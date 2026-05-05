import Foundation

enum APIError: LocalizedError {
  case unauthorized
  case notFound
  case serverError(Int)
  case networkError(Error)
  case decodingError(Error)
  case invalidURL

  var errorDescription: String? {
    switch self {
    case .unauthorized: return "認証エラーが発生しました。再度サインインしてください。"
    case .notFound: return "データが見つかりません。"
    case .serverError(let code): return "サーバーエラーが発生しました（\(code)）。"
    case .networkError(let e): return "ネットワークエラー: \(e.localizedDescription)"
    case .decodingError(let e): return "データの解析に失敗しました: \(e.localizedDescription)"
    case .invalidURL: return "URLが不正です。"
    }
  }
}
