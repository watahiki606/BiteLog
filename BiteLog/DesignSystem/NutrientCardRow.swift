import SwiftUI

/// 栄養素1つを、印の丸と名前を左に、値を右に置いた1行のカードで見せる。
///
/// 記録の編集と食品の詳細で同じ形にする。印の丸は1日の合計と統計のリングのカードと同じもので、
/// 画面が変わっても同じ栄養素を同じ印で見つけられる。
struct NutrientCardRow<Value: View>: View {
  let nutrient: any NutrientDisplaying
  /// 栄養素の名前と違う呼び方をしたいとき。食品の詳細の「うち食物繊維」
  var name: String? = nil
  /// 名前の下に小さく添える一言。成分表で補った値の印
  var note: String? = nil
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
    .background(
      Color(UIColor.tertiarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
  }

  private var label: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(name ?? nutrient.localizedName)
        .fixedSize(horizontal: false, vertical: true)
      if let note {
        Text(note)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }
}
