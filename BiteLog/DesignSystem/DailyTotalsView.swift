import SwiftUI

/// 1日の摂取量を目標と並べて示す要約。
///
/// リング1つと主要3栄養素を主役にし、毎日は追わない食物繊維と炭水化物は畳んでおく。
/// 全部を開いたままにすると要約だけで画面の3分の1を使う。
struct DailyTotalsView: View {
  let totals: NutritionValues
  let goals: NutritionGoalsTargets
  @Binding var showsAllNutrients: Bool

  var body: some View {
    Group {
      HStack(alignment: .center, spacing: 16) {
        CalorieRingView(calories: totals.calories, targetCalories: goals.calories)

        VStack(spacing: 8) {
          NutrientBar(nutrient: .protein, value: totals.protein, target: goals.protein)
          NutrientBar(nutrient: .fat, value: totals.fat, target: goals.fat)
          NutrientBar(nutrient: .netCarbs, value: totals.netCarbs, target: goals.netCarbs)
        }
      }

      DisclosureGroup(isExpanded: $showsAllNutrients) {
        NutrientBar(nutrient: .fiber, value: totals.dietaryFiber, target: goals.fiber)

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
}

/// 1日の目標値。`NutritionGoalsManager` から表示側へ渡すための素の値。
struct NutritionGoalsTargets {
  let calories: Double
  let protein: Double
  let fat: Double
  let netCarbs: Double
  let fiber: Double
}
