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

  /// 日別系列を週/月などのバケットに集計し直す（トレンドグラフの単位切替用）。
  /// 各バケットの代表日は期間先頭（月なら1日、週なら週初め）。`average` のときは
  /// バケットの**暦日数**で割った日平均（記録のない日は0扱い。1日平均カードと定義を揃える）、
  /// それ以外は合計を返す。日付昇順。
  /// - Parameter component: グルーピング単位（`.weekOfYear` / `.month`）。
  static func bucketed(
    _ daily: [DailyNutrition], by component: Calendar.Component,
    average: Bool, calendar: Calendar
  ) -> [DailyNutrition] {
    let groups = Dictionary(grouping: daily) { d -> String in
      guard let date = bucketFormatter.date(from: d.date),
        let start = calendar.dateInterval(of: component, for: date)?.start
      else { return d.date }
      return bucketFormatter.string(from: start)
    }
    return groups.map { key, days in
      let sum = days.reduce(NutritionValues.zero) { $0 + $1.values }
      let values: NutritionValues
      if average {
        // バケットの暦日数（週=7、月=その月の日数）で割る。記録の無い日も母数に含める。
        let start = bucketFormatter.date(from: key)
        let calendarDays = start.flatMap {
          calendar.range(of: .day, in: component, for: $0)?.count
        } ?? days.count
        let n = Double(max(calendarDays, 1))
        values = NutritionValues(
          calories: sum.calories / n, netCarbs: sum.netCarbs / n,
          dietaryFiber: sum.dietaryFiber / n, fat: sum.fat / n, protein: sum.protein / n)
      } else {
        values = sum
      }
      return DailyNutrition(date: key, values: values)
    }
    .sorted { $0.date < $1.date }
  }

  private static let bucketFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

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
