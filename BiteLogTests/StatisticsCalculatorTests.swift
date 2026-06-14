import Foundation
import Testing

@testable import BiteLog

/// portionSize=1 のスナップショットを使い、numberOfServings=量 として
/// 栄養値がそのまま反映される LogItemDTO を組み立てるヘルパー。
private func makeItem(
  logDate: String,
  mealType: MealType = .breakfast,
  servings: Double = 1,
  calories: Double = 0,
  protein: Double = 0,
  fat: Double = 0,
  netCarbs: Double = 0,
  fiber: Double = 0
) -> LogItemDTO {
  let snapshot = NutritionSnapshot(
    brandName: "B",
    productName: "P",
    calories: calories,
    netCarbs: netCarbs,
    dietaryFiber: fiber,
    fat: fat,
    protein: protein,
    portionSize: 1,
    portionUnit: "g"
  )
  return LogItemDTO(
    id: UUID(),
    timestamp: Date(),
    logDate: logDate,
    mealType: mealType,
    numberOfServings: servings,
    isMasterDeleted: false,
    foodMaster: nil,
    nutritionSnapshot: snapshot
  )
}

struct StatisticsCalculatorTests {

  // MARK: - dailyTotals

  @Test func dailyTotalsEmptyReturnsEmpty() {
    #expect(StatisticsCalculator.dailyTotals([] as [LogItemDTO]).isEmpty)
  }

  @Test func dailyTotalsGroupsByDateAndSumsAscending() {
    let items = [
      makeItem(logDate: "2024-01-02", calories: 100),
      makeItem(logDate: "2024-01-01", calories: 200),
      makeItem(logDate: "2024-01-01", calories: 50),
    ]
    let result = StatisticsCalculator.dailyTotals(items)
    #expect(result.map(\.date) == ["2024-01-01", "2024-01-02"])
    #expect(result[0].values.calories == 250)
    #expect(result[1].values.calories == 100)
  }

  @Test func dailyTotalsScalesByServings() {
    let items = [makeItem(logDate: "2024-01-01", servings: 2, calories: 100, protein: 10)]
    let result = StatisticsCalculator.dailyTotals(items)
    #expect(result[0].values.calories == 200)
    #expect(result[0].values.protein == 20)
  }

  // MARK: - periodTotal / dailyAverage

  @Test func periodTotalSumsAllItems() {
    let items = [
      makeItem(logDate: "2024-01-01", calories: 100, protein: 10),
      makeItem(logDate: "2024-01-02", calories: 300, protein: 20),
    ]
    let total = StatisticsCalculator.periodTotal(items)
    #expect(total.calories == 400)
    #expect(total.protein == 30)
  }

  @Test func dailyAverageDividesByCalendarDayCount() {
    // 合計600kcalを暦3日で割る → 200（記録のある日数2ではなく暦日数3が母数）
    let items = [
      makeItem(logDate: "2024-01-01", calories: 200),
      makeItem(logDate: "2024-01-03", calories: 400),
    ]
    let avg = StatisticsCalculator.dailyAverage(items, dayCount: 3)
    #expect(avg.calories == 200)
  }

  @Test func dailyAverageZeroDayCountReturnsZero() {
    let items = [makeItem(logDate: "2024-01-01", calories: 200)]
    #expect(StatisticsCalculator.dailyAverage(items, dayCount: 0).calories == 0)
  }

  // MARK: - goalAchievedDays (±10%)

  @Test func goalAchievedDaysCountsWithinTolerance() {
    // 目標2000kcal、±10% → 1800〜2200 が達成
    let items = [
      makeItem(logDate: "2024-01-01", calories: 2000),  // 達成
      makeItem(logDate: "2024-01-02", calories: 1800),  // 下限ちょうど → 達成
      makeItem(logDate: "2024-01-03", calories: 2200),  // 上限ちょうど → 達成
      makeItem(logDate: "2024-01-04", calories: 1799),  // 未達
      makeItem(logDate: "2024-01-05", calories: 2201),  // 未達
    ]
    let days = StatisticsCalculator.goalAchievedDays(items, targetCalories: 2000)
    #expect(days == 3)
  }

  @Test func goalAchievedDaysAggregatesPerDayBeforeJudging() {
    // 同日の複数記録を合算してから判定（1000+1000=2000 → 達成）
    let items = [
      makeItem(logDate: "2024-01-01", calories: 1000),
      makeItem(logDate: "2024-01-01", calories: 1000),
    ]
    #expect(StatisticsCalculator.goalAchievedDays(items, targetCalories: 2000) == 1)
  }

  @Test func goalAchievedDaysZeroTargetReturnsZero() {
    let items = [makeItem(logDate: "2024-01-01", calories: 2000)]
    #expect(StatisticsCalculator.goalAchievedDays(items, targetCalories: 0) == 0)
  }

  // MARK: - pfcBalance

  @Test func pfcBalanceEmptyReturnsZero() {
    #expect(StatisticsCalculator.pfcBalance([] as [LogItemDTO]) == .zero)
  }

  @Test func pfcBalanceComputesEnergyRatio() {
    // P10g→40kcal, F10g→90kcal, netCarbs10g→40kcal, fiber0 → 合計170kcal
    let items = [makeItem(logDate: "2024-01-01", protein: 10, fat: 10, netCarbs: 10)]
    let b = StatisticsCalculator.pfcBalance(items)
    #expect(abs(b.protein - 40.0 / 170.0 * 100) < 0.0001)
    #expect(abs(b.fat - 90.0 / 170.0 * 100) < 0.0001)
    #expect(abs(b.carbs - 40.0 / 170.0 * 100) < 0.0001)
    #expect(abs(b.protein + b.fat + b.carbs - 100) < 0.0001)
  }

  @Test func pfcBalanceIncludesFiberInCarbs() {
    // fiber 10g → 20kcal が carbs 側に加算される
    let items = [makeItem(logDate: "2024-01-01", fiber: 10)]
    let b = StatisticsCalculator.pfcBalance(items)
    #expect(b.carbs == 100)
    #expect(b.protein == 0)
  }

  // MARK: - mealTypeTotals

  @Test func mealTypeTotalsGroupsByMealType() {
    let items = [
      makeItem(logDate: "2024-01-01", mealType: .breakfast, calories: 100),
      makeItem(logDate: "2024-01-01", mealType: .breakfast, calories: 50),
      makeItem(logDate: "2024-01-01", mealType: .dinner, calories: 700),
    ]
    let totals = StatisticsCalculator.mealTypeTotals(items)
    #expect(totals[.breakfast]?.calories == 150)
    #expect(totals[.dinner]?.calories == 700)
    #expect(totals[.lunch] == nil)
  }
}
