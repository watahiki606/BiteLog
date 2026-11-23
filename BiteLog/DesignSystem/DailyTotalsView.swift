import SwiftUI

/// 1日の摂取量を目標と並べて示す要約。
///
/// カロリーのリングを主役にし、主要3栄養素はその下に添える。毎日は追わない
/// 食物繊維と炭水化物は畳んでおく。
/// 全部を開いたままにすると要約だけで画面の3分の1を使う。
///
/// 下に続く食事の一覧とは別の面として、余白を広く取った1枚のカードにする。
/// 一覧の行と同じ見た目だと、合計と個々の記録の区別がつきにくい。
struct DailyTotalsView: View {
  let totals: NutritionValues
  let goals: NutritionGoalsTargets
  @Binding var showsAllNutrients: Bool
  /// あとから足した栄養素の合計と、値の分かっていた品数
  var addedTotals: NutrientTotals = .empty

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(NSLocalizedString("Daily Total", comment: "Daily nutrition summary"))
        .font(.title2.weight(.bold))
        .accessibilityAddTraits(.isHeader)

      summary
    }
    // 大きな文字では数値が「63.7g l…」と切れる。余白より中身の幅を優先する
    .padding(dynamicTypeSize.isAccessibilitySize ? 12 : 20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(UIColor.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    // 影はライトのときだけ。ダークでは地に沈んで見えないので、背景の階層だけで境界を出す
    .shadow(
      color: .black.opacity(colorScheme == .light ? 0.06 : 0), radius: 12, x: 0, y: 4)
  }

  /// カロリーのリングを主役にして中央に大きく置き、主要3栄養素はその下に小さく並べる。
  ///
  /// リングの横にバーを3本並べると、リングの数字とバーの数字が同じ強さで競い、
  /// どこから読めばいいか分からなくなる。
  @ViewBuilder
  private var summary: some View {
    VStack(alignment: .leading, spacing: 20) {
      CalorieRingView(
        calories: totals.calories, targetCalories: goals.calories, showsRemaining: true,
        isProminent: true
      )
      .frame(maxWidth: .infinity, alignment: .center)

      // 大きな文字では3列に並べると名前も数値も切れる。従来の縦積みのバーに戻す
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 8) {
          NutrientBar(
            nutrient: .protein, value: totals.protein, target: goals.protein,
            showsRemaining: true)
          NutrientBar(nutrient: .fat, value: totals.fat, target: goals.fat, showsRemaining: true)
          NutrientBar(
            nutrient: .netCarbs, value: totals.netCarbs, target: goals.netCarbs,
            showsRemaining: true)
        }
      } else {
        HStack(alignment: .top, spacing: 16) {
          NutrientBar(
            nutrient: .protein, value: totals.protein, target: goals.protein,
            showsRemaining: true, isCompact: true)
          NutrientBar(
            nutrient: .fat, value: totals.fat, target: goals.fat, showsRemaining: true,
            isCompact: true)
          NutrientBar(
            nutrient: .netCarbs, value: totals.netCarbs, target: goals.netCarbs,
            showsRemaining: true, isCompact: true)
        }
      }

      DisclosureGroup(isExpanded: $showsAllNutrients) {
        VStack(alignment: .leading, spacing: 12) {
          NutrientBar(
            nutrient: .fiber, value: totals.dietaryFiber, target: goals.fiber,
            showsRemaining: true)

          LabeledContent {
            Text("\(Nutrient.carbs.format(totals.carbs))\(Nutrient.carbs.unit)")
              .monospacedDigit()
          } label: {
            Text(NSLocalizedString("Carbs (Sugar + Fiber)", comment: "Nutrient label"))
          }

          // 詳しい栄養素は1日の値で見比べる意味が薄いので、統計の期間で見せる
          ForEach(NutrientID.labelNutrients, id: \.self) { id in
            AddedNutrientTotalRow(id: id, totals: addedTotals)
          }
        }
        .padding(.top, 8)
      } label: {
        // リストの外では見出しと矢印がリンク色になり、押せる文字が目立ちすぎる。
        // 中身より弱い補助的な操作なので灰色に落とす
        Text(NSLocalizedString("More nutrients", comment: "Disclosure title"))
          .foregroundStyle(.secondary)
      }
      .font(.subheadline)
      .tint(.secondary)
    }
  }
}

/// 1日の目標値。`NutritionGoalsManager` から表示側へ渡すための素の値。
struct NutritionGoalsTargets {
  let calories: Double
  let protein: Double
  let fat: Double
  let netCarbs: Double
  let fiber: Double
}

/// あとから足した栄養素の合計。値の分からない品があれば、何品ぶんの合計かを添える。
///
/// 分からない品を 0 として足すと少なく見えるので、分かっている品だけの合計だと分かるようにする。
struct AddedNutrientTotalRow: View {
  let id: NutrientID
  let totals: NutrientTotals

  private var known: Int { totals.knownCount(id) }

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      // 大きな文字で名前と値を横に並べると、どちらも語の途中で折れる。縦に積む
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 2) {
          Text(id.localizedName)
          value(alignment: .leading)
        }
      } else {
        // 同じ畳みの炭水化物の行と見た目をそろえ、アイコンは付けない
        LabeledContent {
          value(alignment: .trailing)
        } label: {
          Text(id.localizedName)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func value(alignment: HorizontalAlignment) -> some View {
    VStack(alignment: alignment, spacing: 2) {
      Text(valueText).monospacedDigit()
      if known > 0 && !totals.isComplete(id) {
        Text(partialText).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var valueText: String {
    guard known > 0, let value = totals.values.amounts[id] else {
      return NSLocalizedString("Unknown", comment: "Unknown nutrient value")
    }
    return "\(id.format(value))\(id.unit)"
  }

  private var partialText: String {
    String(
      format: NSLocalizedString("Total of %1$d of %2$d items", comment: "Partial total of a nutrient"),
      known, totals.itemCount)
  }
}
