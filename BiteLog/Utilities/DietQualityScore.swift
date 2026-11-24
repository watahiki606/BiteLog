import Foundation

/// 食事の質のスコア。NRF9.3 日本版から添加糖を除いた形で、満点は900。
///
/// 推奨する9栄養素は参照量に対する割合を100%で打ち切って足し、制限する2栄養素は参照量を超えた分を引く。
/// 摂取量はエネルギーで調整し、推定エネルギー必要量に換算してから参照量と比べる。Murakami 2019 の方法による。
///
/// 値の分からない品は 0 として数えない。0 にすると、記録の欠けの分だけ点が下がり、食事ではなく欠けを測ることになる。
/// 栄養素ごとに、値の分かっていた品の量をその品のカロリーで割って換算する。
/// 分からない品の食べ方が、分かっている品と同じ割合だったとみなすことになる。
///
/// 添加糖は成分表に列が無い。糖質で代えると、でんぷんの多いごはんやいもまで減点するので外した。
/// そのため研究の NRF9.3 とは同じ点にならない。
struct DietQualityScore: Equatable {
  enum Role: Equatable {
    /// 推奨する栄養素。割合を100%で打ち切って足す
    case encouraged
    /// 制限する栄養素。参照量を超えた分を引く
    case limited
  }

  struct Component: Equatable {
    let nutrient: NutrientID
    let role: Role
    /// 推定エネルギー必要量に換算した摂取量の、参照量に対する割合。打ち切る前の値
    let percentOfReference: Double

    /// 点への寄与。制限する栄養素は0以下
    var points: Double {
      switch role {
      case .encouraged: return min(100, percentOfReference)
      case .limited: return -max(0, percentOfReference - 100)
      }
    }
  }

  /// 出せない理由。満たしていない条件をすべて返す
  enum Shortfall: Equatable {
    case noProfile
    case notAdult
    /// 選んだ期間が7日より短い。基準は習慣的な摂取量に対するもの
    case periodTooShort
    /// 記録のある日が5日より少ない
    case tooFewLoggedDays
    /// 値の分かっていた品が無いか、あってもカロリーが 0 の栄養素。換算のもとが無い
    case noKnownValues([NutrientID])
    case noEnergy
  }

  enum Result: Equatable {
    case score(DietQualityScore)
    case unavailable([Shortfall])
  }

  static let maximum = 900.0
  static let encouraged: [NutrientID] = [
    .protein, .dietaryFiber, .vitaminA, .vitaminC, .vitaminD, .calcium, .iron, .potassium, .magnesium,
  ]
  static let limited: [NutrientID] = [.saturatedFat, .saltEquivalent]

  static let minimumAge = 18
  static let minimumPeriodDays = 7
  static let minimumLoggedDays = 5

  let components: [Component]
  /// 値の分からない品のある栄養素が1つでもあるか。あれば点は目安になる
  let hasUnknownItems: Bool

  var score: Double { components.map(\.points).reduce(0, +) }

  func component(_ nutrient: NutrientID) -> Component? {
    components.first { $0.nutrient == nutrient }
  }

  static func evaluate(
    totals: NutrientTotals, periodDays: Int, loggedDays: Int, profile: PersonalProfile?,
    intakes: DietaryReferenceIntakes, today: Date = Date(), calendar: Calendar = .current
  ) -> Result {
    guard let profile, let age = profile.age(on: today, calendar: calendar) else { return .unavailable([.noProfile]) }
    return evaluate(
      totals: totals, periodDays: periodDays, loggedDays: loggedDays, sex: profile.sex, age: age, intakes: intakes)
  }

  static func evaluate(
    totals: NutrientTotals, periodDays: Int, loggedDays: Int, sex: TanitaProfile.Sex, age: Int,
    intakes: DietaryReferenceIntakes
  ) -> Result {
    let nutrients = encouraged + limited
    var shortfalls: [Shortfall] = []
    if age < minimumAge { shortfalls.append(.notAdult) }
    if periodDays < minimumPeriodDays { shortfalls.append(.periodTooShort) }
    if loggedDays < minimumLoggedDays { shortfalls.append(.tooFewLoggedDays) }
    if totals.values.calories <= 0 {
      shortfalls.append(.noEnergy)
    } else {
      let noValues = nutrients.filter { totals.knownEnergy($0) <= 0 }
      if !noValues.isEmpty { shortfalls.append(.noKnownValues(noValues)) }
    }
    guard shortfalls.isEmpty else { return .unavailable(shortfalls) }

    guard let eer = intakes.estimatedEnergyRequirement(sex: sex, age: age) else {
      return .unavailable([.notAdult])
    }
    var components: [Component] = []
    for id in nutrients {
      guard let reference = referenceAmount(id, sex: sex, age: age, eer: eer, intakes: intakes), reference > 0
      else { continue }
      // 値の分かっていた品の量を、その品のカロリーで割って換算する
      let adjusted = (totals.values.amounts[id] ?? 0) / totals.knownEnergy(id) * eer
      components.append(
        Component(
          nutrient: id, role: encouraged.contains(id) ? .encouraged : .limited,
          percentOfReference: adjusted / reference * 100))
    }
    return .score(
      DietQualityScore(components: components, hasUnknownItems: nutrients.contains(where: totals.hasUnknownItems)))
  }

  /// 参照量。女性の鉄は、月経の有無を聞かないので月経なしの値を使う。
  /// 飽和脂肪酸の目標量はエネルギーに占める割合なので、推定エネルギー必要量からグラムに換える
  private static func referenceAmount(
    _ id: NutrientID, sex: TanitaProfile.Sex, age: Int, eer: Double, intakes: DietaryReferenceIntakes
  ) -> Double? {
    guard let goal = intakes.goal(for: id, sex: sex, age: age) else { return nil }
    if goal.comparison == .atMostPercentOfEnergy { return goal.value / 100 * eer / 9 }
    return goal.value
  }
}
