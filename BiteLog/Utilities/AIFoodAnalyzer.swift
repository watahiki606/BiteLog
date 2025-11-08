import Foundation
import UIKit

// OpenAI APIのレスポンス構造体
struct OpenAIResponse: Codable {
  let choices: [Choice]
  
  struct Choice: Codable {
    let message: Message
  }
  
  struct Message: Codable {
    let content: String
  }
}

// 分析結果の構造体
struct FoodAnalysisResult {
  let productName: String
  let calories: Double
  let protein: Double
  let fat: Double
  let sugar: Double
  let dietaryFiber: Double
  let portion: Double
  let portionUnit: String
  let confidence: String
}

class AIFoodAnalyzer {
  static let shared = AIFoodAnalyzer()
  
  private init() {}
  
  // APIキーを取得
  private var apiKey: String? {
    return UserDefaults.standard.string(forKey: "openai_api_key")
  }
  
  // APIキーが設定されているか確認
  func isAPIKeyConfigured() -> Bool {
    guard let key = apiKey, !key.isEmpty else {
      return false
    }
    return true
  }
  
  // 写真から料理を分析
  func analyzeFood(image: UIImage) async throws -> FoodAnalysisResult {
    guard let apiKey = apiKey, !apiKey.isEmpty else {
      throw AnalysisError.apiKeyNotConfigured
    }
    
    // 画像をリサイズしてBase64に変換
    guard let resizedImage = resizeImage(image, maxSize: 1024),
          let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
      throw AnalysisError.imageProcessingFailed
    }
    
    let base64Image = imageData.base64EncodedString()
    
    // OpenAI APIリクエストを構築
    let url = URL(string: "https://api.openai.com/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    // プロンプトを構築
    let prompt = """
    この料理の写真を分析して、以下の情報をJSON形式で返してください。
    
    必ず以下の形式で回答してください（他のテキストは含めないでください）：
    {
      "productName": "料理名（日本語）",
      "calories": カロリー（kcal、数値のみ）,
      "protein": タンパク質（g、数値のみ）,
      "fat": 脂質（g、数値のみ）,
      "sugar": 糖質（g、数値のみ）,
      "dietaryFiber": 食物繊維（g、数値のみ）,
      "portion": 分量（数値のみ）,
      "portionUnit": 分量の単位（例：g、個、人前）,
      "confidence": 推定の信頼度（"high", "medium", "low"のいずれか）
    }
    
    注意事項：
    - カロリーと栄養素は一般的な1人前の量で推定してください
    - 料理が複数ある場合は、全体の合計値を返してください
    - 正確な値がわからない場合は、一般的な値を推定してください
    - JSON形式のみを返し、他の説明文は含めないでください
    """
    
    let requestBody: [String: Any] = [
      "model": "gpt-4o-mini",
      "messages": [
        [
          "role": "user",
          "content": [
            [
              "type": "text",
              "text": prompt
            ],
            [
              "type": "image_url",
              "image_url": [
                "url": "data:image/jpeg;base64,\(base64Image)"
              ]
            ]
          ]
        ]
      ],
      "max_tokens": 500,
      "temperature": 0.3
    ]
    
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    
    // APIリクエストを送信
    let (data, response) = try await URLSession.shared.data(for: request)
    
    // レスポンスを確認
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AnalysisError.invalidResponse
    }
    
    guard httpResponse.statusCode == 200 else {
      if httpResponse.statusCode == 401 {
        throw AnalysisError.invalidAPIKey
      } else if httpResponse.statusCode == 429 {
        throw AnalysisError.rateLimitExceeded
      }
      throw AnalysisError.apiError(statusCode: httpResponse.statusCode)
    }
    
    // レスポンスをデコード
    let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
    
    guard let content = openAIResponse.choices.first?.message.content else {
      throw AnalysisError.noContent
    }
    
    // JSON部分を抽出（```json```で囲まれている場合もあるため）
    let jsonString = extractJSON(from: content)
    
    // JSONをパース
    guard let jsonData = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
      throw AnalysisError.invalidJSONResponse
    }
    
    // 結果を構築
    let result = FoodAnalysisResult(
      productName: json["productName"] as? String ?? "不明な料理",
      calories: json["calories"] as? Double ?? 0,
      protein: json["protein"] as? Double ?? 0,
      fat: json["fat"] as? Double ?? 0,
      sugar: json["sugar"] as? Double ?? 0,
      dietaryFiber: json["dietaryFiber"] as? Double ?? 0,
      portion: json["portion"] as? Double ?? 1,
      portionUnit: json["portionUnit"] as? String ?? "人前",
      confidence: json["confidence"] as? String ?? "medium"
    )
    
    return result
  }
  
  // 画像をリサイズ
  private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage? {
    let size = image.size
    let ratio = min(maxSize / size.width, maxSize / size.height)
    
    if ratio >= 1 {
      return image
    }
    
    let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
    
    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return newImage
  }
  
  // JSON部分を抽出
  private func extractJSON(from text: String) -> String {
    // ```json と ``` で囲まれている場合
    if let jsonStart = text.range(of: "```json"),
       let jsonEnd = text.range(of: "```", range: jsonStart.upperBound..<text.endIndex) {
      return String(text[jsonStart.upperBound..<jsonEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // { と } で囲まれた部分を抽出
    if let jsonStart = text.range(of: "{"),
       let jsonEnd = text.range(of: "}", options: .backwards),
       jsonStart.lowerBound < jsonEnd.upperBound {
      // 安全に範囲を作成
      let range = jsonStart.lowerBound..<jsonEnd.upperBound
      return String(text[range])
    }
    
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  // エラー定義
  enum AnalysisError: LocalizedError {
    case apiKeyNotConfigured
    case imageProcessingFailed
    case invalidResponse
    case invalidAPIKey
    case rateLimitExceeded
    case apiError(statusCode: Int)
    case noContent
    case invalidJSONResponse
    
    var errorDescription: String? {
      switch self {
      case .apiKeyNotConfigured:
        return NSLocalizedString("OpenAI API key is not configured. Please set it in Settings.", comment: "Error message")
      case .imageProcessingFailed:
        return NSLocalizedString("Failed to process image.", comment: "Error message")
      case .invalidResponse:
        return NSLocalizedString("Invalid response from API.", comment: "Error message")
      case .invalidAPIKey:
        return NSLocalizedString("Invalid API key. Please check your API key in Settings.", comment: "Error message")
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

