import SwiftUI

/// 見出しの行の幅いっぱいを押して開閉し、開いた中身を押しても開閉しない畳み。
///
/// DisclosureGroup を List の行の中に置くと、行のどこを押しても開閉する。見た目を
/// DisclosureGroupStyle で差し替えても、ボタンを .borderless にしても変わらない。
/// 1日の合計のように1行に中身の多い畳みを入れると、中のカードを押しただけで閉じるので、
/// DisclosureGroup を使わずに見出しのボタンだけで開閉する。
struct HeadingDisclosure<Label: View, Content: View>: View {
  @Binding var isExpanded: Bool
  @ViewBuilder let content: () -> Content
  @ViewBuilder let label: () -> Label

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder label: @escaping () -> Label
  ) {
    _isExpanded = isExpanded
    self.content = content
    self.label = label
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
          isExpanded.toggle()
        }
      } label: {
        HStack {
          label()
          Spacer(minLength: 8)
          Image(systemName: "chevron.right")
            .imageScale(.small)
            .fontWeight(.semibold)
            .foregroundStyle(.tint)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            // 開閉の状態は値で読み上げる。矢印の名前まで読むと冗長になる
            .accessibilityHidden(true)
        }
        // 文字と矢印のあいだの余白も押せるようにする。押せる高さも指の幅に足りるよう広げる
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
      }
      // List の行は、既定の見た目のボタンへ行のどこを押しても届ける
      .buttonStyle(.borderless)
      .accessibilityValue(
        isExpanded
          ? NSLocalizedString("Expanded", comment: "State of a disclosure that is open")
          : NSLocalizedString("Collapsed", comment: "State of a disclosure that is closed"))

      if isExpanded {
        content()
      }
    }
  }
}
