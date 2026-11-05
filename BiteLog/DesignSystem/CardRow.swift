import SwiftUI

extension View {
  /// List の1行を、独立した1枚のカードにする。
  ///
  /// 同じ面に並べて区切り線で分けると、線が行ごとに入って画面が細切れに見える。
  /// 1件ずつ独立した面にして、カードとカードの隙間で区切る。
  /// カードの左右の端は、insetGrouped のセクションの端にそろう。
  func cardRow(verticalPadding: CGFloat = 16) -> some View {
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
      .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
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
