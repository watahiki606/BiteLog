import SwiftUI

/// 食品1件を表す一覧行。ログ・食品管理・検索結果で共通に使う。
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
  /// 名前の行数。一覧では2行に抑えるが、似た名前から1つ選ばせる場面では
  /// 途中で切ると見分けがつかなくなるので nil を渡して全部出す。
  var titleLineLimit: Int? = 2

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
          .lineLimit(titleLineLimit)
          // 行数を制限しない場合だけ、必要な高さを確保させる。
          // これが無いと親の提案した高さに収まるよう2行で切られる。
          .fixedSize(horizontal: false, vertical: titleLineLimit == nil)

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
  /// 「ブランド名 商品名」の組み立て。
  ///
  /// 実データではブランド名を使わず商品名と同じ語を入れている行が多く、
  /// そのまま連結すると「ゆで卵 ゆで卵」のように同じ語が2回出る。
  /// ブランド名が空か商品名と同じときは商品名だけにする。
  static func displayName(brand: String, product: String) -> String {
    let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
    let trimmedProduct = product.trimmingCharacters(in: .whitespaces)
    if trimmedBrand.isEmpty || trimmedBrand == trimmedProduct { return trimmedProduct }
    return "\(trimmedBrand) \(trimmedProduct)"
  }

  /// 「2 個」「100 g」のような量の表記。
  static func amountText(_ amount: Double, unit: String) -> String {
    "\(NutritionFormatter.formatNutrition(amount)) \(unit)"
  }
}
