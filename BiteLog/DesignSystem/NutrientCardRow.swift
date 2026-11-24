import SwiftUI

/// 栄養素1つを、印の丸と名前を左に、値を右に置いた1行のカードで見せる。
///
/// 記録の編集と食品の詳細と食品の入力で同じ形にする。印の丸は1日の合計と統計のリングのカードと同じもので、
/// 画面が変わっても同じ栄養素を同じ印で見つけられる。
struct NutrientCardRow<Value: View>: View {
  let nutrient: any NutrientDisplaying
  /// カードの地。フォームの行の上に重ねるときは一段明るい地にする。
  /// 行の地を消して画面の地に直接並べるときは、1日の合計や統計のカードと同じ地にする
  var background: Color = Color(UIColor.tertiarySystemGroupedBackground)
  @ViewBuilder let value: () -> Value

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(spacing: 10) {
      NutrientBadge(nutrient: nutrient, size: 30)

      // 大きな文字で名前と値を横に並べると、どちらも語の途中で折れる。値を名前の下へ逃がす
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          label
          value()
        }
      } else {
        label
        Spacer(minLength: 8)
        value()
      }
    }
    .font(.subheadline)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var label: some View {
    Text(nutrient.localizedName)
      .fixedSize(horizontal: false, vertical: true)
  }
}
