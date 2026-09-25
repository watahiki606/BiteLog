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
