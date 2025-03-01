import SwiftData
import SwiftUI

@main
struct BiteLogApp: App {
  @StateObject private var languageManager = LanguageManager()

  var sharedModelContainer: ModelContainer = {
    let schema = Schema([
      Item.self
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
    }
    .modelContainer(sharedModelContainer)
  }
}
