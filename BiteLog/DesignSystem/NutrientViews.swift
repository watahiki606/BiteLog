import SwiftUI

// MARK: - チップ

/// 一覧の行に並べる栄養素の小さな表示。
struct NutrientChip: View {
  let nutrient: Nutrient
  let value: Double

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    HStack(spacing: 3) {
      Text(nutrient.shortLabel)
        .fontWeight(.medium)
        .foregroundStyle(nutrient.color)

      Text("\(nutrient.format(value))\(nutrient.unit)")
        .monospacedDigit()
        .foregroundStyle(.primary)
    }
    .font(.caption)
    .lineLimit(1)
    .padding(.vertical, 3)
    .padding(.horizontal, 6)
    // コントラストを上げる設定では、地に溶ける薄い面をそのまま出さない。
    // 濃さを足したうえで輪郭を描き、チップの範囲が分かるようにする。
    .background(
      nutrient.color.opacity(contrast == .increased ? 0.24 : 0.12),
      in: RoundedRectangle(cornerRadius: 6)
    )
    .overlay {
      if contrast == .increased {
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(nutrient.color, lineWidth: 1)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(nutrient.accessibilityLabel(for: value))
  }
}

/// P / 脂質 / 糖質 / 食物繊維 のチップを既定の順で並べる。
///
/// 文字を大きくすると4つ横並びでは入りきらないので、2列 → 1列と段階的に折り返す。
/// 折り返さずに縮めるとチップの中の数値が「62…」のように切れて読めなくなる。
struct NutrientChipRow: View {
  let values: NutritionValues

  private var items: [(Nutrient, Double)] {
    Nutrient.chipNutrients.map { ($0, $0.value(of: values)) }
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 6) {
        ForEach(items, id: \.0) { NutrientChip(nutrient: $0.0, value: $0.1) }
      }

      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { index in
          HStack(spacing: 6) {
            NutrientChip(nutrient: items[index].0, value: items[index].1)
            if index + 1 < items.count {
              NutrientChip(nutrient: items[index + 1].0, value: items[index + 1].1)
            }
          }
        }
      }

      VStack(alignment: .leading, spacing: 4) {
        ForEach(items, id: \.0) { NutrientChip(nutrient: $0.0, value: $0.1) }
      }
    }
  }
}

// MARK: - 目標に対する進捗バー

/// 目標値に対する摂取量のバー。超過時は目標ラインを描いて超過分を示す。
struct NutrientBar: View {
  let nutrient: Nutrient
  let value: Double
  let target: Double

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast

  /// 超過時に表示する最大倍率。目標の150%でバーが埋まる。
  private let maxDisplayRatio: Double = 1.5

  private var ratio: Double {
    guard target > 0 else { return 0 }
    return value / target
  }

  private var isOverTarget: Bool { ratio > 1.0 }
  private var overAmount: Double { max(value - target, 0) }
  private var barColor: Color { isOverTarget ? .red : nutrient.color }

  private var barWidth: Double {
    isOverTarget ? min(ratio / maxDisplayRatio, 1.0) : ratio
  }

  /// 100% の位置。超過表示に切り替わるとバー全体が 150% を表すのでその逆数。
  private var targetLinePosition: Double { 1.0 / maxDisplayRatio }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Text(nutrient.localizedName)
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer(minLength: 4)

        if isOverTarget {
          Text("+\(nutrient.format(overAmount))\(nutrient.unit)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.red)
        }

        Text("\(nutrient.format(value))\(nutrient.unit)")
          .font(.caption.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(isOverTarget ? .red : .primary)
      }

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(barColor.opacity(contrast == .increased ? 0.3 : 0.15))
            .frame(height: 5)

          Capsule()
            .fill(barColor)
            .frame(width: geometry.size.width * barWidth, height: 5)
            // 視差効果を減らす設定では伸び縮みさせず、新しい長さで直接描く。
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: barWidth)

          if isOverTarget {
            Rectangle()
              .fill(Color.primary.opacity(0.6))
              .frame(width: 2, height: 9)
              .offset(x: geometry.size.width * targetLinePosition - 1)
          }
        }
        .frame(maxHeight: .infinity)
      }
      .frame(height: 9)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(nutrient.accessibilityLabel(for: value))
    .accessibilityValue(progressDescription)
  }

  private var progressDescription: String {
    guard target > 0 else { return "" }
    return String(
      format: NSLocalizedString("%@ of %@ goal", comment: "Accessibility progress"),
      "\(Int((ratio * 100).rounded()))%",
      "\(nutrient.format(target))\(nutrient.unit)"
    )
  }
}

// MARK: - カロリーリング

/// 1日の摂取カロリーを目標に対する円環で示す。
struct CalorieRingView: View {
  let calories: Double
  let targetCalories: Double

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast

  /// 文字サイズに追随させる。固定 90pt のままだと大きい文字で数字が枠からはみ出す。
  @ScaledMetric(relativeTo: .title2) private var scaledDiameter: CGFloat = 92
  @ScaledMetric(relativeTo: .title2) private var scaledLineWidth: CGFloat = 10

  /// 文字サイズには追随させるが、要約カードに収まる範囲で頭打ちにする。
  private var diameter: CGFloat { min(scaledDiameter, 140) }
  private var lineWidth: CGFloat { min(scaledLineWidth, 14) }

  init(calories: Double, targetCalories: Double = 2000) {
    self.calories = calories
    self.targetCalories = targetCalories
  }

  private var ratio: Double {
    guard targetCalories > 0 else { return 0 }
    return calories / targetCalories
  }

  private var progress: Double { min(ratio, 1.0) }
  private var isOverTarget: Bool { ratio > 1.0 }
  private var overAmount: Double { max(calories - targetCalories, 0) }
  private var ringColor: Color { isOverTarget ? .red : Nutrient.calories.color }

  var body: some View {
    ZStack {
      Circle()
        .stroke(ringColor.opacity(contrast == .increased ? 0.3 : 0.15), lineWidth: lineWidth)

      Circle()
        .trim(from: 0, to: progress)
        .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
        // 視差効果を減らす設定では円弧を伸ばさず、新しい位置で直接描く。
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: progress)

      VStack(spacing: 0) {
        Text(NutritionFormatter.formatCalories(calories))
          .font(.system(.title3, design: .rounded, weight: .bold))
          .monospacedDigit()
          .foregroundStyle(isOverTarget ? Color.red : Color.primary)

        Text(Nutrient.calories.unit)
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)

        if isOverTarget {
          Text("+\(NutritionFormatter.formatCalories(overAmount))")
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.red)
        }
      }
      .minimumScaleFactor(0.6)
      .padding(lineWidth + 2)
    }
    .frame(width: diameter, height: diameter)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Nutrient.calories.accessibilityLabel(for: calories))
    .accessibilityValue(
      String(
        format: NSLocalizedString("%@ of %@ goal", comment: "Accessibility progress"),
        "\(Int((ratio * 100).rounded()))%",
        "\(NutritionFormatter.formatCalories(targetCalories)) \(Nutrient.calories.unit)"
      )
    )
  }
}

// MARK: - カロリー表示

/// 「520 kcal」のように数値を強く、単位を弱く並べる共通表示。
struct CalorieLabel: View {
  let calories: Double
  var textStyle: Font.TextStyle = .subheadline

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 2) {
      Text(NutritionFormatter.formatCalories(calories))
        .font(.system(textStyle, design: .rounded, weight: .semibold))
        .monospacedDigit()
      Text(Nutrient.calories.unit)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Nutrient.calories.accessibilityLabel(for: calories))
  }
}
