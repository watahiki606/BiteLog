import Foundation
import SwiftUI

enum MealType: String, CaseIterable, Identifiable, Codable {
  case breakfast = "Breakfast"
  case lunch = "Lunch"
  case dinner = "Dinner"
  case snack = "Snack"
  case other = "Other"

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
    case .other:
      return NSLocalizedString("Other", comment: "Meal type")
    }
  }

  var accentColor: Color {
    switch self {
    case .breakfast: return .orange
    case .lunch: return .green
    case .dinner: return .indigo
    case .snack: return .pink
    case .other: return .gray
    }
  }

  var iconName: String {
    switch self {
    case .breakfast: return "sunrise.fill"
    case .lunch: return "sun.max.fill"
    case .dinner: return "moon.stars.fill"
    case .snack: return "cup.and.saucer.fill"
    case .other: return "fork.knife"
    }
  }
}
