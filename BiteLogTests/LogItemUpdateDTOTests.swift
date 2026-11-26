import Foundation
import Testing

@testable import BiteLog

/// 記録の更新では、変わった項目だけをサーバーに送る。
struct LogItemUpdateDTOTests {

  private static func item(mealType: MealType, servings: Double) -> LogItemDTO {
    let food = FoodMasterDTO(
      id: UUID(), brandName: "架空商店", productName: "試作おにぎり", calories: 180, dietaryFiber: 1,
      netCarbs: 38, fat: 1, protein: 4, portionSize: 1, portionUnit: "個",
      uniqueKey: "架空商店|試作おにぎり|個", usageCount: 3, lastNumberOfServings: 1)
    return LogItemDTO(
      id: UUID(), timestamp: Date(timeIntervalSince1970: 1_767_220_241), logDate: "2026-01-01",
      mealType: mealType, numberOfServings: servings, isMasterDeleted: false, foodMaster: food,
      nutritionSnapshot: nil)
  }

  @Test func 食事だけ変えたら量は送らない() {
    let dto = LogItemUpdateDTO(
      changesFrom: Self.item(mealType: .lunch, servings: 2), numberOfServings: 2, mealType: .breakfast)

    #expect(dto.mealType == "Breakfast")
    #expect(dto.numberOfServings == nil)
    #expect(dto.timestamp == nil)
  }

  @Test func 量だけ変えたら食事は送らない() {
    let dto = LogItemUpdateDTO(
      changesFrom: Self.item(mealType: .lunch, servings: 2), numberOfServings: 3, mealType: .lunch)

    #expect(dto.numberOfServings == 3)
    #expect(dto.mealType == nil)
    #expect(dto.timestamp == nil)
  }

  @Test func 何も変えなければ何も送らない() {
    let dto = LogItemUpdateDTO(
      changesFrom: Self.item(mealType: .dinner, servings: 1.5), numberOfServings: 1.5, mealType: .dinner)

    #expect(dto.numberOfServings == nil)
    #expect(dto.mealType == nil)
    #expect(dto.timestamp == nil)
  }
}
