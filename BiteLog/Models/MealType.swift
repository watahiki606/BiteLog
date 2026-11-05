import Foundation
import SwiftUI

enum MealType: String, CaseIterable, Identifiable, Codable {
  case breakfast = "Breakfast"
  case lunch = "Lunch"
  case dinner = "Dinner"
  case snack = "Snack"

  var id: String { self.rawValue }

  /// 「その他」は使われていないので選択肢から外した。
  /// ただし外す前に記録された "Other" が残っていると、その日の記録が1件も
  /// 読めなくなる。間食として読み、記録自体は見えるようにしておく。
  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    if raw == "Other" {
      self = .snack
      return
    }
    guard let value = MealType(rawValue: raw) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unknown meal type: \(raw)"))
    }
    self = value
  }

  var localizedName: String {
    switch self {
    case .breakfast:
      return NSLocalizedString("Breakfast", comment: "Meal type")
    case .lunch:
      return NSLocalizedString("Lunch", comment: "Meal type")
    case .dinner:
      return NSLocalizedString("Dinner", comment: "Meal type")
    case .snack:
      return NSLocalizedString("Snack", comment: "Meal type")
    }
  }

  var accentColor: Color {
    switch self {
    case .breakfast: return .orange
    case .lunch: return .green
    case .dinner: return .indigo
    case .snack: return .pink
    }
  }

  /// 左下の追加ボタンから開いたときに最初に選んでおく食事。
  ///
  /// あとからまとめて記録することもあるので、これは仮の選択にすぎない。
  /// 追加画面の上部でいつでも切り替えられる前提で、今の時刻にいちばん近いものを選ぶ。
  static func suggested(at date: Date = Date(), calendar: Calendar = .current) -> MealType {
    switch calendar.component(.hour, from: date) {
    case 4..<10: return .breakfast
    case 10..<15: return .lunch
    case 15..<17: return .snack
    default: return .dinner
    }
  }

  var iconName: String {
    switch self {
    case .breakfast: return "sunrise.fill"
    case .lunch: return "sun.max.fill"
    case .dinner: return "moon.stars.fill"
    case .snack: return "cup.and.saucer.fill"
    }
  }
}
