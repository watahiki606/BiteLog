import Testing

@testable import BiteLog

struct NutritionFormatterTests {

  @Test func 整数の栄養値は小数点を出さない() {
    #expect(NutritionFormatter.formatNutrition(1) == "1")
    #expect(NutritionFormatter.formatNutrition(0) == "0")
  }

  @Test func 小数のある栄養値は1桁に丸める() {
    #expect(NutritionFormatter.formatNutrition(1.5) == "1.5")
    #expect(NutritionFormatter.formatNutrition(1.234) == "1.2")
  }

  /// カロリーは 0.1 kcal 単位に意味が無いので整数にする。
  @Test func カロリーは整数に丸める() {
    #expect(NutritionFormatter.formatCalories(71.4) == "71")
    #expect(NutritionFormatter.formatCalories(71.5) == "72")
    #expect(NutritionFormatter.formatCalories(0) == "0")
  }

  @Test func 栄養素ごとに桁数を使い分ける() {
    #expect(Nutrient.calories.format(114.6) == "115")
    #expect(Nutrient.protein.format(24.14) == "24.1")
    #expect(Nutrient.fiber.format(2) == "2")
  }

  @Test func 単位は栄養素から引ける() {
    #expect(Nutrient.calories.unit == "kcal")
    #expect(Nutrient.protein.unit == "g")
  }
}
