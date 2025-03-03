import Foundation
import SwiftData

@Model
final class LogItem {
  var timestamp: Date
  var mealType: MealType
  var numberOfServings: Double
  @Relationship var foodMaster: FoodMaster?  // FoodMasterへのリレーションシップ

  var baseCalories: Double {
    return (foodMaster?.calories ?? 0) * numberOfServings
  }
  var baseProtein: Double {
    return (foodMaster?.protein ?? 0) * numberOfServings
  }
  var baseFat: Double {
    return (foodMaster?.fat ?? 0) * numberOfServings
  }
  var baseCarbohydrates: Double {
    return (foodMaster?.carbohydrates ?? 0) * numberOfServings
  }
  var portion: Double {
    return foodMaster?.portion ?? 0
  }
  var brandName: String {
    return foodMaster?.brandName ?? ""
  }
  var productName: String {
    return foodMaster?.productName ?? ""
  }
  var calories: Double {
    return baseCalories
  }
  var protein: Double {
    return baseProtein
  }
  var fat: Double {
    return baseFat
  }
  var carbohydrates: Double {
    return baseCarbohydrates
  }
  var portionUnit: String {
    return foodMaster?.portionUnit ?? ""
  }

  init(
    timestamp: Date, mealType: MealType, numberOfServings: Double,
    foodMaster: FoodMaster? = nil
  ) {
    self.timestamp = timestamp
    self.mealType = mealType
    self.numberOfServings = numberOfServings
    self.foodMaster = foodMaster
  }
}
