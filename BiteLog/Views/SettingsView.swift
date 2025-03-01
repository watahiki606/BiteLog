import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var languageManager: LanguageManager
  @State private var showingRestartAlert = false
  @State private var selectedNewLanguage: AppLanguage?

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text(NSLocalizedString("Language", comment: "Settings section"))) {
          ForEach(AppLanguage.allCases) { language in
            Button(action: {
              if languageManager.selectedLanguage != language {
                selectedNewLanguage = language
                showingRestartAlert = true
              }
            }) {
              HStack {
                Text(language.displayName)
                Spacer()
                if languageManager.selectedLanguage == language {
                  Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                }
              }
            }
            .foregroundColor(.primary)
          }
        }
      }
      .navigationTitle(NSLocalizedString("Settings", comment: "Navigation title"))
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(NSLocalizedString("Done", comment: "Button title")) {
            dismiss()
          }
        }
      }
      .alert(
        NSLocalizedString("Language Changed", comment: "Alert title"),
        isPresented: $showingRestartAlert
      ) {
        Button(NSLocalizedString("Apply", comment: "Button title")) {
          if let language = selectedNewLanguage {
            languageManager.selectedLanguage = language
          }
          // アプリの再起動をシミュレート
          exit(0)
        }
        Button(NSLocalizedString("Cancel", comment: "Button title"), role: .cancel) {
          selectedNewLanguage = nil
        }
      } message: {
        Text(
          NSLocalizedString(
            "The app needs to restart to apply the language change. Restart now?",
            comment: "Alert message"))
      }
    }
  }
}
