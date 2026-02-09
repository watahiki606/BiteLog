import Foundation
import SwiftData

@Model
final class FoodMaster {
  #Index<FoodMaster>(
    [\.usageCount, \.lastUsedDate, \.productName])

  @Attribute(.unique) var id: UUID
  var brandName: String
  var productName: String
  var calories: Double
  var dietaryFiber: Double
  var netCarbs: Double
  var fat: Double
  var protein: Double
  var portionSize: Double
  var portionUnit: String
  @Attribute(.unique) var uniqueKey: String

  // 使用頻度関連のプロパティ
  var usageCount: Int = 0
  var lastUsedDate: Date?
  var lastNumberOfServings: Double = 1.0

  // 炭水化物は食物繊維と糖質の合計として計算
  var carbohydrates: Double {
    return netCarbs + dietaryFiber
  }

  init(
    id: UUID = UUID(), brandName: String, productName: String, calories: Double,
    netCarbs: Double, dietaryFiber: Double, fat: Double, protein: Double,
    portionSize: Double = 1.0, portionUnit: String
  ) {
    self.id = id
    self.brandName = brandName
    self.productName = productName
    self.calories = calories
    self.netCarbs = netCarbs
    self.dietaryFiber = dietaryFiber
    self.fat = fat
    self.protein = protein
    self.portionSize = portionSize
    self.portionUnit = portionUnit
    self.lastNumberOfServings = portionSize

    self.uniqueKey = FoodMaster.createUniqueKey(
      brandName: brandName, productName: productName, portionUnit: portionUnit)
  }

  /// uniqueKeyを生成する静的メソッド（CSVImporterと共用）
  static func createUniqueKey(brandName: String, productName: String, portionUnit: String) -> String
  {
    "\(brandName)|\(productName)|\(portionUnit)"
  }
}

// MARK: - 使用統計
extension FoodMaster {
  /// 使用頻度とサービング数を更新するメソッド
  func incrementUsageWithServings(_ servings: Double) {
    self.usageCount += 1
    self.lastUsedDate = Date()
    self.lastNumberOfServings = servings
  }

  /// 使用頻度をデクリメントするメソッド
  func decrementUsage() {
    if self.usageCount > 0 {
      self.usageCount -= 1
    }
  }
}
