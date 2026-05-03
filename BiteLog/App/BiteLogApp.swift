import GoogleSignIn
import SwiftUI

@main
struct BiteLogApp: App {
  @StateObject private var languageManager = LanguageManager()
  @StateObject private var nutritionGoalsManager = NutritionGoalsManager()
  @StateObject private var authManager = AuthManager.shared

  init() {
    AdMobManager.shared.initialize()
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if authManager.isSignedIn {
          ContentView()
            .environmentObject(languageManager)
            .environmentObject(nutritionGoalsManager)
            .onAppear {
              Task { await nutritionGoalsManager.fetch() }
            }
        } else {
          LoginView()
            .environmentObject(languageManager)
        }
      }
      .tint(Color.accentColor)
      .environment(\.locale, languageManager.locale)
      .id(languageManager.selectedLanguage)
      .onAppear {
        AdMobManager.shared.requestTrackingAuthorization { authorized in
          print("Tracking authorization status: \(authorized)")
        }
      }
      .onOpenURL { url in
        _ = AuthManager.handleGoogleSignInCallback(url)
      }
    }
  }
}
