import Foundation

/// 1日分の集計結果（トレンドグラフ・平均・達成日数の素材）
struct DailyNutrition: Identifiable {
  let date: String  // "yyyy-MM-dd"
  let values: NutritionValues
  var id: String { date }
}

/// PFCのエネルギー比率（合計100%。記録ゼロなら全て0）
struct PFCBalance: Equatable {
  let protein: Double
  let fat: Double
  let carbs: Double

  static let zero = PFCBalance(protein: 0, fat: 0, carbs: 0)
}

/// 統計タブの期間集計ロジック。View から切り離した純粋関数群（テスト容易性のため）。
///
/// エネルギー換算はアプリの目標カロリー式（`NutritionGoalsDTO.targetCalories`）と揃える:
/// タンパク質×4 + 脂質×9 + 糖質(netCarbs)×4 + 食物繊維×2 kcal。
enum StatisticsCalculator {
  static let proteinKcal = 4.0
  static let fatKcal = 9.0
  static let netCarbsKcal = 4.0
  static let fiberKcal = 2.0

  /// 日別合計。logDate でグルーピングし、各日の `NutritionValues` を合算。日付昇順で返す。
  static func dailyTotals(_ items: [some NutritionContributing]) -> [DailyNutrition] {
    let grouped = Dictionary(grouping: items, by: { $0.logDate })
    return grouped
      .map { date, dayItems in
        DailyNutrition(
          date: date,
          values: dayItems.reduce(.zero) { $0 + $1.nutritionValues }
        )
      }
      .sorted { $0.date < $1.date }
  }

  /// 期間全体の合計。
  static func periodTotal(_ items: [some NutritionContributing]) -> NutritionValues {
    items.reduce(.zero) { $0 + $1.nutritionValues }
  }

  /// 1日平均（期間合計 ÷ 対象日数）。
  /// - Parameter dayCount: 期間の暦日数（記録の有無に依らない母数）。0以下なら `.zero`。
  static func dailyAverage(_ items: [some NutritionContributing], dayCount: Int) -> NutritionValues {
    guard dayCount > 0 else { return .zero }
    let total = periodTotal(items)
    let d = Double(dayCount)
    return NutritionValues(
      calories: total.calories / d,
      netCarbs: total.netCarbs / d,
      dietaryFiber: total.dietaryFiber / d,
      fat: total.fat / d,
      protein: total.protein / d
    )
  }

  /// 目標達成日数。各日の合計カロリーが目標カロリーの ±tolerance に収まる日を数える。
  /// - Parameters:
  ///   - targetCalories: 1日の目標カロリー。0以下なら 0 を返す。
  ///   - tolerance: 許容割合（0.1 = ±10%）。
  static func goalAchievedDays(
    _ items: [some NutritionContributing], targetCalories: Double, tolerance: Double = 0.1
  ) -> Int {
    guard targetCalories > 0 else { return 0 }
    let lower = targetCalories * (1 - tolerance)
    let upper = targetCalories * (1 + tolerance)
    return dailyTotals(items).filter { $0.values.calories >= lower && $0.values.calories <= upper }
      .count
  }

  /// PFCのエネルギー比率（合計100%）。記録が無い/エネルギー0なら `.zero`。
  static func pfcBalance(_ items: [some NutritionContributing]) -> PFCBalance {
    let total = periodTotal(items)
    let pCal = total.protein * proteinKcal
    let fCal = total.fat * fatKcal
    let cCal = total.netCarbs * netCarbsKcal + total.dietaryFiber * fiberKcal
    let sum = pCal + fCal + cCal
    guard sum > 0 else { return .zero }
    return PFCBalance(
      protein: pCal / sum * 100,
      fat: fCal / sum * 100,
      carbs: cCal / sum * 100
    )
  }

  /// 食事タイプ別の合計。記録のないタイプはキーに含まれない。
  static func mealTypeTotals(_ items: [some NutritionContributing]) -> [MealType: NutritionValues] {
    Dictionary(grouping: items, by: { $0.mealType })
      .mapValues { typeItems in typeItems.reduce(.zero) { $0 + $1.nutritionValues } }
  }
}
