import SwiftUI

/// 1件の記録で摂った量の要約。カロリーを大きく、主要3栄養素をその下にタイルで並べる。
///
/// 「1食あたり → 合計」の行だけだと、6行の数字を読み比べないと何をどれだけ
/// 摂ったか分からない。まず合計を一目で見せ、内訳の行はその下に残す。
struct NutritionOverview: View {
  let values: NutritionValues

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private static let tileNutrients: [Nutrient] = [.protein, .fat, .netCarbs]

  var body: some View {
    VStack(spacing: 12) {
      calorieCard

      // 大きな文字では3枚を横に並べると数値が切れる。縦に積む
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 12) {
          ForEach(Self.tileNutrients) { tile(for: $0) }
        }
      } else {
        HStack(spacing: 12) {
          ForEach(Self.tileNutrients) { tile(for: $0) }
        }
      }
    }
  }

  private var calorieCard: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(NutritionFormatter.formatCalories(values.calories))
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .monospacedDigit()
          Text(Nutrient.calories.unit)
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        Text(Nutrient.calories.localizedName)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      NutrientBadge(nutrient: .calories, size: 48)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(UIColor.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 20, style: .continuous)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Nutrient.calories.accessibilityLabel(for: values.calories))
  }

  private func tile(for nutrient: Nutrient) -> some View {
    let value = nutrient.value(of: values)
    return VStack(spacing: 6) {
      NutrientBadge(nutrient: nutrient, size: 36)

      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(nutrient.format(value))
          .font(.system(.title3, design: .rounded, weight: .bold))
          .monospacedDigit()
        Text(nutrient.unit)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.8)

      Text(nutrient.localizedName)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity)
    .background(
      Color(UIColor.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(nutrient.accessibilityLabel(for: value))
  }
}

/// 栄養素の形を、その色の淡い丸に入れた印。
struct NutrientBadge: View {
  let nutrient: Nutrient
  var size: CGFloat = 36

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    Image(systemName: nutrient.symbolName)
      .font(.system(size: size * 0.42, weight: .semibold))
      .foregroundStyle(nutrient.color)
      .frame(width: size, height: size)
      .background(nutrient.color.opacity(contrast == .increased ? 0.3 : 0.15), in: Circle())
      .accessibilityHidden(true)
  }
}
