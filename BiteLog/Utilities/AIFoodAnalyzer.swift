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
  private var apiKey: String {
    return APIKeys.openAI
  }
  
  // APIキーが設定されているか確認
  func isAPIKeyConfigured() -> Bool {
    // プレースホルダーでないかチェック
    let key = apiKey
    return !key.isEmpty && 
           key != "YOUR_OPENAI_API_KEY_HERE" && 
           key != "あなたのAPIキーをここに入力してください"
  }
  
  // 写真から料理を分析
  func analyzeFood(image: UIImage) async throws -> FoodAnalysisResult {
    guard isAPIKeyConfigured() else {
      throw AnalysisError.apiKeyNotConfigured
    }
    
    let apiKey = self.apiKey
    
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
    Analyze this image and return nutrition information in JSON format.
    
    IMPORTANT - Nutrition Label Reading:
    If the image contains a nutrition facts label (package/product label), prioritize reading the text:
    - Calories/Energy/カロリー/熱量
    - Protein/たんぱく質/タンパク質
    - Fat/脂質
    - Sugar/Carbohydrate/糖質
    - Dietary Fiber/食物繊維
    - Total Carbohydrates/炭水化物
    If "糖質" and "食物繊維" are both listed, use those values directly. If only "炭水化物" is listed, set sugar = 炭水化物 and dietaryFiber = 0.
    If a nutrition label is present, set confidence to "high".
    
    Return ONLY this JSON format (no other text):
    {
      "productName": "Product or dish name in Japanese",
      "calories": number in kcal,
      "protein": number in grams,
      "fat": number in grams,
      "sugar": number in grams,
      "dietaryFiber": number in grams,
      "portion": portion amount (number),
      "portionUnit": "unit (e.g., g, ml, 個, 人前)",
      "confidence": "high" or "medium" or "low"
    }
    
    Rules:
    - If nutrition label exists, read and use those exact values
    - For food photos without labels, estimate typical serving size
    - For multiple items, sum the total values
    - Return JSON only, no explanations
    """
    
    let requestBody: [String: Any] = [
      "model": "gpt-5-mini",
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
      "max_completion_tokens": 4096
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
    let renderer = UIGraphicsImageRenderer(size: newSize)
    
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: newSize))
    }
  }
  
  // JSON部分を抽出
  private func extractJSON(from text: String) -> String {
    // ```json と ``` で囲まれている場合
    if let jsonStart = text.range(of: "```json"),
       let jsonEnd = text.range(of: "```", range: jsonStart.upperBound..<text.endIndex) {
      return String(text[jsonStart.upperBound..<jsonEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // { と } で囲まれた部分を抽出（ネスト対応）
    if let jsonStart = text.firstIndex(of: "{") {
      var braceCount = 0
      var jsonEnd: String.Index?
      var isInString = false
      var previousChar: Character?
      
      for index in text[jsonStart...].indices {
        let char = text[index]
        
        // 文字列リテラル内かどうかを判定（エスケープされた引用符を考慮）
        if char == "\"" && previousChar != "\\" {
          isInString.toggle()
        }
        
        // 文字列リテラル内でない場合のみブレースをカウント
        if !isInString {
          if char == "{" {
            braceCount += 1
          } else if char == "}" {
            braceCount -= 1
            if braceCount == 0 {
              jsonEnd = index
              break
            }
          }
        }
        
        previousChar = char
      }
      
      if let end = jsonEnd {
        return String(text[jsonStart...end])
      }
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

