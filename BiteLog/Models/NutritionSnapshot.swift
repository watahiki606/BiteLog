import Foundation

/// FoodMasterの栄養素情報のスナップショット（LogItemのバックアップ用）
/// 栄養素値はportionSize分の量に対する値（CSVの元データそのまま）
struct NutritionSnapshot: Codable, Equatable {
  var brandName: String
  var productName: String
  var calories: Double
  var netCarbs: Double
  var dietaryFiber: Double
  var fat: Double
  var protein: Double
  var portionSize: Double
  var portionUnit: String

  var carbs: Double { netCarbs + dietaryFiber }

  /// 指定量に対する栄養素値を計算
  /// - Parameter amount: 実際の摂取量（例: 50g）
  /// - Returns: amount分の栄養素値
  func scaled(by amount: Double) -> NutritionValues {
    let ratio = portionSize > 0 ? amount / portionSize : 0
    return NutritionValues(
      calories: calories * ratio,
      netCarbs: netCarbs * ratio,
      dietaryFiber: dietaryFiber * ratio,
      fat: fat * ratio,
      protein: protein * ratio
    )
  }

  /// FoodMasterからスナップショットを作成
  static func from(_ foodMaster: FoodMaster) -> NutritionSnapshot {
    NutritionSnapshot(
      brandName: foodMaster.brandName,
      productName: foodMaster.productName,
      calories: foodMaster.calories,
      netCarbs: foodMaster.netCarbs,
      dietaryFiber: foodMaster.dietaryFiber,
      fat: foodMaster.fat,
      protein: foodMaster.protein,
      portionSize: foodMaster.portionSize,
      portionUnit: foodMaster.portionUnit
    )
  }
}

/// 計算済みの栄養素値（実際の摂取量に対する値）
struct NutritionValues {
  let calories: Double
  let netCarbs: Double
  let dietaryFiber: Double
  let fat: Double
  let protein: Double

  var carbs: Double { netCarbs + dietaryFiber }

  static let zero = NutritionValues(
    calories: 0, netCarbs: 0, dietaryFiber: 0, fat: 0, protein: 0)

  static func + (lhs: NutritionValues, rhs: NutritionValues) -> NutritionValues {
    NutritionValues(
      calories: lhs.calories + rhs.calories,
      netCarbs: lhs.netCarbs + rhs.netCarbs,
      dietaryFiber: lhs.dietaryFiber + rhs.dietaryFiber,
      fat: lhs.fat + rhs.fat,
      protein: lhs.protein + rhs.protein
    )
  }
}
