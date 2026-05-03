import AuthenticationServices
import Foundation
import GoogleSignIn
import Security
import UIKit

/// Apple/Google Sign In を管理し、セッションJWTをKeychainに保存する
@MainActor
final class AuthManager: NSObject, ObservableObject {
  static let shared = AuthManager()

  @Published private(set) var isSignedIn: Bool = false
  @Published private(set) var userId: String?

  private let keychainKey = "com.watahiki.BiteLog.sessionToken"

  override init() {
    super.init()
    // 起動時にKeychainからトークンを復元
    if let token = loadTokenFromKeychain() {
      self.isSignedIn = true
      // JWTのペイロードからuserIdを取得
      self.userId = extractUserId(from: token)
    }
  }

  // MARK: - Token

  var sessionToken: String? {
    loadTokenFromKeychain()
  }

  func storeToken(_ token: String) {
    saveTokenToKeychain(token)
    self.userId = extractUserId(from: token)
    self.isSignedIn = true
  }

  func signOut() {
    deleteTokenFromKeychain()
    self.isSignedIn = false
    self.userId = nil
  }

  // MARK: - Apple Sign In

  func signInWithApple() async throws {
    let provider = ASAuthorizationAppleIDProvider()
    let request = provider.createRequest()
    request.requestedScopes = [.fullName, .email]

    let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
      let controller = ASAuthorizationController(authorizationRequests: [request])
      let delegate = AppleSignInDelegate(continuation: continuation)
      controller.delegate = delegate
      controller.presentationContextProvider = delegate
      controller.performRequests()
      // delegateを保持
      objc_setAssociatedObject(controller, &AssociatedKeys.delegate, delegate, .OBJC_ASSOCIATION_RETAIN)
    }

    guard
      let credential = result.credential as? ASAuthorizationAppleIDCredential,
      let tokenData = credential.identityToken,
      let identityToken = String(data: tokenData, encoding: .utf8)
    else {
      throw APIError.unauthorized
    }

    let authResponse = try await APIClient.shared.signIn(provider: "apple", identityToken: identityToken)
    storeToken(authResponse.token)
  }

  // MARK: - Google Sign In

  func signInWithGoogle() async throws {
    guard
      let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
      !clientID.isEmpty,
      !clientID.hasPrefix("YOUR_")
    else {
      throw AuthError.missingGoogleClientID
    }

    if let expectedScheme = Self.googleRedirectScheme(for: clientID),
      !Self.bundleURLSchemes.contains(expectedScheme)
    {
      throw AuthError.missingGoogleURLScheme(expectedScheme)
    }

    let serverClientID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String
    let normalizedServerClientID =
      serverClientID?.isEmpty == false && serverClientID?.hasPrefix("YOUR_") == false
      ? serverClientID
      : nil

    let configuration = GIDConfiguration(
      clientID: clientID,
      serverClientID: normalizedServerClientID
    )
    GIDSignIn.sharedInstance.configuration = configuration

    guard let presentingViewController = Self.presentingViewController else {
      throw AuthError.presentationAnchorUnavailable
    }

    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

    guard let identityToken = result.user.idToken?.tokenString else {
      throw APIError.unauthorized
    }

    let authResponse = try await APIClient.shared.signIn(provider: "google", identityToken: identityToken)
    storeToken(authResponse.token)
  }

  static func handleGoogleSignInCallback(_ url: URL) -> Bool {
    GIDSignIn.sharedInstance.handle(url)
  }

  // MARK: - Keychain

  private func saveTokenToKeychain(_ token: String) {
    let data = token.data(using: .utf8)!
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: keychainKey,
      kSecValueData: data,
    ]
    SecItemDelete(query as CFDictionary)
    SecItemAdd(query as CFDictionary, nil)
  }

  private func loadTokenFromKeychain() -> String? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: keychainKey,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let token = String(data: data, encoding: .utf8)
    else { return nil }
    return token
  }

  private func deleteTokenFromKeychain() {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: keychainKey,
    ]
    SecItemDelete(query as CFDictionary)
  }

  private func extractUserId(from token: String) -> String? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var base64 = String(parts[1])
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }
    guard let data = Data(base64Encoded: base64),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let sub = json["sub"] as? String
    else { return nil }
    return sub
  }

  private static var presentingViewController: UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let keyWindow = scenes.flatMap(\.windows).first { $0.isKeyWindow }
    var controller = keyWindow?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }

  private static var bundleURLSchemes: Set<String> {
    guard
      let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
        as? [[String: Any]]
    else { return [] }

    return Set(urlTypes.flatMap { urlType in
      urlType["CFBundleURLSchemes"] as? [String] ?? []
    })
  }

  private static func googleRedirectScheme(for clientID: String) -> String? {
    let suffix = ".apps.googleusercontent.com"
    guard clientID.hasSuffix(suffix) else { return nil }
    let appID = clientID.dropLast(suffix.count)
    return "com.googleusercontent.apps.\(appID)"
  }
}

enum AuthError: LocalizedError {
  case missingGoogleClientID
  case missingGoogleURLScheme(String)
  case presentationAnchorUnavailable

  var errorDescription: String? {
    switch self {
    case .missingGoogleClientID:
      return "Google Sign-In の GIDClientID が Info.plist に設定されていません。"
    case .missingGoogleURLScheme(let scheme):
      return "Google Sign-In の URL Scheme が Info.plist に設定されていません: \(scheme)"
    case .presentationAnchorUnavailable:
      return "サインイン画面を表示できませんでした。"
    }
  }
}

// MARK: - Apple Sign In Delegate

private enum AssociatedKeys {
  static var delegate = "delegate"
}

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding
{
  private let continuation: CheckedContinuation<ASAuthorization, Error>

  init(continuation: CheckedContinuation<ASAuthorization, Error>) {
    self.continuation = continuation
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    continuation.resume(returning: authorization)
  }

  func authorizationController(
    controller: ASAuthorizationController, didCompleteWithError error: Error
  ) {
    continuation.resume(throwing: error)
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first?.windows.first { $0.isKeyWindow } ?? UIWindow()
  }
}
