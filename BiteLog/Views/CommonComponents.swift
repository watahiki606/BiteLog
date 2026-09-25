import SwiftUI

/// 見出し付きのカード。
///
/// 境界は影ではなく背景の階層で表す。黒い影はダークモードでは地の色に沈んで
/// 輪郭が消える。グループ背景の上に1段明るい面を置けば、ライト・ダーク
/// どちらでも境界が立つ。
struct CardView<Content: View>: View {
  let title: String?
  let content: Content

  init(title: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: title == nil ? 0 : 16) {
      if let title {
        Text(title)
          .font(.headline)
      }

      content
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(UIColor.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 16)
    )
  }
}

/// 読み込みに失敗したことを示す表示。
///
/// 通信の失敗を「1件もありません」と同じ見た目で出すと、記録が残っているのに
/// もう一度記録する、登録済みの食品をまた登録する、といった操作を誘発する。
/// 空の状態とは別物として描き分ける。
struct LoadFailureView: View {
  let retry: () async -> Void

  var body: some View {
    ContentUnavailableView {
      Label(
        NSLocalizedString("Couldn't load", comment: "Load failure title"),
        systemImage: "wifi.exclamationmark")
    } description: {
      Text(
        NSLocalizedString(
          "Check your connection and try again.", comment: "Load failure description"))
    } actions: {
      Button(NSLocalizedString("Retry", comment: "Retry button")) {
        Task { await retry() }
      }
      .buttonStyle(.borderedProminent)
    }
  }
}

/// 保存・削除に失敗したことを伝えるための値。
///
/// 失敗を握りつぶすと、保存できていないのに保存したつもりになれてしまう。
/// 画面ごとに文面を組み立てず、失敗した操作名とエラーの説明だけを持たせる。
struct OperationFailure: Identifiable, Equatable {
  let id = UUID()
  let title: String
  let message: String

  static func == (lhs: OperationFailure, rhs: OperationFailure) -> Bool { lhs.id == rhs.id }

  static func saving(_ error: Error) -> OperationFailure {
    OperationFailure(
      title: NSLocalizedString("Couldn't save", comment: "Save failure title"),
      message: error.localizedDescription)
  }

  static func deleting(_ error: Error) -> OperationFailure {
    OperationFailure(
      title: NSLocalizedString("Couldn't delete", comment: "Delete failure title"),
      message: error.localizedDescription)
  }

  /// 既に表示できている内容がある状態での再読み込み失敗。
  /// 画面ごと差し替えると読めていた内容まで消えるので、アラートだけで伝える。
  static func refreshing(_ error: Error) -> OperationFailure {
    OperationFailure(
      title: NSLocalizedString("Couldn't refresh", comment: "Refresh failure title"),
      message: error.localizedDescription)
  }
}

extension View {
  /// 保存・削除の失敗をアラートとハプティクスで返す。
  func operationFailureAlert(_ failure: Binding<OperationFailure?>) -> some View {
    alert(
      failure.wrappedValue?.title ?? "",
      isPresented: Binding(
        get: { failure.wrappedValue != nil },
        set: { if !$0 { failure.wrappedValue = nil } }
      ),
      presenting: failure.wrappedValue
    ) { _ in
      Button(NSLocalizedString("OK", comment: "Button title"), role: .cancel) {}
    } message: { failure in
      Text(failure.message)
    }
    .sensoryFeedback(.error, trigger: failure.wrappedValue?.id)
  }
}
