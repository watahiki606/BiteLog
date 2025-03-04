import Foundation
import SwiftData

@Model
final class LogItem {
  var timestamp: Date
  var mealType: MealType
  var numberOfServings: Double
  @Relationship var foodMaster: FoodMaster?  // FoodMasterへのリレーションシップ

  var calories: Double {
    return (foodMaster?.calories ?? 0) * numberOfServings
  }
  
  var protein: Double {
    return (foodMaster?.protein ?? 0) * numberOfServings
  }
  
  var fat: Double {
    return (foodMaster?.fat ?? 0) * numberOfServings
  }
  
  var carbohydrates: Double {
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
