import SwiftData
import SwiftUI

@main
struct BiteLogApp: App {
  @StateObject private var languageManager = LanguageManager()
  @StateObject private var nutritionGoalsManager = NutritionGoalsManager()

  init() {
    // AdMob初期化（SDK v12対応済み）
    // GADApplicationIdentifierはInfo.plistで設定済み
    AdMobManager.shared.initialize()
  }

  var sharedModelContainer: ModelContainer = {
    let schema = Schema([
      FoodMaster.self,
      LogItem.self,
    ])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

    do {
      return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .tint(Color.accentColor)
        .environment(\.locale, languageManager.locale)
        .environmentObject(languageManager)
        .environmentObject(nutritionGoalsManager)
        .id(languageManager.selectedLanguage)
        .onAppear {
          // App Tracking Transparencyのリクエスト
          AdMobManager.shared.requestTrackingAuthorization { authorized in
            print("Tracking authorization status: \(authorized)")
          }
        }
    }
    .modelContainer(sharedModelContainer)
  }
}
