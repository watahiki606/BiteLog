import Foundation

enum APIError: LocalizedError {
  case unauthorized
  case notFound
  case serverError(Int)
  /// 409。何と重なったかを呼ぶ側が読めるよう、本文を持たせる
  case conflict(Data)
  case networkError(Error)
  case decodingError(Error)
  case invalidURL

  /// 画面に出す文面。アラートやエラー表示にそのまま載るので、
  /// 英語表示のユーザーに日本語が出ないよう必ずローカライズ資材から引く。
  var errorDescription: String? {
    switch self {
    case .unauthorized:
      return NSLocalizedString(
        "Your session has expired. Please sign in again.", comment: "API error")
    case .notFound:
      return NSLocalizedString("The data could not be found.", comment: "API error")
    case .serverError(let code):
      return String(
        format: NSLocalizedString("The server returned an error (%d).", comment: "API error"), code)
    case .conflict:
      return NSLocalizedString("The same data is already registered.", comment: "API error")
    case .networkError:
      return NSLocalizedString(
        "Couldn't reach the server. Check your connection.", comment: "API error")
    case .decodingError:
      return NSLocalizedString("The response couldn't be read.", comment: "API error")
    case .invalidURL:
      return NSLocalizedString("The request address is invalid.", comment: "API error")
    }
  }
}

/// 食品を作ろうとしたら、同じブランド名・商品名・単位の食品が既にあった。
///
/// 送った値で作れたことにはならないので、呼ぶ側は登録済みの食品を使うか、
/// 名前か単位を変えて作り直すかを選ばせる。
struct FoodMasterExistsError: LocalizedError {
  let existing: FoodMasterDTO

  init(conflictBody: Data) throws {
    struct Body: Decodable { let existing: FoodMasterDTO }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    existing = try decoder.decode(Body.self, from: conflictBody).existing
  }

  var errorDescription: String? {
    NSLocalizedString(
      "A food with the same brand, name, and unit is already registered.", comment: "Food master conflict")
  }
}
