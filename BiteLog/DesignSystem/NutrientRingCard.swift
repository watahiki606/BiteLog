import SwiftUI

// MARK: - リング

/// 印の丸の外周に、基準値に対する割合だけ伸びる輪を描く。
///
/// 上限の目標を超えたら輪を赤にする。満たしたい栄養素が届いたら輪を閉じ、印を添える。
/// 基準値が無ければ輪を描かず、印の丸だけにする。
struct NutrientRing: View {
  let nutrient: NutrientID
  let progress: ReferenceProgress?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast

  /// 文字サイズには追随させるが、2列のカードに収まる範囲で頭打ちにする
  @ScaledMetric(relativeTo: .headline) private var scaledSize: CGFloat = 42
  private var size: CGFloat { min(scaledSize, 64) }
  private var lineWidth: CGFloat { max(size * 0.085, 4) }

  private var ringColor: Color { progress?.isOver == true ? .red : nutrient.color }

  var body: some View {
    ZStack {
      Circle()
        .fill(nutrient.color.opacity(contrast == .increased ? 0.3 : 0.15))

      if let progress {
        Circle()
          .inset(by: lineWidth / 2)
          .stroke(ringColor.opacity(contrast == .increased ? 0.35 : 0.2), lineWidth: lineWidth)

        Circle()
          .inset(by: lineWidth / 2)
          .trim(from: 0, to: progress.ringFraction)
          .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
          // 視差効果を減らす設定では伸ばさず、新しい長さで直接描く
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: progress.ringFraction)
      }

      NutrientGlyphView(glyph: nutrient.glyph)
        .font(.system(size: size * NutrientBadge.glyphScale(nutrient.glyph), weight: .semibold))
        .foregroundStyle(nutrient.color)
        .padding(lineWidth + 3)
    }
    .frame(width: size, height: size)
    .overlay(alignment: .bottomTrailing) {
      if progress?.isReached == true {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: size * 0.3, weight: .bold))
          .foregroundStyle(.white, nutrient.color)
          .offset(x: size * 0.06, y: size * 0.06)
      }
    }
    .accessibilityHidden(true)
  }
}

// MARK: - カード

/// 栄養素1つを、リングと値で見せる小さなカード。2列に並べる。
///
/// 文字は名前、量、基準値に対する割合の3つだけにする。残りの量や月経の有無で変わる基準まで
/// 並べると、2列のカードでは文字が詰まって読めない。届いたか超えたかは輪の印と色で示す。
struct NutrientRingCard: View {
  let nutrient: NutrientID
  /// 値の分かった品の合計や平均。どの品も分からなければ nil
  let amount: Double?
  /// 基準値と比べた結果。プロフィールが無いときや、値が分からないときは nil
  let progress: ReferenceProgress?
  var background: Color = Color(UIColor.secondarySystemGroupedBackground)

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      NutrientRing(nutrient: nutrient, progress: progress)

      VStack(alignment: .leading, spacing: 2) {
        Text(nutrient.localizedName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        value

        if let progress {
          Text(verbatim: "\(progress.percent)%")
            .font(.caption2)
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(progress.isOver ? .red : .secondary)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      amount.map(nutrient.accessibilityLabel(for:))
        ?? "\(nutrient.localizedName) \(NSLocalizedString("Unknown", comment: "Unknown nutrient value"))")
    .accessibilityValue(accessibilityValue)
  }

  /// 数値を強く、単位を弱く並べる。記録の詳細のタイルと同じ形
  @ViewBuilder
  private var value: some View {
    if let amount {
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(nutrient.format(amount))
          .font(.system(.headline, design: .rounded, weight: .bold))
          .foregroundStyle(progress?.isOver == true ? .red : .primary)
        Text(nutrient.unit)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.7)
    } else {
      Text(NSLocalizedString("Unknown", comment: "Unknown nutrient value"))
        .font(.system(.headline, design: .rounded, weight: .bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
  }

  /// 「推奨量の 82%」。画面では割合だけを出すが、読み上げでは何と比べたかを言葉で分ける
  static func percentText(_ progress: ReferenceProgress) -> String {
    let key: String
    switch progress.goal.indicator {
    case .tentativeDietaryGoal:
      key = NSLocalizedString("%d%% of the goal", comment: "Share of the tentative dietary goal")
    case .recommendedDietaryAllowance:
      key = NSLocalizedString("%d%% of the recommended amount", comment: "Share of the recommended dietary allowance")
    case .adequateIntake:
      key = NSLocalizedString("%d%% of the adequate intake", comment: "Share of the adequate intake")
    }
    return String(format: key, progress.percent)
  }

  /// 画面で輪の色と印が示すことを、言葉にして読み上げる
  private var accessibilityValue: String {
    guard let progress else { return "" }
    var parts = [Self.percentText(progress)]
    if progress.isOver {
      parts.append(
        String(
          format: NSLocalizedString("Over by %@", comment: "Amount over an upper goal"),
          "\(nutrient.format(progress.excess)) \(nutrient.spokenUnit)"))
    } else if progress.isReached {
      parts.append(NSLocalizedString("Reached", comment: "A nutrient reached its reference amount"))
    }
    return parts.joined(separator: ", ")
  }
}

// MARK: - 並び

/// 栄養素のリングのカードを、見出しで分けて2列に並べる。
///
/// 食塩相当量と飽和脂肪酸は上限の目標なので、ミネラルや脂質の仲間からは出して先にまとめる。
/// 残りはミネラル、ビタミン、脂肪酸に分ける。
struct NutrientRingGrid: View {
  /// どの合計を見せるか。1日の合計か、期間の1日平均か
  enum Aggregation {
    case dayTotal
    case dailyAverage(days: Int)
  }

  enum Section: CaseIterable {
    case saltAndSaturatedFat, minerals, vitamins, fattyAcids

    init(_ id: NutrientID) {
      switch id {
      case .saltEquivalent, .saturatedFat: self = .saltAndSaturatedFat
      default:
        switch id.definition.group {
        case .mineral: self = .minerals
        case .vitamin: self = .vitamins
        // 並べるのは主要な5項目のほかの栄養素だけで、残りは脂肪酸
        default: self = .fattyAcids
        }
      }
    }

    var title: String {
      switch self {
      case .saltAndSaturatedFat: return NSLocalizedString("Salt and Saturated Fat", comment: "Nutrient group heading")
      case .minerals: return NSLocalizedString("Minerals", comment: "Nutrient group heading")
      case .vitamins: return NSLocalizedString("Vitamins", comment: "Nutrient group heading")
      case .fattyAcids: return NSLocalizedString("Fatty acids", comment: "Nutrient group heading")
      }
    }
  }

  let nutrients: [NutrientID]
  let totals: NutrientTotals
  let aggregation: Aggregation
  /// プロフィールの性別と年齢で引いた基準値。プロフィールが無ければ空で、輪を描かない
  let goals: [NutrientID: DietaryReferenceIntakes.Goal]
  /// 飽和脂肪酸の目標量はエネルギーに占める割合なので、その割合を掛けるエネルギー
  let energy: Double
  var cardBackground: Color = Color(UIColor.secondarySystemGroupedBackground)
  /// カードを押したとき。統計だけが渡し、説明を開く。ログの合計では渡さない
  var onSelect: ((NutrientID) -> Void)? = nil

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(Section.allCases, id: \.self) { section in
        let members = nutrients.filter { Section($0) == section }
        if !members.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
              .accessibilityAddTraits(.isHeader)
            grid(members)
          }
        }
      }
    }
  }

  /// 大きな文字では2列に並べると名前も値も切れるので、1列にする
  private var columns: Int { dynamicTypeSize.isAccessibilitySize ? 1 : 2 }

  private func grid(_ members: [NutrientID]) -> some View {
    let rows = stride(from: 0, to: members.count, by: columns).map {
      Array(members[$0..<min($0 + columns, members.count)])
    }
    return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
      ForEach(rows, id: \.self) { row in
        GridRow {
          ForEach(row, id: \.self) { id in
            if let onSelect {
              card(id).opensNutrientInfo { onSelect(id) }
            } else {
              card(id)
            }
          }
          // 奇数で余った列は空けておき、最後の1枚を半分の幅にそろえる
          if row.count < columns {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
          }
        }
      }
    }
  }

  private func card(_ id: NutrientID) -> some View {
    let known = totals.knownCount(id)
    let amount = known > 0 ? (totals.values.amounts[id] ?? 0) / divisor : nil
    let progress = amount.flatMap { amount in
      goals[id].flatMap { ReferenceProgress(amount: amount, goal: $0, energy: energy) }
    }
    return NutrientRingCard(nutrient: id, amount: amount, progress: progress, background: cardBackground)
  }

  private var divisor: Double {
    switch aggregation {
    case .dayTotal: return 1
    case .dailyAverage(let days): return Double(max(days, 1))
    }
  }
}
