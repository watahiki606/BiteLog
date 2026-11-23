import Foundation
import Testing

@testable import BiteLog

/// 栄養素を持つ型の JSON の形。サーバー、公開中の古い版のアプリ、保存済みのスナップショットと
/// 同じ平らなキーで読み書きできることを確かめる。5つの栄養素にはすべて別の値を入れ、取り違えに気づけるようにする。
struct NutrientJSONTests {

  private static let nutrients: [String: Double] = [
    "calories": 650, "protein": 15, "fat": 20, "netCarbs": 90, "dietaryFiber": 3,
  ]

  /// 栄養素に別のキーを足した JSON の中身
  private static func with(_ extra: [String: Any]) -> [String: Any] {
    var object: [String: Any] = nutrients
    for (key, value) in extra { object[key] = value }
    return object
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private static func json(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
  }

  private static func object(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private static func expectNutrients(_ object: [String: Any]) {
    for (key, value) in nutrients {
      #expect(object[key] as? Double == value, "\(key)")
    }
  }

  private static let foodJSON: [String: Any] = with([
    "id": "11111111-1111-1111-1111-111111111111", "brandName": "Home", "productName": "カレーライス",
    "portionSize": 1, "portionUnit": "皿", "uniqueKey": "Home|カレーライス|皿",
    "usageCount": 2, "lastUsedDate": "2026-11-01T12:00:00Z", "lastNumberOfServings": 1.5,
  ])

  @Test func 食品を読んで同じキーで書き戻す() throws {
    let food = try Self.decoder().decode(FoodMasterDTO.self, from: Self.json(Self.foodJSON))

    #expect(food.calories == 650)
    #expect(food.protein == 15)
    #expect(food.fat == 20)
    #expect(food.netCarbs == 90)
    #expect(food.dietaryFiber == 3)
    #expect(food.usageCount == 2)
    #expect(food.lastNumberOfServings == 1.5)
    #expect(food.isMine == nil)

    let written = try Self.object(food)
    Self.expectNutrients(written)
    #expect(written["productName"] as? String == "カレーライス")
    #expect(written["isMine"] == nil)
  }

  @Test func 必須の栄養素が無い食品は読まない() throws {
    // 今のサーバーは5つを必ず返す。欠けていれば壊れた応答として扱う
    var json = Self.foodJSON
    json["dietaryFiber"] = nil

    #expect(throws: DecodingError.self) {
      try Self.decoder().decode(FoodMasterDTO.self, from: Self.json(json))
    }
  }

  @Test func スナップショットは名前と量と栄養素だけを平らなキーで書く() throws {
    let snapshot = NutritionSnapshot(
      brandName: "Home", productName: "カレーライス", calories: 650, netCarbs: 90,
      dietaryFiber: 3, fat: 20, protein: 15, portionSize: 1, portionUnit: "皿")

    let written = try Self.object(snapshot)

    #expect(Set(written.keys) == Set(Self.nutrients.keys).union(["brandName", "productName", "portionSize", "portionUnit"]))
    Self.expectNutrients(written)
    let read = try JSONDecoder().decode(NutritionSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(read == snapshot)
  }

  @Test func 食品を作る本文は栄養素を平らなキーで送る() throws {
    let dto = FoodMasterCreateDTO(
      id: "x", brandName: "Home", productName: "カレーライス", calories: 650, dietaryFiber: 3,
      netCarbs: 90, fat: 20, protein: 15, portionSize: 1, portionUnit: "皿", uniqueKey: "k")

    Self.expectNutrients(try Self.object(dto))
  }

  @Test func 食品を直す本文は送る栄養素だけを含める() throws {
    let dto = FoodMasterUpdateDTO(fat: 25)

    let written = try Self.object(dto)

    #expect(written["fat"] as? Double == 25)
    #expect(written["calories"] == nil)
    #expect(written["protein"] == nil)
  }

  @Test func 記録の値は食品の値を量で按分する() throws {
    let food = try Self.decoder().decode(FoodMasterDTO.self, from: Self.json(Self.foodJSON))
    let item = LogItemDTO(
      id: UUID(), timestamp: Date(), logDate: "2026-11-01", mealType: .lunch, numberOfServings: 2,
      isMasterDeleted: false, foodMaster: food, nutritionSnapshot: nil)

    #expect(item.calories == 1300)
    #expect(item.protein == 30)
    #expect(item.fat == 40)
    #expect(item.netCarbs == 180)
    #expect(item.dietaryFiber == 6)
    #expect(item.carbohydrates == 186)
  }

  @Test func 日ごとの集計を読む() throws {
    let summary = try JSONDecoder().decode(
      DaySummaryDTO.self,
      from: Self.json(Self.with(["logDate": "2026-11-01", "mealType": "Lunch"])))

    #expect(summary.nutritionValues.calories == 650)
    #expect(summary.nutritionValues.protein == 15)
    #expect(summary.nutritionValues.fat == 20)
    #expect(summary.nutritionValues.netCarbs == 90)
    #expect(summary.nutritionValues.dietaryFiber == 3)
  }

  @Test func 日次の統計を読む() throws {
    let stat = try JSONDecoder().decode(
      DailyStatDTO.self,
      from: Self.json(Self.with(["date": "2026-11-01", "weightKg": 60.5])))

    #expect(stat.calories == 650)
    #expect(stat.protein == 15)
    #expect(stat.fat == 20)
    #expect(stat.netCarbs == 90)
    #expect(stat.dietaryFiber == 3)
    #expect(stat.weightKg == 60.5)
    #expect(stat.bodyFatPercent == nil)
  }
}
