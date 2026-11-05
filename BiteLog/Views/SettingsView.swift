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
              SettingsRowLabel(
                NSLocalizedString("Language", comment: "Settings section"),
                systemImage: "globe", color: .blue)
            }
          }
          // 既定のままだと行のラベルまで着色され、同じ Form の中で
          // 遷移する他の行と見た目が揃わない。外に出ることは末尾の記号で示す。
          .buttonStyle(.plain)
        } footer: {
          Text(
            NSLocalizedString(
              "Change the language in the Settings app, under Preferred Language.",
              comment: "Language settings footer"))
        }

        Section(header: Text(NSLocalizedString("Nutrition Goals", comment: "Nutrition goals section"))) {
          NavigationLink(destination: NutritionGoalsEditView()) {
            SettingsRowLabel(
              NSLocalizedString("Daily Nutrition Goals", comment: "Nutrition goals link"),
              systemImage: "target", color: .red)
          }
        }

        Section(header: Text(NSLocalizedString("Data Management", comment: "Data management section"))) {
          NavigationLink(destination: ImportCSVView()) {
            SettingsRowLabel(
              NSLocalizedString("Import CSV", comment: "Import CSV"),
              systemImage: "square.and.arrow.down", color: .green)
          }
          NavigationLink(destination: ExportCSVView()) {
            SettingsRowLabel(
              NSLocalizedString("Export CSV", comment: "Export CSV"),
              systemImage: "square.and.arrow.up", color: .teal)
          }
          NavigationLink(destination: ScaleImportView()) {
            SettingsRowLabel(
              NSLocalizedString("Scale Setup", comment: "Scale setup title"),
              systemImage: "scalemass.fill", color: .purple)
          }
          Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
            SettingsRowLabel(
              NSLocalizedString("Delete All Data", comment: "Delete all data"),
              systemImage: "trash.fill", color: .red)
          }
        }

        Section(header: Text(NSLocalizedString("Account", comment: "Account settings section"))) {
          Button(role: .destructive, action: { showingSignOutConfirmation = true }) {
            SettingsRowLabel(
              NSLocalizedString("Sign Out", comment: "Sign out button"),
              systemImage: "rectangle.portrait.and.arrow.right", color: .red)
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

/// 設定の1行。淡い色の角丸に入れたアイコンを行頭に置く。
///
/// 文字だけの行が続くと、目的の項目を見つけるのに上から全部読むことになる。
/// 行ごとに色と形を変えておけば、2回目からは形で探せる。
struct SettingsRowLabel: View {
  let title: String
  let systemImage: String
  let color: Color

  @Environment(\.colorSchemeContrast) private var contrast
  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 30

  init(_ title: String, systemImage: String, color: Color) {
    self.title = title
    self.systemImage = systemImage
    self.color = color
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .frame(width: iconSize, height: iconSize)
        .background(
          color.opacity(contrast == .increased ? 0.25 : 0.15),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .accessibilityHidden(true)

      Text(title)
    }
  }
}
