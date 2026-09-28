import SwiftUI

/// 1日の摂取量を目標と並べて示す要約。
///
/// リング1つと主要3栄養素を主役にし、毎日は追わない食物繊維と炭水化物は畳んでおく。
/// 全部を開いたままにすると要約だけで画面の3分の1を使う。
struct DailyTotalsView: View {
  let totals: NutritionValues
  let goals: NutritionGoalsTargets
  @Binding var showsAllNutrients: Bool

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      // 大きな文字ではリングの横に残る幅が栄養素名だけで埋まり、
      // バーの数値が折り返して読めなくなる。行と同じく縦積みに切り替える。
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          CalorieRingView(
            calories: totals.calories, targetCalories: goals.calories, showsRemaining: true)
            .frame(maxWidth: .infinity, alignment: .center)

          macroBars
        }
      } else {
        HStack(alignment: .center, spacing: 16) {
          CalorieRingView(
            calories: totals.calories, targetCalories: goals.calories, showsRemaining: true)

          macroBars
        }
      }

      DisclosureGroup(isExpanded: $showsAllNutrients) {
        NutrientBar(
          nutrient: .fiber, value: totals.dietaryFiber, target: goals.fiber, showsRemaining: true)

        LabeledContent {
          Text("\(Nutrient.carbs.format(totals.carbs))\(Nutrient.carbs.unit)")
            .monospacedDigit()
        } label: {
          Text(NSLocalizedString("Carbs (Sugar + Fiber)", comment: "Nutrient label"))
        }
      } label: {
        Text(NSLocalizedString("More nutrients", comment: "Disclosure title"))
      }
      .font(.subheadline)
    }
  }

  private var macroBars: some View {
    VStack(spacing: 8) {
      NutrientBar(
        nutrient: .protein, value: totals.protein, target: goals.protein, showsRemaining: true)
      NutrientBar(nutrient: .fat, value: totals.fat, target: goals.fat, showsRemaining: true)
      NutrientBar(
        nutrient: .netCarbs, value: totals.netCarbs, target: goals.netCarbs, showsRemaining: true)
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
