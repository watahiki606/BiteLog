import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var languageManager: LanguageManager

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text("Language")) {
          ForEach(AppLanguage.allCases) { language in
            Button(action: {
              languageManager.selectedLanguage = language
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
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}
