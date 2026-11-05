import SwiftUI

extension Notification.Name {
  static let allDataDeleted = Notification.Name("allDataDeleted")
}

/// プロフィールのタブ。自分について・目標・体組成計・データ・アカウントをまとめる。
///
/// 以前は記録の画面の歯車から開く設定のシートだった。生年月日や身長は体組成計の
/// 設定の奥にあり、体組成計を持っていない人は見つけられなかった。
/// 自分についての情報を先頭に置き、機器やデータの管理はその後ろに並べる。
struct ProfileView: View {
  @EnvironmentObject private var languageManager: LanguageManager
  @EnvironmentObject private var nutritionGoalsManager: NutritionGoalsManager
  @State private var showingDeleteConfirmation = false
  @State private var isDeleting = false
  @State private var showDeleteSuccessAlert = false
  @State private var showDeleteErrorAlert = false
  @State private var showingSignOutConfirmation = false
  @State private var deleteErrorMessage = ""
  /// 入力画面から戻るたびに読み直す
  @State private var personal = PersonalProfile.load()
  @State private var isScaleRegistered = TanitaScaleConnection.isPaired()

  var body: some View {
    NavigationStack {
      Form {
        Section {
          NavigationLink(destination: PersonalProfileView()) {
            ProfileHeroCard(personal: personal)
          }
        }

        Section {
          NavigationLink(destination: NutritionGoalsEditView()) {
            SettingsRowLabel(
              NSLocalizedString("Daily Nutrition Goals", comment: "Nutrition goals link"),
              systemImage: "target", color: .red,
              detail: "\(NutritionFormatter.formatCalories(nutritionGoalsManager.targetCalories)) kcal")
          }
        } header: {
          CardSectionHeader(NSLocalizedString("Goals", comment: "Profile section"))
        }

        Section {
          NavigationLink(destination: ScaleImportView()) {
            SettingsRowLabel(
              NSLocalizedString("Body Composition Scale", comment: "Profile scale link"),
              systemImage: "scalemass.fill", color: .purple,
              detail: isScaleRegistered
                ? NSLocalizedString("Registered", comment: "Scale registered status")
                : NSLocalizedString("Not Registered", comment: "Scale not registered status"))
          }
        } header: {
          CardSectionHeader(NSLocalizedString("Devices", comment: "Profile section"))
        }

        Section {
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
          Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
            SettingsRowLabel(
              NSLocalizedString("Delete All Data", comment: "Delete all data"),
              systemImage: "trash.fill", color: .red)
          }
        } header: {
          CardSectionHeader(NSLocalizedString("Data Management", comment: "Data management section"))
        }

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

          Button(role: .destructive, action: { showingSignOutConfirmation = true }) {
            SettingsRowLabel(
              NSLocalizedString("Sign Out", comment: "Sign out button"),
              systemImage: "rectangle.portrait.and.arrow.right", color: .red)
          }
        } header: {
          CardSectionHeader(NSLocalizedString("Account", comment: "Account settings section"))
        } footer: {
          Text(
            NSLocalizedString(
              "Change the language in the Settings app, under Preferred Language.",
              comment: "Language settings footer"))
        }
      }
      .navigationTitle(NSLocalizedString("Profile", comment: "Tab name"))
      .onAppear {
        personal = PersonalProfile.load()
        isScaleRegistered = TanitaScaleConnection.isPaired()
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
  /// 名前の下に添える今の値。「42歳 · 166.0 cm」など。開かなくても中身が分かる
  var detail: String?

  @Environment(\.colorSchemeContrast) private var contrast
  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 38

  init(_ title: String, systemImage: String, color: Color, detail: String? = nil) {
    self.title = title
    self.systemImage = systemImage
    self.color = color
    self.detail = detail
  }

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: systemImage)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .frame(width: iconSize, height: iconSize)
        .background(
          color.opacity(contrast == .increased ? 0.25 : 0.15),
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityHidden(true)

      // 記録の画面の名前と同じく太字にする。細い字だと一覧が頼りなく見える
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.body.weight(.semibold))
        if let detail {
          Text(detail)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

/// プロフィールの先頭のカード。自分についての情報を大きく見せる。
///
/// 一覧の1行にすると、ほかの設定と同じ重さになって埋もれる。
/// このタブの主役なので、アイコンと要約を大きく出す。
private struct ProfileHeroCard: View {
  let personal: PersonalProfile?

  @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 84

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "person.fill")
        .font(.system(size: avatarSize * 0.45, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: avatarSize, height: avatarSize)
        .background(
          LinearGradient(
            colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
          in: Circle()
        )
        .accessibilityHidden(true)

      VStack(spacing: 4) {
        Text(NSLocalizedString("About Me", comment: "Personal profile title"))
          .font(.title3.weight(.bold))

        Text(
          personal?.summary()
            ?? NSLocalizedString(
              "Enter your date of birth and height", comment: "Profile hero empty")
        )
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
    .accessibilityElement(children: .combine)
  }
}
