import Foundation
import Testing

@testable import BiteLog

/// 食品を成分表にひも付けるときの初期値
struct CompositionLinkTests {
  @Test func 量がgかmlならその数を重さの初期値にする() {
    #expect(CompositionLink.defaultGrams(portionSize: 60, portionUnit: "g") == 60)
    #expect(CompositionLink.defaultGrams(portionSize: 200, portionUnit: "ml") == 200)
    #expect(CompositionLink.defaultGrams(portionSize: 150, portionUnit: "グラム") == 150)
  }

  @Test func 個や人前なら100gにする() {
    #expect(CompositionLink.defaultGrams(portionSize: 1, portionUnit: "個") == 100)
    #expect(CompositionLink.defaultGrams(portionSize: 1, portionUnit: "人前") == 100)
  }

  @Test func 候補は食品名の最初の語で探す() {
    #expect(CompositionLink.query(for: "鶏むね肉（皮なし）") == "鶏むね肉")
    #expect(CompositionLink.query(for: "ゆで卵") == "ゆで卵")
  }

  @Test func 成分表で補った栄養素を見分ける() throws {
    let json = """
      {"id":"11111111-1111-1111-1111-111111111111","brandName":"b","productName":"p","calories":1,"protein":1,
       "fat":1,"netCarbs":1,"dietaryFiber":0,"potassium":65,"portionSize":1,"portionUnit":"個","uniqueKey":"k",
       "usageCount":0,"lastNumberOfServings":1,"nutrientSources":{"potassium":"composition_table"},
       "components":[{"foodNumber":"12005","grams":50,"name":"鶏卵 全卵 ゆで"}]}
      """
    let food = try JSONDecoder().decode(FoodMasterDTO.self, from: Data(json.utf8))
    #expect(food.isSupplemented(.potassium))
    #expect(!food.isSupplemented(.calories))
    #expect(food.components == [FoodComponent(foodNumber: "12005", grams: 50, name: "鶏卵 全卵 ゆで")])
  }

  @Test func 写真の解析の応答から足した栄養素と食材を読む() throws {
    let json = """
      {"calories":592,"protein":23,"fat":11,"netCarbs":99,"dietaryFiber":4.5,"portionAmount":1,"portionUnit":"人前",
       "confidence":"medium","productName":"親子丼","saltEquivalent":2,"potassium":312.5,
       "components":[{"foodNumber":"01088","grams":250,"name":"めし"}]}
      """
    let response = try JSONDecoder().decode(AIAnalyzeResponse.self, from: Data(json.utf8))
    #expect(response.addedNutrients[.potassium] == 312.5)
    #expect(response.addedNutrients[.saltEquivalent] == 2)
    #expect(response.addedNutrients[.calories] == nil)
    #expect(response.components?.first?.foodNumber == "01088")
  }
}
