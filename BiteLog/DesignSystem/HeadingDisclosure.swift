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
      DisclosureHeading(isExpanded: $isExpanded, label: label)

      if isExpanded {
        content()
      }
    }
  }
}

/// 畳みの見出しだけのボタン。開いた中身は呼ぶ側が List の行として並べる。
///
/// List の中の DisclosureGroup は、中身の行を見出しより右に字下げする。
/// 栄養素のカードは1枚ずつ List の行に置いているので、畳んだカードだけが
/// ほかのカードとそろわなくなる。見出しと中身を別の行にして、字下げを起こさない。
struct DisclosureHeading<Label: View>: View {
  @Binding var isExpanded: Bool
  @ViewBuilder let label: () -> Label

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
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
  }
}

extension DisclosureHeading where Label == Text {
  init(_ title: String, isExpanded: Binding<Bool>) {
    // ボタンの文字はリンク色になる。栄養素の名前と同じ色にし、押せることは矢印で示す
    self.init(isExpanded: isExpanded) { Text(title).foregroundColor(.primary) }
  }
}
