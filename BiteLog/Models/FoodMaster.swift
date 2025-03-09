import Foundation
import SwiftData

@Model
final class FoodMaster {
  #Index<FoodMaster>(
    [\.usageCount, \.lastUsedDate, \.productName])

  @Attribute(.unique) var id: UUID  // ユニークIDを追加
  var brandName: String
  var productName: String
  var calories: Double
  var carbohydrates: Double
  var fat: Double
  var protein: Double
  var portionUnit: String
  var portion: Double  // 数量を表すので Double 型に変更
  @Attribute(.unique) var uniqueKey: String  // 栄養素に基づく一意キー

  // 使用頻度関連のプロパティ
  var usageCount: Int = 0  // 使用回数
  var lastUsedDate: Date?  // 最後に使用された日時

  init(
    id: UUID = UUID(), brandName: String, productName: String, calories: Double,
    carbohydrates: Double, fat: Double, protein: Double, portionUnit: String, portion: Double
  ) {
    self.id = id
    self.brandName = brandName
    self.productName = productName
    self.calories = calories
    self.carbohydrates = carbohydrates
    self.fat = fat
    self.protein = protein
    self.portionUnit = portionUnit
    self.portion = portion

    // 栄養素に基づく一意キーを生成
    let caloriesStr = String(format: "%.2f", calories)
    let carbsStr = String(format: "%.2f", carbohydrates)
    let fatStr = String(format: "%.2f", fat)
    let proteinStr = String(format: "%.2f", protein)
    self.uniqueKey =
      "\(brandName)|\(productName)|\(caloriesStr)|\(carbsStr)|\(fatStr)|\(proteinStr)|\(portionUnit)"
  }

  // 使用頻度を更新するメソッド
  func incrementUsage() {
    self.usageCount += 1
    self.lastUsedDate = Date()
  }

  // 使用頻度をデクリメントするメソッド
  func decrementUsage() {
    if self.usageCount > 0 {
      self.usageCount -= 1
    }
    // 最終使用日は更新しない（最後に使われた日時は変わらない）
  }
}
