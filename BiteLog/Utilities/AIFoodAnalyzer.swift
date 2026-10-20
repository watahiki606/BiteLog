import Foundation
import UIKit

// 分析結果の構造体
struct FoodAnalysisResult {
  let productName: String
  let calories: Double
  let protein: Double
  let fat: Double
  let netCarbs: Double
  let dietaryFiber: Double
  let portionAmount: Double
  let portionUnit: String
  let confidence: String
  let basis: AnalysisBasis
  /// 公式の栄養成分を調べる欄に入れておく名前。ロゴや文字が見えなければ nil
  var menuGuess: String? = nil
}

/// 値が何に基づくか。店名を入れたときだけ Web で調べるので、結果画面でそれを見せる。
enum AnalysisBasis: Equatable {
  /// 店名を入れずに解析した。写真の成分表示を読んだ場合もここに入る
  case photoOnly
  /// 店名を入れたが、写真に成分表示があったのでそれを読んだ
  case nutritionLabel
  /// 店名から公式の値を調べた。出典は Worker が検索で実際に見たページのときだけ持つ
  case web(source: URL?)
  /// 店名から調べたが見つからず、写真から推定した
  case estimatedAfterSearch

  init(menuName: String?, basis: String?, sourceUrl: String?) {
    guard menuName != nil else {
      self = .photoOnly
      return
    }
    switch basis {
    case "official": self = .web(source: sourceUrl.flatMap(URL.init(string:)))
    case "label": self = .nutritionLabel
    default: self = .estimatedAfterSearch
    }
  }
}

class AIFoodAnalyzer {
  static let shared = AIFoodAnalyzer()

  private init() {}

  @MainActor
  func isAvailable() -> Bool {
    return AuthManager.shared.isSignedIn
  }

  // 写真から料理を分析
  /// - Parameter menuName: 入れると、Worker が公式の栄養成分を Web で調べる。時間と費用がかかる
  func analyzeFood(image: UIImage, note: String? = nil, menuName: String? = nil) async throws -> FoodAnalysisResult {
    let available = await MainActor.run { AuthManager.shared.isSignedIn }
    guard available else {
      throw AnalysisError.notAuthenticated
    }

    // 画像をリサイズしてBase64に変換
    guard let imageData = Self.resizedForUpload(image, maxPixelSize: Self.uploadMaxPixelSize)
      .jpegData(compressionQuality: 0.8)
    else {
      throw AnalysisError.imageProcessingFailed
    }

    let base64Image = imageData.base64EncodedString()

    do {
      let response = try await APIClient.shared.analyzeFoodImage(
        imageBase64: base64Image, note: note, menuName: menuName)
      return FoodAnalysisResult(
        productName: response.productName,
        calories: response.calories,
        protein: response.protein,
        fat: response.fat,
        netCarbs: response.netCarbs,
        dietaryFiber: response.dietaryFiber,
        portionAmount: response.portionAmount,
        portionUnit: response.portionUnit,
        confidence: response.confidence,
        basis: AnalysisBasis(menuName: menuName, basis: response.basis, sourceUrl: response.sourceUrl),
        menuGuess: response.menuGuess
      )
    } catch APIError.unauthorized {
      throw AnalysisError.notAuthenticated
    } catch APIError.serverError(429) {
      throw AnalysisError.rateLimitExceeded
    } catch {
      throw error
    }
  }

  /// 1024 では成分表示の小さな文字を読み違え、2048 以上では精度が上がらずトークンだけ増えた。
  static let uploadMaxPixelSize: CGFloat = 1536

  /// 長辺が maxPixelSize ピクセルに収まるよう縮める。小さい画像はそのまま返す。
  ///
  /// UIImage.size はポイントなので、倍率を掛けてピクセルで比べる。描くときも倍率 1 にしないと、
  /// UIGraphicsImageRenderer が画面の倍率で描き、iPhone では3倍のピクセル数になる。
  static func resizedForUpload(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage {
    let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    let ratio = min(maxPixelSize / pixelSize.width, maxPixelSize / pixelSize.height)

    if ratio >= 1 {
      return image
    }

    let newSize = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)

    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: newSize))
    }
  }

  // エラー定義
  enum AnalysisError: LocalizedError {
    case notAuthenticated
    case imageProcessingFailed
    case invalidResponse
    case rateLimitExceeded
    case apiError(statusCode: Int)
    case noContent
    case invalidJSONResponse

    var errorDescription: String? {
      switch self {
      case .notAuthenticated:
        return NSLocalizedString("AI food analysis requires sign-in.", comment: "Error message")
      case .imageProcessingFailed:
        return NSLocalizedString("Failed to process image.", comment: "Error message")
      case .invalidResponse:
        return NSLocalizedString("Invalid response from API.", comment: "Error message")
      case .rateLimitExceeded:
        return NSLocalizedString("API rate limit exceeded. Please try again later.", comment: "Error message")
      case .apiError(let statusCode):
        return String(format: NSLocalizedString("API error (status code: %d)", comment: "Error message"), statusCode)
      case .noContent:
        return NSLocalizedString("No content returned from API.", comment: "Error message")
      case .invalidJSONResponse:
        return NSLocalizedString("Failed to parse API response.", comment: "Error message")
      }
    }
  }
}

extension AIFoodAnalyzer {
  /// AI が付けた長い名前から、既存の食品を探すための短い語を取り出す。
  ///
  ///     「おにぎり 昆布」                → 「おにぎり」
  ///     「カフェオレ（微糖、200ml）」       → 「カフェオレ」
  ///     「定食（ご飯＋汁物）」              → 「定食」
  ///
  /// 名前をそのまま検索語にすると当たらない。AI は写真ごとに違う言い回しを返すので、
  /// 同じおにぎりでも「NL」と「国産」で別物になる。区切りの手前までを使う。
  /// 結果画面の「登録済みの食品」を探す語。見当の店名とメニュー名で先に探し、
  /// 当たらなければ料理名の頭で探す。1文字だと関係の無い食品が大量に当たるので使わない。
  static func candidateQueries(menuGuess: String?, productName: String) -> [String] {
    var queries: [String] = []
    for query in [menuGuess?.trimmingCharacters(in: .whitespaces) ?? "", searchTerm(for: productName)]
    where query.count >= 2 && !queries.contains(query) {
      queries.append(query)
    }
    return queries
  }

  static func searchTerm(for productName: String) -> String {
    let separators = CharacterSet(charactersIn: " 　（(【[｛{、，,・/＋+&")
    let head =
      productName
      .components(separatedBy: separators)
      .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      ?? productName
    return head.trimmingCharacters(in: .whitespaces)
  }
}
