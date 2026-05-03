import AuthenticationServices
import SwiftUI

struct LoginView: View {
  @StateObject private var authManager = AuthManager.shared
  @State private var isSigningIn = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 40) {
      Spacer()

      VStack(spacing: 12) {
        Image(systemName: "fork.knife.circle.fill")
          .font(.system(size: 80))
          .foregroundColor(.accentColor)

        Text("BiteLog")
          .font(.largeTitle.bold())

        Text(NSLocalizedString("Track your meals and nutrition", comment: "App description"))
          .font(.subheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }

      Spacer()

      VStack(spacing: 16) {
        if isSigningIn {
          ProgressView()
            .scaleEffect(1.2)
        } else {
          SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
          } onCompletion: { result in
            handleAppleSignIn(result)
          }
          .signInWithAppleButtonStyle(.black)
          .frame(height: 50)
          .cornerRadius(10)

          #if DEBUG
          Button("Debug: Skip Sign In") {
            // Workers に認証なしでアクセスするためのデバッグ用ダミートークン
            // Workers側で "debug-bypass" を許可する必要あり
            debugSignIn()
          }
          .font(.footnote)
          .foregroundColor(.secondary)
          #endif
        }

        if let error = errorMessage {
          Text(error)
            .font(.caption)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 40)

      Spacer()
        .frame(height: 40)
    }
    .padding()
  }

  #if DEBUG
  private func debugSignIn() {
    isSigningIn = true
    Task {
      do {
        let response = try await APIClient.shared.signIn(provider: "debug", identityToken: "debug-bypass-token")
        AuthManager.shared.storeToken(response.token)
      } catch {
        errorMessage = "Debug sign in failed: \(error.localizedDescription)"
      }
      isSigningIn = false
    }
  }
  #endif

  private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
    switch result {
    case .success(let auth):
      guard
        let credential = auth.credential as? ASAuthorizationAppleIDCredential,
        let tokenData = credential.identityToken,
        let identityToken = String(data: tokenData, encoding: .utf8)
      else {
        errorMessage = "サインインに失敗しました"
        return
      }

      isSigningIn = true
      errorMessage = nil

      Task {
        do {
          let response = try await APIClient.shared.signIn(provider: "apple", identityToken: identityToken)
          AuthManager.shared.storeToken(response.token)
        } catch {
          errorMessage = error.localizedDescription
        }
        isSigningIn = false
      }

    case .failure(let error):
      if (error as? ASAuthorizationError)?.code != .canceled {
        errorMessage = error.localizedDescription
      }
    }
  }
}
