import Foundation

enum APIError: LocalizedError {
  case unauthorized
  case notFound
  case serverError(Int)
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
