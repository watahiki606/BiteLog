import Foundation

/// 食事摂取基準の基準値。アプリに同梱した DietaryReferenceIntakes.json から、性別と年齢で引く。
///
/// 性別と生年月日は端末の中の `PersonalProfile` にしか無いので、サーバーには置かない。
struct DietaryReferenceIntakes {
  /// 基準と比べる向き
  enum Comparison: String, Decodable {
    /// 値が目標量より少なければよい。食塩相当量
    case lessThan
    /// エネルギーに占める割合が目標量以下ならよい。飽和脂肪酸
    case atMostPercentOfEnergy
    /// 値が目標量以上ならよい。カリウム
    case atLeast
    /// 良し悪しの向きを持たず、基準の値と並べるだけ。推奨量や目安量
    case reference
  }

  /// 指標の種類。画面の書き方を変える
  enum Indicator: String, Decodable {
    case tentativeDietaryGoal
    case recommendedDietaryAllowance
    /// 目安量。下回っても不足とは判定できないので、割合を出さない
    case adequateIntake
  }

  struct Goal: Equatable {
    let nutrient: NutrientID
    let indicator: Indicator
    let comparison: Comparison
    let value: Double
    /// 女性の鉄の、月経がある場合の値。月経の有無はプロフィールで聞かないので、両方を並べる
    var menstruatingValue: Double? = nil
  }

  private struct File: Decodable {
    struct Entry: Decodable {
      struct Band: Decodable {
        let sex: String
        let minAge: Int
        let maxAge: Int?
        let value: Double
        let menstruatingValue: Double?
      }
      let nutrient: NutrientID
      let indicator: Indicator
      let comparison: Comparison
      let bands: [Band]
    }
    struct EnergyRequirement: Decodable {
      let bands: [Entry.Band]
    }
    let goals: [Entry]
    let estimatedEnergyRequirement: EnergyRequirement
  }

  private let entries: [File.Entry]
  private let energyBands: [File.Entry.Band]

  init(data: Data) throws {
    let file = try JSONDecoder().decode(File.self, from: data)
    entries = file.goals
    energyBands = file.estimatedEnergyRequirement.bands
  }

  /// 同梱のファイル。読めなければ目標量を出さない
  static let bundled: DietaryReferenceIntakes? = {
    guard let url = Bundle.main.url(forResource: "DietaryReferenceIntakes", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? DietaryReferenceIntakes(data: data)
  }()

  /// 目標量。その性別と年齢に目標量が無ければ nil
  func goal(for nutrient: NutrientID, sex: TanitaProfile.Sex, age: Int) -> Goal? {
    guard let entry = entries.first(where: { $0.nutrient == nutrient }),
      let band = Self.band(entry.bands, sex: sex, age: age)
    else { return nil }
    return Goal(
      nutrient: nutrient, indicator: entry.indicator, comparison: entry.comparison, value: band.value,
      menstruatingValue: band.menstruatingValue)
  }

  /// プロフィールの性別と、今日の年齢で引く
  func goal(for nutrient: NutrientID, profile: PersonalProfile, today: Date = Date(), calendar: Calendar = .current)
    -> Goal?
  {
    guard let age = profile.age(on: today, calendar: calendar) else { return nil }
    return goal(for: nutrient, sex: profile.sex, age: age)
  }

  /// プロフィールで引いた、目標量のある栄養素すべて
  func goals(for profile: PersonalProfile, today: Date = Date(), calendar: Calendar = .current)
    -> [NutrientID: Goal]
  {
    var goals: [NutrientID: Goal] = [:]
    for id in NutrientID.allCases {
      if let goal = goal(for: id, profile: profile, today: today, calendar: calendar) { goals[id] = goal }
    }
    return goals
  }

  /// 端末に保存したプロフィールで引く。性別と生年月日が無ければ空
  static func goalsForSavedProfile() -> [NutrientID: Goal] {
    guard let profile = PersonalProfile.load(), let intakes = bundled else { return [:] }
    return intakes.goals(for: profile)
  }

  /// 推定エネルギー必要量。身体活動レベル「ふつう」の値。1歳未満は nil
  func estimatedEnergyRequirement(sex: TanitaProfile.Sex, age: Int) -> Double? {
    Self.band(energyBands, sex: sex, age: age)?.value
  }

  private static func band(_ bands: [File.Entry.Band], sex: TanitaProfile.Sex, age: Int) -> File.Entry.Band? {
    let sexName = sex == .male ? "male" : "female"
    return bands.first { $0.sex == sexName && age >= $0.minAge && age <= ($0.maxAge ?? Int.max) }
  }
}
