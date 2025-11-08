import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @EnvironmentObject private var languageManager: LanguageManager
  @State private var showingRestartAlert = false
  @State private var selectedNewLanguage: AppLanguage?
  @State private var showingDeleteConfirmation = false
  @State private var isDeleting = false
  @State private var showDeleteSuccessAlert = false
  @State private var showDeleteErrorAlert = false
  @State private var deleteErrorMessage = ""
  
  // AI機能用
  @State private var apiKey: String = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
  @State private var showingAPIKeyInfo = false

  var body: some View {
    NavigationStack {
      Form {
        // AI機能セクション
        Section(header: Text(NSLocalizedString("AI Features", comment: "Settings section"))) {
          VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("OpenAI API Key", comment: "Settings label"))
              .font(.subheadline)
              .foregroundColor(.secondary)
            
            HStack {
              if apiKey.isEmpty {
                SecureField(NSLocalizedString("Enter API Key", comment: "Placeholder"), text: $apiKey)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
              } else {
                SecureField(NSLocalizedString("API Key Set", comment: "Label"), text: $apiKey)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
              }
              
              if !apiKey.isEmpty {
                Button {
                  apiKey = ""
                  UserDefaults.standard.removeObject(forKey: "openai_api_key")
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                }
              }
            }
            
            Button {
              showingAPIKeyInfo = true
            } label: {
              HStack {
                Image(systemName: "info.circle")
                Text(NSLocalizedString("How to get API Key", comment: "Button title"))
              }
              .font(.caption)
              .foregroundColor(.blue)
            }
          }
          .onChange(of: apiKey) { oldValue, newValue in
            if !newValue.isEmpty {
              UserDefaults.standard.set(newValue, forKey: "openai_api_key")
            }
          }
        }
        
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
            Task {
              await deleteAllData()
            }
          },
          secondaryButton: .cancel(Text(NSLocalizedString("Cancel", comment: "Cancel button")))
        )
      }
      .alert(
        NSLocalizedString("Success", comment: "Success alert title"),
        isPresented: $showDeleteSuccessAlert
      ) {
        Button(NSLocalizedString("OK", comment: "Button title"), role: .cancel) {}
      } message: {
        Text(NSLocalizedString("All data has been successfully deleted.", comment: "Success message"))
      }
      .alert(
        NSLocalizedString("Error", comment: "Error alert title"),
        isPresented: $showDeleteErrorAlert
      ) {
        Button(NSLocalizedString("OK", comment: "Button title"), role: .cancel) {}
      } message: {
        Text(deleteErrorMessage)
      }
      .alert(
        NSLocalizedString("How to get API Key", comment: "Alert title"),
        isPresented: $showingAPIKeyInfo
      ) {
        Button(NSLocalizedString("Open OpenAI Website", comment: "Button title")) {
          if let url = URL(string: "https://platform.openai.com/api-keys") {
            UIApplication.shared.open(url)
          }
        }
        Button(NSLocalizedString("Cancel", comment: "Button title"), role: .cancel) {}
      } message: {
        Text(NSLocalizedString("You can get an API key from OpenAI's website. After signing up, go to API Keys section and create a new secret key.", comment: "API key info"))
      }
      .overlay {
        if isDeleting {
          ZStack {
            Color.black.opacity(0.4)
              .ignoresSafeArea()
            VStack {
              ProgressView()
                .scaleEffect(1.5)
                .padding()
              Text(NSLocalizedString("Deleting data...", comment: "Loading message"))
                .foregroundColor(.white)
                .padding()
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
            .shadow(radius: 10)
            .padding(30)
          }
        }
      }
    }
  }

  private func deleteAllData() async {
    // メインスレッドでUIの更新
    await MainActor.run {
      isDeleting = true
      print("Starting data deletion...")
    }
    
    // 少し遅延を入れて、ローディング表示が見えるようにする
    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
    
    let context: ModelContext = modelContext
    do {
      try context.delete(model: LogItem.self)
      try context.delete(model: FoodMaster.self)
      print("All data deleted successfully.")
      
      // メインスレッドでUIの更新
      await MainActor.run {
        isDeleting = false
        showDeleteSuccessAlert = true
      }
    } catch {
      print("Failed to delete data: \(error)")
      
      // メインスレッドでUIの更新
      await MainActor.run {
        isDeleting = false
        deleteErrorMessage = NSLocalizedString("Failed to delete data: ", comment: "Error message") + error.localizedDescription
        showDeleteErrorAlert = true
      }
    }
  }
}
