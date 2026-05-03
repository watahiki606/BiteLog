import Foundation

// MARK: - FoodMaster DTO

struct FoodMasterDTO: Codable, Identifiable, Hashable {
  var id: UUID
  var brandName: String
  var productName: String
  var calories: Double
  var dietaryFiber: Double
  var netCarbs: Double
  var fat: Double
  var protein: Double
  var portionSize: Double
  var portionUnit: String
  var uniqueKey: String
  var usageCount: Int
  var lastUsedDate: Date?
  var lastNumberOfServings: Double

  var carbohydrates: Double { netCarbs + dietaryFiber }

  static func createUniqueKey(brandName: String, productName: String, portionUnit: String) -> String {
    "\(brandName)|\(productName)|\(portionUnit)"
  }
}

struct FoodMasterCreateDTO: Codable {
  var id: String
  var brandName: String
  var productName: String
  var calories: Double
  var dietaryFiber: Double
  var netCarbs: Double
  var fat: Double
  var protein: Double
  var portionSize: Double
  var portionUnit: String
  var uniqueKey: String
}

struct FoodMasterUpdateDTO: Codable {
  var brandName: String?
  var productName: String?
  var calories: Double?
  var dietaryFiber: Double?
  var netCarbs: Double?
  var fat: Double?
  var protein: Double?
  var portionSize: Double?
  var portionUnit: String?
}

struct FoodMasterListResponse: Codable {
  var items: [FoodMasterDTO]
  var total: Int
  var hasMore: Bool
}

// MARK: - LogItem DTO

struct LogItemDTO: Codable, Identifiable {
  var id: UUID
  var timestamp: Date
  var logDate: String
  var mealType: MealType
  var numberOfServings: Double
  var isMasterDeleted: Bool
  var foodMaster: FoodMasterDTO?
  var nutritionSnapshot: NutritionSnapshot?

  var nutritionValues: NutritionValues {
    if let fm = foodMaster {
      return NutritionSnapshot.from(fm).scaled(by: numberOfServings)
    } else if let snapshot = nutritionSnapshot {
      return snapshot.scaled(by: numberOfServings)
    }
    return .zero
  }

  var calories: Double { nutritionValues.calories }
  var protein: Double { nutritionValues.protein }
  var fat: Double { nutritionValues.fat }
  var netCarbs: Double { nutritionValues.netCarbs }
  var dietaryFiber: Double { nutritionValues.dietaryFiber }
  var carbohydrates: Double { nutritionValues.carbs }

  var brandName: String { foodMaster?.brandName ?? nutritionSnapshot?.brandName ?? "" }
  var productName: String { foodMaster?.productName ?? nutritionSnapshot?.productName ?? "" }
  var portionUnit: String { foodMaster?.portionUnit ?? nutritionSnapshot?.portionUnit ?? "" }
}

struct LogItemCreateDTO: Codable {
  var id: String
  var timestamp: String
  var logDate: String
  var mealType: String
  var numberOfServings: Double
  var foodMasterId: String?
  var nutritionSnapshot: NutritionSnapshot?
}

struct LogItemUpdateDTO: Codable {
  var numberOfServings: Double?
  var mealType: String?
  var timestamp: String?
}

struct LogItemListResponse: Codable {
  var items: [LogItemDTO]
  var hasMore: Bool?
}

// MARK: - NutritionGoals DTO

struct NutritionGoalsDTO: Codable {
  var targetProtein: Double
  var targetFat: Double
  var targetNetCarbs: Double
  var targetFiber: Double

  var targetCalories: Double {
    targetProtein * 4 + targetFat * 9 + targetNetCarbs * 4 + targetFiber * 2
  }
}

// MARK: - Auth DTO

struct AuthRequest: Codable {
  var provider: String
  var identityToken: String
}

struct AuthResponse: Codable {
  var token: String
  var userId: String
}

// MARK: - Batch Result

struct BatchResult: Codable {
  var created: Int
  var skipped: Int
  var errors: Int
}

// MARK: - NutritionSnapshot extension（FoodMasterDTOから生成）

extension NutritionSnapshot {
  static func from(_ dto: FoodMasterDTO) -> NutritionSnapshot {
    NutritionSnapshot(
      brandName: dto.brandName,
      productName: dto.productName,
      calories: dto.calories,
      netCarbs: dto.netCarbs,
      dietaryFiber: dto.dietaryFiber,
      fat: dto.fat,
      protein: dto.protein,
      portionSize: dto.portionSize,
      portionUnit: dto.portionUnit
    )
  }
}
