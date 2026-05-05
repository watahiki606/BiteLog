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
}

class AIFoodAnalyzer {
  static let shared = AIFoodAnalyzer()

  private init() {}

  @MainActor
  func isAvailable() -> Bool {
    return AuthManager.shared.isSignedIn
  }

  // 写真から料理を分析
  func analyzeFood(image: UIImage) async throws -> FoodAnalysisResult {
    let available = await MainActor.run { AuthManager.shared.isSignedIn }
    guard available else {
      throw AnalysisError.notAuthenticated
    }

    // 画像をリサイズしてBase64に変換
    guard let resizedImage = resizeImage(image, maxSize: 1024),
          let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
      throw AnalysisError.imageProcessingFailed
    }

    let base64Image = imageData.base64EncodedString()

    do {
      let response = try await APIClient.shared.analyzeFoodImage(imageBase64: base64Image)
      return FoodAnalysisResult(
        productName: response.productName,
        calories: response.calories,
        protein: response.protein,
        fat: response.fat,
        netCarbs: response.netCarbs,
        dietaryFiber: response.dietaryFiber,
        portionAmount: response.portionAmount,
        portionUnit: response.portionUnit,
        confidence: response.confidence
      )
    } catch APIError.unauthorized {
      throw AnalysisError.notAuthenticated
    } catch APIError.serverError(429) {
      throw AnalysisError.rateLimitExceeded
    } catch {
      throw error
    }
  }

  // 画像をリサイズ
  private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage? {
    let size = image.size
    let ratio = min(maxSize / size.width, maxSize / size.height)

    if ratio >= 1 {
      return image
    }

    let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
    let renderer = UIGraphicsImageRenderer(size: newSize)

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
