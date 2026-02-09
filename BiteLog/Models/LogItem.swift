import Foundation
import SwiftData

@Model
final class LogItem {
  var timestamp: Date
  var logDate: String
  var mealType: MealType
  var numberOfServings: Double
  @Relationship var foodMaster: FoodMaster?

  // FoodMasterが削除された場合のバックアップデータ（NutritionSnapshotをJSON化して保存）
  var nutritionSnapshotData: Data?
  var isMasterDeleted: Bool = false

  // MARK: - 計算プロパティ

  /// 栄養素のスナップショットを取得（デコード）
  var nutritionSnapshot: NutritionSnapshot? {
    get {
      guard let data = nutritionSnapshotData else { return nil }
      return try? JSONDecoder().decode(NutritionSnapshot.self, from: data)
    }
    set {
      nutritionSnapshotData = try? JSONEncoder().encode(newValue)
    }
  }

  /// サービング数を掛けた栄養素値を取得
  var nutritionValues: NutritionValues {
    if let foodMaster = foodMaster {
      return NutritionSnapshot.from(foodMaster).scaled(by: numberOfServings)
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

  var brandName: String {
    foodMaster?.brandName ?? nutritionSnapshot?.brandName ?? ""
  }

  var productName: String {
    foodMaster?.productName ?? nutritionSnapshot?.productName ?? ""
  }

  var portionUnit: String {
    foodMaster?.portionUnit ?? nutritionSnapshot?.portionUnit ?? ""
  }

  init(
    timestamp: Date, mealType: MealType, numberOfServings: Double,
    foodMaster: FoodMaster? = nil
  ) {
    self.timestamp = timestamp
    self.logDate = LogItem.formatLogDate(timestamp)
    self.mealType = mealType
    self.numberOfServings = numberOfServings
    self.foodMaster = foodMaster

    // FoodMasterの情報をバックアップ
    if let food = foodMaster {
      self.nutritionSnapshot = NutritionSnapshot.from(food)
      food.incrementUsageWithServings(numberOfServings)
    }
  }

  /// FoodMasterが削除される前に呼び出すメソッド
  func backupFoodMasterData() {
    if let food = foodMaster {
      self.nutritionSnapshot = NutritionSnapshot.from(food)
      self.isMasterDeleted = true
    }
  }

  /// 日付文字列を生成（フィルタリング用）
  static func formatLogDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}
