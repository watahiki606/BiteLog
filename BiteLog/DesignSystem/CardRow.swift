import SwiftUI

extension View {
  /// List の1行を、独立した1枚のカードにする。
  ///
  /// 同じ面に並べて区切り線で分けると、線が行ごとに入って画面が細切れに見える。
  /// 1件ずつ独立した面にして、カードとカードの隙間で区切る。
  /// カードの左右の端は、insetGrouped のセクションの端にそろう。
  func cardRow(verticalPadding: CGFloat = 20) -> some View {
    self
      // 合計カードの中身と左端がそろうよう、同じ 20pt にする
      .padding(.horizontal, 20)
      .padding(.vertical, verticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color(UIColor.secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
  }
}

/// 押すと別の画面へ進むカード。
///
/// NavigationLink をそのまま行に置くと、右端の矢印がカードの外に描かれる。
/// 遷移は透明な NavigationLink に任せ、矢印はカードの中に自分で描く。
struct CardNavigationLink<Destination: View, Label: View>: View {
  @ViewBuilder let destination: () -> Destination
  @ViewBuilder let label: () -> Label

  var body: some View {
    ZStack {
      NavigationLink(destination: destination) { EmptyView() }
        .opacity(0)

      HStack(spacing: 8) {
        label()
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
    }
    .cardRow()
  }
}

extension View {
  /// セクションの見出しを、下のカードの左端にそろえる。
  ///
  /// 既定では見出しがカードの中身と同じ位置まで内側に寄り、見出しなのに
  /// カードより奥に引っ込んで見える。外側にそろえて、どのカードの見出しかを示す。
  func sectionHeaderAlignedToCard() -> some View {
    listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
  }
}

/// 一覧のセクションの見出し。
///
/// 標準の見出しは小さな灰色の大文字で、どこで区切れているかが目に入りにくい。
/// 太字にして本文と同じ色にし、カードの左端にそろえる。
struct CardSectionHeader: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.headline)
      // フォームの見出しは灰色に塗られる。.primary だとその灰色の中の濃い側になるだけなので、
      // 本文の色を直接指定する
      .foregroundStyle(Color(UIColor.label))
      .textCase(nil)
      .sectionHeaderAlignedToCard()
  }
}
