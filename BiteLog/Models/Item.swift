import Foundation
import SwiftData

enum MealType: String, CaseIterable, Codable {
  case breakfast = "朝食"
  case lunch = "昼食"
  case dinner = "夕食"
  case snack = "間食"
}

@Model
final class Item {
  @Attribute(.unique) var id: String
  var brandName: String
  var productName: String
  var portion: String
  var calories: Double
  var protein: Double
  var fat: Double
  var carbohydrates: Double
  var mealType: MealType
  @Attribute(.externalStorage) var timestamp: Date

  init(
    brandName: String, productName: String, portion: String,
    calories: Double, protein: Double, fat: Double, carbohydrates: Double,
    mealType: MealType, timestamp: Date
  ) {
    self.id = UUID().uuidString
    self.brandName = brandName
    self.productName = productName
    self.portion = portion
    self.calories = calories
    self.protein = protein
    self.fat = fat
    self.carbohydrates = carbohydrates
    self.mealType = mealType
    self.timestamp = timestamp
  }

  var name: String {
    "\(brandName) \(productName)"
  }
}
