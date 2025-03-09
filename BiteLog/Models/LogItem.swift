import Foundation
import SwiftData

@Model
final class LogItem {
  var timestamp: Date
  var mealType: MealType
  var numberOfServings: Double
  @Relationship var foodMaster: FoodMaster?  // FoodMasterへのリレーションシップ
  
  // FoodMasterが削除された場合のバックアップデータ
  var backupFoodId: UUID?
  var backupBrandName: String?
  var backupProductName: String?
  var backupCalories: Double?
  var backupSugar: Double?
  var backupDietaryFiber: Double?
  var backupFat: Double?
  var backupProtein: Double?
  var backupPortionUnit: String?
  var backupPortion: Double?
  var isMasterDeleted: Bool = false

  var calories: Double {
    if let foodMaster = foodMaster {
      return foodMaster.calories * numberOfServings
    } else if let backupCalories = backupCalories {
      return backupCalories * numberOfServings
    }
    return 0
  }
  
  var protein: Double {
    if let foodMaster = foodMaster {
      return foodMaster.protein * numberOfServings
    } else if let backupProtein = backupProtein {
      return backupProtein * numberOfServings
    }
    return 0
  }
  
  var fat: Double {
    if let foodMaster = foodMaster {
      return foodMaster.fat * numberOfServings
    } else if let backupFat = backupFat {
      return backupFat * numberOfServings
    }
    return 0
  }
  
  var sugar: Double {
    if let foodMaster = foodMaster {
      return foodMaster.sugar * numberOfServings
    } else if let backupSugar = backupSugar {
      return backupSugar * numberOfServings
    }
    return 0
  }
  
  var dietaryFiber: Double {
    if let foodMaster = foodMaster {
      return foodMaster.dietaryFiber * numberOfServings
    } else if let backupDietaryFiber = backupDietaryFiber {
      return backupDietaryFiber * numberOfServings
    }
    return 0
  }
  
  var carbohydrates: Double {
    return sugar + dietaryFiber
  }
  
  var portion: Double {
    if let foodMaster = foodMaster {
      return foodMaster.portion
    }
    return backupPortion ?? 0
  }
  
  var brandName: String {
    if let foodMaster = foodMaster {
      return foodMaster.brandName
    }
    return backupBrandName ?? ""
  }
  
  var productName: String {
    if let foodMaster = foodMaster {
      return foodMaster.productName
    }
    return backupProductName ?? ""
  }
  
  var portionUnit: String {
    if let foodMaster = foodMaster {
      return foodMaster.portionUnit
    }
    return backupPortionUnit ?? ""
  }

  init(
    timestamp: Date, mealType: MealType, numberOfServings: Double,
    foodMaster: FoodMaster? = nil
  ) {
    self.timestamp = timestamp
    self.mealType = mealType
    self.numberOfServings = numberOfServings
    self.foodMaster = foodMaster
    
    // FoodMasterの情報をバックアップ
    if let food = foodMaster {
      self.backupFoodId = food.id
      self.backupBrandName = food.brandName
      self.backupProductName = food.productName
      self.backupCalories = food.calories
      self.backupSugar = food.sugar
      self.backupDietaryFiber = food.dietaryFiber
      self.backupFat = food.fat
      self.backupProtein = food.protein
      self.backupPortionUnit = food.portionUnit
      self.backupPortion = food.portion
      
      // FoodMasterの使用頻度を更新
      food.incrementUsage()
    }
  }
  
  // FoodMasterが削除される前に呼び出すメソッド
  func backupFoodMasterData() {
    if let food = foodMaster {
      self.backupFoodId = food.id
      self.backupBrandName = food.brandName
      self.backupProductName = food.productName
      self.backupCalories = food.calories
      self.backupSugar = food.sugar
      self.backupDietaryFiber = food.dietaryFiber
      self.backupFat = food.fat
      self.backupProtein = food.protein
      self.backupPortionUnit = food.portionUnit
      self.backupPortion = food.portion
      self.isMasterDeleted = true
    }
  }
}
