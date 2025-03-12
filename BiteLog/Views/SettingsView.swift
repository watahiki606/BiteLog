import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @EnvironmentObject private var languageManager: LanguageManager
  @State private var showingRestartAlert = false
  @State private var selectedNewLanguage: AppLanguage?
  @State private var showingDeleteConfirmation = false

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text(NSLocalizedString("Language", comment: "Settings section"))) {
          ForEach(AppLanguage.allCases, id: \.self) { language in
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

        Section(header: Text(NSLocalizedString("Data Management", comment: "Data management section"))) {
          NavigationLink(destination: ImportCSVView()) {
            Text(NSLocalizedString("Import CSV", comment: "Import CSV"))
          }
          
          NavigationLink(destination: ExportCSVView()) {
            Text(NSLocalizedString("Export CSV", comment: "Export CSV"))
          }
          
          Button(
            role: .destructive,
            action: {
              showingDeleteConfirmation = true
            }
          ) {
            Text(NSLocalizedString("Delete All Data", comment: "Delete all data"))
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
      .alert(isPresented: $showingDeleteConfirmation) {
        Alert(
          title: Text(NSLocalizedString("Delete All Data?", comment: "Delete confirmation title")),
          message: Text(NSLocalizedString("Are you sure you want to delete all data? This action cannot be undone.", comment: "Delete confirmation message")),
          primaryButton: .destructive(Text(NSLocalizedString("Delete", comment: "Delete button"))) {
            deleteAllData()
          },
          secondaryButton: .cancel(Text(NSLocalizedString("Cancel", comment: "Cancel button")))
        )
      }
    }
  }

  private func deleteAllData() {
    let context: ModelContext = modelContext
    do {
      try context.delete(model: LogItem.self)
      try context.delete(model: FoodMaster.self)
      print("All data deleted successfully.")
    } catch {
      print("Failed to delete data: \(error)")
    }
  }
}
