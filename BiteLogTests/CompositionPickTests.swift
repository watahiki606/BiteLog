import Foundation
import Testing

@testable import BiteLog

/// 食品の入力で、成分表から選んだ食品の値を欄に入れる
struct CompositionPickTests {
  @Test func 量がgかmlならその数を重さの初期値にする() {
    #expect(CompositionPick.defaultGrams(portionSize: 60, portionUnit: "g") == 60)
    #expect(CompositionPick.defaultGrams(portionSize: 200, portionUnit: "ml") == 200)
    #expect(CompositionPick.defaultGrams(portionSize: 150, portionUnit: "グラム") == 150)
  }

  @Test func 個や人前なら100gにする() {
    #expect(CompositionPick.defaultGrams(portionSize: 1, portionUnit: "個") == 100)
    #expect(CompositionPick.defaultGrams(portionSize: 1, portionUnit: "人前") == 100)
  }

  @Test func 候補は食品名の最初の語で探す() {
    #expect(CompositionPick.query(for: "鶏むね肉（皮なし）") == "鶏むね肉")
    #expect(CompositionPick.query(for: "ゆで卵") == "ゆで卵")
  }

  @Test func 重さの分の値を欄の文字にする() {
    // ゆで卵 50 g。成分表で未測定のビタミン D は欄に入れない
    let texts = CompositionPick.fieldTexts(
      per100g: ["calories": 134, "protein": 12.4, "fat": 10.4, "netCarbs": 0.4, "dietaryFiber": 0, "potassium": 130],
      grams: 50)
    #expect(texts[.calories] == "67")
    #expect(texts[.protein] == "6.2")
    #expect(texts[.fat] == "5.2")
    #expect(texts[.dietaryFiber] == "0")
    #expect(texts[.added(.potassium)] == "65")
    #expect(texts[.added(.vitaminD)] == nil)
  }

  @Test func 炭水化物の欄には糖質と食物繊維を足した値を入れる() {
    let texts = CompositionPick.fieldTexts(per100g: ["netCarbs": 35.6, "dietaryFiber": 1.5], grams: 100)
    #expect(texts[.carbohydrate] == "37.1")
  }

  @Test func 糖質か食物繊維のどちらかが未測定なら炭水化物の欄は空のまま() {
    let texts = CompositionPick.fieldTexts(per100g: ["netCarbs": 35.6], grams: 100)
    #expect(texts[.carbohydrate] == nil)
  }

  @Test func 空の欄にだけ書いて手で入れた値は残す() {
    // ラベルの5項目を入れたあとに選んだ。ラベルのほうが商品に近い
    let merged = CompositionPick.merge(
      current: [.calories: "336", .added(.potassium): ""],
      picked: [.calories: "325", .added(.potassium): "720"],
      previouslyPicked: [:])
    // 書き換える欄だけが返る
    #expect(merged == [.added(.potassium): "720"])
  }

  @Test func 選び直すと前に選んだ値を入れ替えて新しい候補に無い値は空に戻す() {
    let merged = CompositionPick.merge(
      current: [.calories: "160", .added(.vitaminD): "0.4", .added(.potassium): "50"],
      picked: [.calories: "156"],
      previouslyPicked: [.calories: "160", .added(.vitaminD): "0.4", .added(.potassium): "29"])
    // 前に選んだあと手で直したカリウムは残す
    #expect(merged == [.calories: "156", .added(.vitaminD): ""])
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
