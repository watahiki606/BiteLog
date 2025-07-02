import SwiftData
import SwiftUI

@main
struct BiteLogApp: App {
  @StateObject private var languageManager = LanguageManager()

  init() {
    // TODO: AdMob初期化でクラッシュが発生中
    // 原因: GADApplicationIdentifierがInfo.plistに設定されていない
    // 解決策: Info.plist設定修正 or AdMobアカウント作成後の実際のID設定
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
