import Foundation

/// 食事摂取基準の目標量。アプリに同梱した DietaryReferenceIntakes.json から、性別と年齢で引く。
///
/// 性別と生年月日は端末の中の `PersonalProfile` にしか無いので、サーバーには置かない。
struct DietaryReferenceIntakes {
  /// 目標量と比べる向き
  enum Comparison: String, Decodable {
    /// 値が目標量より少なければよい。食塩相当量
    case lessThan
    /// エネルギーに占める割合が目標量以下ならよい。飽和脂肪酸
    case atMostPercentOfEnergy
  }

  struct Goal: Equatable {
    let nutrient: NutrientID
    let comparison: Comparison
    let value: Double
  }

  private struct File: Decodable {
    struct Entry: Decodable {
      struct Band: Decodable {
        let sex: String
        let minAge: Int
        let maxAge: Int?
        let value: Double
      }
      let nutrient: NutrientID
      let comparison: Comparison
      let bands: [Band]
    }
    let goals: [Entry]
  }

  private let entries: [File.Entry]

  init(data: Data) throws {
    entries = try JSONDecoder().decode(File.self, from: data).goals
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
    let sexName = sex == .male ? "male" : "female"
    guard let entry = entries.first(where: { $0.nutrient == nutrient }),
      let band = entry.bands.first(where: {
        $0.sex == sexName && age >= $0.minAge && age <= ($0.maxAge ?? Int.max)
      })
    else { return nil }
    return Goal(nutrient: nutrient, comparison: entry.comparison, value: band.value)
  }

  /// プロフィールの性別と、今日の年齢で引く
  func goal(for nutrient: NutrientID, profile: PersonalProfile, today: Date = Date(), calendar: Calendar = .current)
    -> Goal?
  {
    guard let birth = calendar.date(from: profile.birthDate),
      let age = calendar.dateComponents([.year], from: birth, to: today).year
    else { return nil }
    return goal(for: nutrient, sex: profile.sex, age: age)
  }
}
