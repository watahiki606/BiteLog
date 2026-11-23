import Foundation
import Testing

@testable import BiteLog

/// 食事の質のスコア。NRF9.3 日本版から添加糖を除いた形で、満点は900
struct DietQualityScoreTests {

  private static let intakes = DietaryReferenceIntakes.bundled!

  /// 30〜49歳男性の推定エネルギー必要量。この7日分のエネルギーなら、換算しても合計の7分の1がそのまま1日分になる
  private static let maleEER = 2750.0

  /// 7日分の合計。値は1日あたりで渡す
  private static func totals(
    perDay: [NutrientID: Double], calories: Double = maleEER, days: Double = 7, itemCount: Int = 10,
    knownCounts: [NutrientID: Int] = [:]
  ) -> NutrientTotals {
    var amounts = NutrientAmounts(
      calories: calories * days, protein: (perDay[.protein] ?? 0) * days, fat: 0, netCarbs: 0,
      dietaryFiber: (perDay[.dietaryFiber] ?? 0) * days)
    var counts: [NutrientID: Int] = [:]
    for id in NutrientID.allCases where !id.definition.core {
      if let v = perDay[id] { amounts[id] = v * days }
      counts[id] = knownCounts[id] ?? itemCount
    }
    return NutrientTotals(values: NutritionValues(amounts), itemCount: itemCount, knownCounts: counts)
  }

  /// 30〜49歳男性の参照量に対して、推奨する栄養素がちょうど100%、制限する栄養素がちょうど100%になる1日分
  private static let maleAtReference: [NutrientID: Double] = [
    .protein: 65, .dietaryFiber: 22, .vitaminA: 900, .vitaminC: 100, .vitaminD: 9.0, .calcium: 750,
    .iron: 7.5, .potassium: 3000, .magnesium: 380, .saturatedFat: 0.07 * maleEER / 9, .saltEquivalent: 7.5,
  ]

  private static func evaluate(
    _ totals: NutrientTotals, periodDays: Int = 7, loggedDays: Int = 7, sex: TanitaProfile.Sex = .male, age: Int = 40
  ) -> DietQualityScore.Result {
    DietQualityScore.evaluate(
      totals: totals, periodDays: periodDays, loggedDays: loggedDays, sex: sex, age: age, intakes: intakes)
  }

  private static func score(_ result: DietQualityScore.Result) -> DietQualityScore? {
    if case .score(let score) = result { return score }
    return nil
  }

  private static func shortfalls(_ result: DietQualityScore.Result) -> [DietQualityScore.Shortfall] {
    if case .unavailable(let shortfalls) = result { return shortfalls }
    return []
  }

  // MARK: 計算

  @Test func 推奨する栄養素が参照量にそろい制限する栄養素が参照量ちょうどなら満点() throws {
    let score = try #require(Self.score(Self.evaluate(Self.totals(perDay: Self.maleAtReference))))

    #expect(abs(score.score - 900) < 0.001)
    #expect(score.components.count == 11)
  }

  @Test func 推奨する栄養素は100パーセントで打ち切る() throws {
    var perDay = Self.maleAtReference
    perDay[.vitaminC] = 300

    let score = try #require(Self.score(Self.evaluate(Self.totals(perDay: perDay))))

    #expect(abs(score.score - 900) < 0.001)
    #expect(abs((score.component(.vitaminC)?.percentOfReference ?? 0) - 300) < 0.001)
    #expect(abs((score.component(.vitaminC)?.points ?? 0) - 100) < 0.001)
  }

  @Test func 推奨する栄養素は参照量に対する割合を足す() throws {
    var perDay = Self.maleAtReference
    perDay[.dietaryFiber] = 11
    perDay[.magnesium] = 190

    let score = try #require(Self.score(Self.evaluate(Self.totals(perDay: perDay))))

    #expect(abs(score.score - 800) < 0.001)
  }

  @Test func 制限する栄養素は参照量を超えた分だけ引く() throws {
    var perDay = Self.maleAtReference
    perDay[.saltEquivalent] = 7.5 * 1.1
    perDay[.saturatedFat] = 0.07 * Self.maleEER / 9 * 1.2

    let score = try #require(Self.score(Self.evaluate(Self.totals(perDay: perDay))))

    #expect(abs(score.score - 870) < 0.001)
    #expect(abs((score.component(.saltEquivalent)?.points ?? 0) - -10) < 0.001)
  }

  @Test func 制限する栄養素が参照量より少なくても足さない() throws {
    var perDay = Self.maleAtReference
    perDay[.saltEquivalent] = 3

    let score = try #require(Self.score(Self.evaluate(Self.totals(perDay: perDay))))

    #expect(abs(score.score - 900) < 0.001)
  }

  @Test func 摂取量はエネルギーで調整して推定エネルギー必要量に換算する() throws {
    // エネルギーが必要量の倍なら、同じ量でも換算後は半分になる
    let score = try #require(
      Self.score(Self.evaluate(Self.totals(perDay: Self.maleAtReference, calories: Self.maleEER * 2))))

    #expect(abs((score.component(.protein)?.percentOfReference ?? 0) - 50) < 0.001)
    #expect(abs((score.component(.saltEquivalent)?.percentOfReference ?? 0) - 50) < 0.001)
    #expect(abs(score.score - 450) < 0.001)
  }

  @Test func 女性の鉄は月経なしの推奨量と比べる() throws {
    let perDay: [NutrientID: Double] = [.iron: 6.0]
    let score = try #require(
      Self.score(Self.evaluate(Self.totals(perDay: perDay, calories: 2050), sex: .female)))

    #expect(abs((score.component(.iron)?.percentOfReference ?? 0) - 100) < 0.001)
  }

  // MARK: 出す条件

  @Test func 期間が7日より短ければ出さない() {
    let result = Self.evaluate(Self.totals(perDay: Self.maleAtReference), periodDays: 6, loggedDays: 6)

    #expect(Self.shortfalls(result) == [.periodTooShort])
  }

  @Test func 記録のある日が5日より少なければ出さない() {
    let result = Self.evaluate(Self.totals(perDay: Self.maleAtReference), periodDays: 30, loggedDays: 4)

    #expect(Self.shortfalls(result) == [.tooFewLoggedDays])
  }

  @Test func 値の分かっていた品が8割に満たない栄養素があれば出さない() {
    let short = Self.totals(perDay: Self.maleAtReference, knownCounts: [.potassium: 7, .vitaminD: 0])
    let enough = Self.totals(perDay: Self.maleAtReference, knownCounts: [.potassium: 8])

    #expect(Self.shortfalls(Self.evaluate(short)) == [.manyUnknownItems([.vitaminD, .potassium])])
    #expect(Self.score(Self.evaluate(enough)) != nil)
  }

  @Test func エネルギーの合計が0なら出さない() {
    let result = Self.evaluate(Self.totals(perDay: Self.maleAtReference, calories: 0))

    #expect(Self.shortfalls(result) == [.noEnergy])
  }

  @Test func 品が無ければ出さない() {
    let result = Self.evaluate(.empty, loggedDays: 0)

    #expect(Self.shortfalls(result) == [.tooFewLoggedDays, .noEnergy])
  }

  @Test func 十八歳未満には出さない() {
    let result = Self.evaluate(Self.totals(perDay: Self.maleAtReference), age: 17)

    #expect(Self.shortfalls(result) == [.notAdult])
  }

  @Test func 満たしていない条件はすべて返す() {
    let result = Self.evaluate(
      Self.totals(perDay: Self.maleAtReference, knownCounts: [.calcium: 1]), periodDays: 3, loggedDays: 2, age: 10)

    #expect(Self.shortfalls(result) == [.notAdult, .periodTooShort, .tooFewLoggedDays, .manyUnknownItems([.calcium])])
  }

  @Test func プロフィールが無ければ出さない() {
    let result = DietQualityScore.evaluate(
      totals: Self.totals(perDay: Self.maleAtReference), periodDays: 7, loggedDays: 7, profile: nil,
      intakes: Self.intakes)

    #expect(Self.shortfalls(result) == [.noProfile])
  }

  @Test func プロフィールの生年月日から今日の年齢で引く() throws {
    let calendar = Calendar(identifier: .gregorian)
    let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23)))
    let profile = PersonalProfile(
      birthDate: DateComponents(year: 2008, month: 11, day: 24), heightCm: 170, sex: .male, bodyType: .standard)

    let result = DietQualityScore.evaluate(
      totals: Self.totals(perDay: Self.maleAtReference), periodDays: 7, loggedDays: 7, profile: profile,
      intakes: Self.intakes, today: today, calendar: calendar)

    #expect(Self.shortfalls(result) == [.notAdult])
  }

  // MARK: 参照量

  @Test func たんぱく質と食物繊維の参照量を引く() {
    #expect(Self.intakes.goal(for: .protein, sex: .male, age: 40)?.value == 65)
    #expect(Self.intakes.goal(for: .protein, sex: .female, age: 13)?.value == 55)
    #expect(Self.intakes.goal(for: .protein, sex: .male, age: 40)?.indicator == .recommendedDietaryAllowance)
    #expect(Self.intakes.goal(for: .dietaryFiber, sex: .female, age: 40)?.value == 18)
    #expect(Self.intakes.goal(for: .dietaryFiber, sex: .male, age: 80)?.value == 20)
    #expect(Self.intakes.goal(for: .dietaryFiber, sex: .male, age: 40)?.comparison == .atLeast)
    #expect(Self.intakes.goal(for: .dietaryFiber, sex: .male, age: 2) == nil)
  }

  @Test func 推定エネルギー必要量は身体活動レベルふつうの値を引く() {
    #expect(Self.intakes.estimatedEnergyRequirement(sex: .male, age: 40) == 2750)
    #expect(Self.intakes.estimatedEnergyRequirement(sex: .female, age: 40) == 2050)
    #expect(Self.intakes.estimatedEnergyRequirement(sex: .female, age: 80) == 1750)
    #expect(Self.intakes.estimatedEnergyRequirement(sex: .male, age: 1) == 950)
    #expect(Self.intakes.estimatedEnergyRequirement(sex: .male, age: 0) == nil)
  }
}
