import Foundation
import SwiftData

enum MealType: String, CaseIterable, Codable {
  case breakfast = "Breakfast"
  case lunch = "Lunch"
  case dinner = "Dinner"
  case snack = "Snack"

  var localizedName: String {
    return NSLocalizedString(self.rawValue, comment: "Meal type")
  }
}

@Model
final class Item {
  #Index<Item>([\.timestamp], [\.timestamp, \.mealTypeRawValue])
  #Unique<Item>([\.id])

  var id: String
  var brandName: String
  var productName: String
  var portion: String
  var numberOfServings: Double
  var baseCalories: Double
  var baseProtein: Double
  var baseFat: Double
  var baseCarbohydrates: Double
  var mealTypeRawValue: String
  var timestamp: Date

  @Transient
  var mealType: MealType {
    get { MealType(rawValue: mealTypeRawValue) ?? .snack }
    set { mealTypeRawValue = newValue.rawValue }
  }

  init(
    brandName: String, productName: String, portion: String,
    calories: Double, protein: Double, fat: Double, carbohydrates: Double,
    mealType: MealType, timestamp: Date, numberOfServings: Double = 1.0
  ) {
    self.id = UUID().uuidString
    self.brandName = brandName
    self.productName = productName
    self.portion = portion
    self.numberOfServings = numberOfServings
    self.baseCalories = calories
    self.baseProtein = protein
    self.baseFat = fat
    self.baseCarbohydrates = carbohydrates
    self.mealTypeRawValue = mealType.rawValue
    self.timestamp = timestamp
  }

  var name: String {
    "\(brandName) \(productName)"
  }

  // 栄養素の計算プロパティ
  var calories: Double {
    baseCalories * numberOfServings
  }

  var protein: Double {
    baseProtein * numberOfServings
  }

  var fat: Double {
    baseFat * numberOfServings
  }

  var carbohydrates: Double {
    baseCarbohydrates * numberOfServings
  }
}
