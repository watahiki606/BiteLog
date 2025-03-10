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
  var dietaryFiber: Double  // 食物繊維を追加
  var sugar: Double  // 糖質を追加
  var fat: Double
  var protein: Double
  var portionUnit: String
  var portion: Double  // 数量を表すので Double 型に変更
  @Attribute(.unique) var uniqueKey: String  // 栄養素に基づく一意キー

  // 使用頻度関連のプロパティ
  var usageCount: Int = 0  // 使用回数
  var lastUsedDate: Date?  // 最後に使用された日時
  var lastNumberOfServings: Double = 1.0  // 最後に使用したサービング数

  // 炭水化物は食物繊維と糖質の合計として計算
  var carbohydrates: Double {
    return sugar + dietaryFiber
  }

  init(
    id: UUID = UUID(), brandName: String, productName: String, calories: Double,
    sugar: Double, dietaryFiber: Double, fat: Double, protein: Double, portionUnit: String,
    portion: Double
  ) {
    self.id = id
    self.brandName = brandName
    self.productName = productName
    self.calories = calories
    self.sugar = sugar
    self.dietaryFiber = dietaryFiber
    self.fat = fat
    self.protein = protein
    self.portionUnit = portionUnit
    self.portion = portion
    self.lastNumberOfServings = 1.0  // デフォルト値を設定

    // 栄養素に基づく一意キーを生成
    let caloriesStr = String(format: "%.2f", calories)
    let sugarStr = String(format: "%.2f", sugar)
    let fiberStr = String(format: "%.2f", dietaryFiber)
    let fatStr = String(format: "%.2f", fat)
    let proteinStr = String(format: "%.2f", protein)
    self.uniqueKey =
      "\(brandName)|\(productName)|\(caloriesStr)|\(sugarStr)|\(fiberStr)|\(fatStr)|\(proteinStr)|\(portionUnit)"
  }

  // 使用頻度とサービング数を更新するメソッド
  func incrementUsageWithServings(_ servings: Double) {
    self.usageCount += 1
    self.lastUsedDate = Date()
    self.lastNumberOfServings = servings
  }

  // 使用頻度をデクリメントするメソッド
  func decrementUsage() {
    if self.usageCount > 0 {
      self.usageCount -= 1
    }
    // 最終使用日は更新しない（最後に使われた日時は変わらない）
  }
}
