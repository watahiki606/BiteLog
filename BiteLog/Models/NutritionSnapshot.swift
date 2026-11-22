import Foundation

/// FoodMasterの栄養素情報のスナップショット（LogItemのバックアップ用）
/// 栄養素値はportionSize分の量に対する値（CSVの元データそのまま）
struct NutritionSnapshot: Codable, Equatable {
  var brandName: String
  var productName: String
  var nutrients: NutrientAmounts
  var portionSize: Double
  var portionUnit: String

  init(
    brandName: String, productName: String, nutrients: NutrientAmounts, portionSize: Double,
    portionUnit: String
  ) {
    self.brandName = brandName
    self.productName = productName
    self.nutrients = nutrients
    self.portionSize = portionSize
    self.portionUnit = portionUnit
  }

  init(
    brandName: String, productName: String, calories: Double, netCarbs: Double, dietaryFiber: Double,
    fat: Double, protein: Double, portionSize: Double, portionUnit: String
  ) {
    self.init(
      brandName: brandName, productName: productName,
      nutrients: NutrientAmounts(
        calories: calories, protein: protein, fat: fat, netCarbs: netCarbs, dietaryFiber: dietaryFiber),
      portionSize: portionSize, portionUnit: portionUnit)
  }

  var calories: Double { nutrients.core(.calories) }
  var netCarbs: Double { nutrients.core(.netCarbs) }
  var dietaryFiber: Double { nutrients.core(.dietaryFiber) }
  var fat: Double { nutrients.core(.fat) }
  var protein: Double { nutrients.core(.protein) }
  var carbs: Double { netCarbs + dietaryFiber }

  /// 指定量に対する栄養素値を計算
  /// - Parameter amount: 実際の摂取量（例: 50g）
  /// - Returns: amount分の栄養素値
  func scaled(by amount: Double) -> NutritionValues {
    let ratio = portionSize > 0 ? amount / portionSize : 0
    return NutritionValues(nutrients.scaled(by: ratio))
  }

  // FoodMasterからのスナップショット作成はDTOs.swiftのextensionに移動

  private enum CodingKeys: String, CodingKey {
    case brandName, productName, portionSize, portionUnit
  }

  // 栄養素は名前や量と同じ階層に平らに並ぶ。サーバーに保存済みのスナップショットと同じ形
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    brandName = try container.decode(String.self, forKey: .brandName)
    productName = try container.decode(String.self, forKey: .productName)
    portionSize = try container.decode(Double.self, forKey: .portionSize)
    portionUnit = try container.decode(String.self, forKey: .portionUnit)
    nutrients = try NutrientAmounts(fromFlat: decoder)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(brandName, forKey: .brandName)
    try container.encode(productName, forKey: .productName)
    try container.encode(portionSize, forKey: .portionSize)
    try container.encode(portionUnit, forKey: .portionUnit)
    try nutrients.encodeFlat(to: encoder)
  }
}

/// 計算済みの栄養素値（実際の摂取量に対する値）
struct NutritionValues {
  let amounts: NutrientAmounts

  init(_ amounts: NutrientAmounts) {
    self.amounts = amounts
  }

  init(calories: Double, netCarbs: Double, dietaryFiber: Double, fat: Double, protein: Double) {
    self.init(
      NutrientAmounts(
        calories: calories, protein: protein, fat: fat, netCarbs: netCarbs, dietaryFiber: dietaryFiber))
  }

  var calories: Double { amounts.core(.calories) }
  var netCarbs: Double { amounts.core(.netCarbs) }
  var dietaryFiber: Double { amounts.core(.dietaryFiber) }
  var fat: Double { amounts.core(.fat) }
  var protein: Double { amounts.core(.protein) }
  var carbs: Double { netCarbs + dietaryFiber }

  static let zero = NutritionValues(
    calories: 0, netCarbs: 0, dietaryFiber: 0, fat: 0, protein: 0)

  /// 値の分かっている品だけを足す。どちらも分からない栄養素は、足した結果も分からないまま。
  /// 分からない品を 0 として足したことにはしないので、何品ぶんの合計かは `NutrientTotals` で数える
  static func + (lhs: NutritionValues, rhs: NutritionValues) -> NutritionValues {
    var sum = NutrientAmounts()
    for id in NutrientID.allCases {
      switch (lhs.amounts[id], rhs.amounts[id]) {
      case let (l?, r?): sum[id] = l + r
      case let (l?, nil): sum[id] = l
      case let (nil, r?): sum[id] = r
      case (nil, nil): break
      }
    }
    return NutritionValues(sum)
  }
}
