import Foundation

enum MealType: String, CaseIterable, Identifiable, Codable {
  case breakfast = "Breakfast"
  case lunch = "Lunch"
  case dinner = "Dinner"
  case snack = "Snack"

  var id: String { self.rawValue }

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
}
