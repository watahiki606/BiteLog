import Foundation
import Testing

@testable import BiteLog

/// 栄養素の量を、食事摂取基準の値と比べた結果。
/// 上限の目標は超えたかを、満たしたい栄養素は届いたかを見る。
struct ReferenceProgressTests {

  private typealias Goal = DietaryReferenceIntakes.Goal

  private static let salt = Goal(
    nutrient: .saltEquivalent, indicator: .tentativeDietaryGoal, comparison: .lessThan, value: 7.5)
  private static let saturatedFat = Goal(
    nutrient: .saturatedFat, indicator: .tentativeDietaryGoal, comparison: .atMostPercentOfEnergy, value: 7)
  private static let potassium = Goal(
    nutrient: .potassium, indicator: .tentativeDietaryGoal, comparison: .atLeast, value: 2600)
  private static let calcium = Goal(
    nutrient: .calcium, indicator: .recommendedDietaryAllowance, comparison: .reference, value: 650)

  // MARK: 上限の目標

  @Test func 上限の目標の手前なら残りを出す() throws {
    let progress = try #require(ReferenceProgress(amount: 5, goal: Self.salt, energy: 2000))

    #expect(progress.isLimit)
    #expect(!progress.isOver)
    #expect(!progress.isReached)
    #expect(progress.remaining == 2.5)
    #expect(progress.percent == 67)
  }

  @Test func 上限の目標を超えたら超過の量を出す() throws {
    let progress = try #require(ReferenceProgress(amount: 9, goal: Self.salt, energy: 2000))

    #expect(progress.isOver)
    #expect(progress.excess == 1.5)
    #expect(progress.remaining == 0)
    #expect(progress.percent == 120)
  }

  @Test func 飽和脂肪酸はエネルギーの割合をgに直して比べる() throws {
    // 1800 kcal の 7% は 126 kcal。脂質は 1 g 9 kcal なので 14 g
    let progress = try #require(ReferenceProgress(amount: 7, goal: Self.saturatedFat, energy: 1800))

    #expect(progress.target == 14)
    #expect(progress.percent == 50)
    #expect(progress.remaining == 7)
  }

  @Test func 比べるエネルギーが無ければ飽和脂肪酸は比べない() {
    #expect(ReferenceProgress(amount: 7, goal: Self.saturatedFat, energy: 0) == nil)
  }

  // MARK: 満たしたい栄養素

  @Test func 満たしたい栄養素は届くまで残りを出す() throws {
    let progress = try #require(ReferenceProgress(amount: 1300, goal: Self.potassium, energy: 2000))

    #expect(!progress.isLimit)
    #expect(!progress.isReached)
    #expect(progress.remaining == 1300)
    #expect(progress.percent == 50)
  }

  @Test func 満たしたい栄養素は届いたら到達にし超過とは呼ばない() throws {
    let progress = try #require(ReferenceProgress(amount: 800, goal: Self.calcium, energy: 2000))

    #expect(progress.isReached)
    #expect(!progress.isOver)
    #expect(progress.percent == 123)
  }

  @Test func ちょうど届いたら到達() throws {
    let progress = try #require(ReferenceProgress(amount: 650, goal: Self.calcium, energy: 2000))

    #expect(progress.isReached)
    #expect(progress.remaining == 0)
  }

  // MARK: 輪の長さ

  @Test func 輪は基準の量で一周して止まる() throws {
    #expect(try #require(ReferenceProgress(amount: 325, goal: Self.calcium, energy: 2000)).ringFraction == 0.5)
    #expect(try #require(ReferenceProgress(amount: 2000, goal: Self.calcium, energy: 2000)).ringFraction == 1)
  }

  // MARK: プロフィールから引く

  @Test func プロフィールから栄養素ごとの基準値を引く() throws {
    let url = try #require(Bundle.main.url(forResource: "DietaryReferenceIntakes", withExtension: "json"))
    let intakes = try DietaryReferenceIntakes(data: Data(contentsOf: url))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    let profile = PersonalProfile(
      birthDate: DateComponents(year: 1986, month: 4, day: 1), heightCm: 160, sex: .female, bodyType: .standard)
    let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23)))

    let goals = intakes.goals(for: profile, today: today, calendar: calendar)

    #expect(goals[.potassium]?.value == 2600)
    #expect(goals[.saltEquivalent]?.value == 6.5)
    #expect(goals[.calories] == nil)
  }
}
