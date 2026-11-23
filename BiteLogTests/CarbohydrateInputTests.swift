import Testing

@testable import BiteLog

/// 入力欄は炭水化物とうち食物繊維。保存は糖質と食物繊維
struct CarbohydrateInputTests {

  @Test func 炭水化物から食物繊維を引いた値を糖質として保存する() {
    let input = CarbohydrateInput(carbohydrate: "40.2", dietaryFiber: "1.6")
    #expect(input.netCarbs == 38.6)
    #expect(input.fiber == 1.6)
    #expect(input.isValid)
  }

  @Test func 食物繊維が空欄なら0として保存し糖質は炭水化物と同じ() {
    let input = CarbohydrateInput(carbohydrate: "31", dietaryFiber: "")
    #expect(input.netCarbs == 31)
    #expect(input.fiber == 0)
  }

  @Test func 炭水化物が空欄なら0() {
    let input = CarbohydrateInput(carbohydrate: "", dietaryFiber: "")
    #expect(input.netCarbs == 0)
    #expect(input.fiber == 0)
    #expect(input.isValid)
  }

  @Test func 食物繊維が炭水化物より多ければ保存できない() {
    let input = CarbohydrateInput(carbohydrate: "2", dietaryFiber: "3")
    #expect(!input.isValid)
  }

  @Test func 小数の誤差で糖質がずれない() {
    // 0.3 - 0.1 は 0.19999999999999998 になる
    let input = CarbohydrateInput(carbohydrate: "0.3", dietaryFiber: "0.1")
    #expect(input.netCarbs == 0.2)
  }

  @Test func 保存済みの糖質と食物繊維から炭水化物の欄を作る() {
    #expect(CarbohydrateInput.carbohydrateText(netCarbs: 38.6, dietaryFiber: 1.6) == "40.2")
    #expect(CarbohydrateInput.carbohydrateText(netCarbs: 31, dietaryFiber: 0) == "31")
  }
}
