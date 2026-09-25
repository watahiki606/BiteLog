import SwiftUI

extension Notification.Name {
  static let allDataDeleted = Notification.Name("allDataDeleted")
}

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var languageManager: LanguageManager
  @EnvironmentObject private var nutritionGoalsManager: NutritionGoalsManager
  @State private var showingDeleteConfirmation = false
  @State private var isDeleting = false
  @State private var showDeleteSuccessAlert = false
  @State private var showDeleteErrorAlert = false
  @State private var showingSignOutConfirmation = false
  @State private var deleteErrorMessage = ""

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Button(action: { languageManager.openSystemSettings() }) {
            LabeledContent {
              HStack(spacing: 6) {
                Text(languageManager.currentLanguageName)
                Image(systemName: "arrow.up.forward.app")
                  .font(.footnote)
                  .accessibilityHidden(true)
              }
              .foregroundStyle(.secondary)
            } label: {
              Text(NSLocalizedString("Language", comment: "Settings section"))
                .foregroundStyle(.primary)
            }
          }
        } footer: {
          Text(
            NSLocalizedString(
              "Change the language in the Settings app, under Preferred Language.",
              comment: "Language settings footer"))
        }

        Section(header: Text(NSLocalizedString("Nutrition Goals", comment: "Nutrition goals section"))) {
          NavigationLink(destination: NutritionGoalsEditView()) {
            Text(NSLocalizedString("Daily Nutrition Goals", comment: "Nutrition goals link"))
          }
        }

        Section(header: Text(NSLocalizedString("Data Management", comment: "Data management section"))) {
          NavigationLink(destination: ImportCSVView()) {
            Text(NSLocalizedString("Import CSV", comment: "Import CSV"))
          }
          NavigationLink(destination: ExportCSVView()) {
            Text(NSLocalizedString("Export CSV", comment: "Export CSV"))
          }
          Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
            Text(NSLocalizedString("Delete All Data", comment: "Delete all data"))
          }
        }

        Section(header: Text(NSLocalizedString("Account", comment: "Account settings section"))) {
          Button(role: .destructive, action: { showingSignOutConfirmation = true }) {
            Text(NSLocalizedString("Sign Out", comment: "Sign out button"))
          }
        }
      }
      .navigationTitle(NSLocalizedString("Settings", comment: "Navigation title"))
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(NSLocalizedString("Done", comment: "Button title")) { dismiss() }
        }
      }
      // 目標の編集は画面を離れたときに保存するので、失敗を伝える頃には
      // その画面が無い。まだ出ている設定画面から出す。
      .operationFailureAlert($nutritionGoalsManager.saveFailure)
      .alert(
        NSLocalizedString("Delete All Data?", comment: "Delete confirmation title"),
        isPresented: $showingDeleteConfirmation
      ) {
        Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
          Task { await deleteAllData() }
        }
        Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
      } message: {
        Text(NSLocalizedString(
          "Are you sure you want to delete all data? This action cannot be undone.",
          comment: "Delete confirmation message"))
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
        NSLocalizedString("Sign Out?", comment: "Sign out confirmation title"),
        isPresented: $showingSignOutConfirmation
      ) {
        Button(NSLocalizedString("Sign Out", comment: "Sign out button"), role: .destructive) {
          AuthManager.shared.signOut()
          dismiss()
        }
        Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
      } message: {
        Text(NSLocalizedString(
          "You will return to the sign-in screen.",
          comment: "Sign out confirmation message"))
      }
      .overlay {
        if isDeleting {
          ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack {
              ProgressView().scaleEffect(1.5).padding()
              Text(NSLocalizedString("Deleting data...", comment: "Loading message"))
                .foregroundColor(.white).padding()
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
    await MainActor.run { isDeleting = true }
    try? await Task.sleep(nanoseconds: 500_000_000)
    do {
      if AuthManager.shared.isAdmin {
        try await APIClient.shared.deleteAllDataAsAdmin()
      } else {
        try await APIClient.shared.deleteAllUserData()
      }
      await MainActor.run {
        isDeleting = false
        showDeleteSuccessAlert = true
        NotificationCenter.default.post(name: .allDataDeleted, object: nil)
      }
    } catch {
      await MainActor.run {
        isDeleting = false
        deleteErrorMessage = NSLocalizedString("Failed to delete data: ", comment: "Error message")
          + error.localizedDescription
        showDeleteErrorAlert = true
      }
    }
  }
}
