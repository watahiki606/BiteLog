import GoogleSignIn
import SwiftUI

@main
struct BiteLogApp: App {
  @StateObject private var languageManager = LanguageManager()
  @StateObject private var nutritionGoalsManager = NutritionGoalsManager()
  @StateObject private var authManager = AuthManager.shared
  @StateObject private var adMobManager = AdMobManager.shared

  var body: some Scene {
    WindowGroup {
      Group {
        if authManager.isSignedIn {
          ContentView()
            .environmentObject(languageManager)
            .environmentObject(nutritionGoalsManager)
            .onAppear {
              Task { await nutritionGoalsManager.fetch() }
              adMobManager.prepareAfterLaunch()
            }
        } else {
          LoginView()
            .environmentObject(languageManager)
        }
      }
      .tint(Color.accentColor)
      .environment(\.locale, languageManager.locale)
      .id(languageManager.selectedLanguage)
      .onOpenURL { url in
        _ = AuthManager.handleGoogleSignInCallback(url)
      }
    }
  }
}
