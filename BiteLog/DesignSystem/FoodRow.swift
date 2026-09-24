import SwiftUI

/// 食品1件を表す一覧行。ログ・食品管理・検索結果で共通に使う。
///
/// 以前は3画面がそれぞれ別のレイアウトを持っていて、同じ食品が画面ごとに
/// 違う見た目で出ていた。
///
/// アクセシビリティ用の大きな文字サイズでは、名前とカロリーを横に並べると
/// どちらも潰れて読めなくなるため縦積みに切り替える。
struct FoodRow: View {
  let title: String
  /// 摂取量や1食分の量。「2 個」「100 g」など。
  let subtitle: String
  let values: NutritionValues
  var isDeleted: Bool = false
  /// 行頭に出す SF Symbol。自分で登録した食品を示す場合などに使う。
  var leadingSymbol: String?
  var leadingSymbolLabel: String?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          titleBlock
          CalorieLabel(calories: values.calories)
        }
      } else {
        HStack(alignment: .firstTextBaseline) {
          titleBlock
          Spacer(minLength: 8)
          CalorieLabel(calories: values.calories)
        }
      }

      NutrientChipRow(values: values)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var titleBlock: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        if let leadingSymbol {
          Image(systemName: leadingSymbol)
            .font(.caption2)
            .foregroundStyle(.tint)
            .accessibilityLabel(leadingSymbolLabel ?? "")
            .accessibilityHidden(leadingSymbolLabel == nil)
        }

        Text(title)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(isDeleted ? .secondary : .primary)
          .strikethrough(isDeleted)
          .lineLimit(2)

        if isDeleted && !dynamicTypeSize.isAccessibilitySize {
          deletedBadge
        }
      }

      if isDeleted && dynamicTypeSize.isAccessibilitySize {
        deletedBadge
      }

      if !subtitle.isEmpty {
        Text(subtitle)
          .font(.caption)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
  }

  private var deletedBadge: some View {
    Text(NSLocalizedString("(Deleted)", comment: "Deleted Food indicator"))
      .font(.caption2)
      .foregroundStyle(.red)
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, 4)
      .padding(.vertical, 2)
      .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
  }
}

extension FoodRow {
  /// 「ブランド名 商品名」の組み立て。ブランド名が空のときに先頭の空白が残らないようにする。
  static func displayName(brand: String, product: String) -> String {
    brand.isEmpty ? product : "\(brand) \(product)"
  }

  /// 「2 個」「100 g」のような量の表記。
  static func amountText(_ amount: Double, unit: String) -> String {
    "\(NutritionFormatter.formatNutrition(amount)) \(unit)"
  }
}
