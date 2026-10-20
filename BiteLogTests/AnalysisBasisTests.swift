import Foundation
import Testing

@testable import BiteLog

/// 写真解析の値が何に基づくか。結果画面で、Web で調べたかどうかと出典を見せるのに使う。
struct AnalysisBasisTests {

  @Test func 店名を入れなければ写真だけの推定になる() {
    #expect(AnalysisBasis(menuName: nil, basis: nil, sourceUrl: nil) == .photoOnly)
  }

  @Test func 公式の値で出典があれば出典のURLを持つ() {
    let basis = AnalysisBasis(
      menuName: "くら寿司 サーモン", basis: "official",
      sourceUrl: "https://www.kurasushi.co.jp/common/pdf/kura_allergen.pdf")

    #expect(basis == .web(source: URL(string: "https://www.kurasushi.co.jp/common/pdf/kura_allergen.pdf")))
  }

  @Test func 公式の値でも出典が無ければURLを持たない() {
    let basis = AnalysisBasis(menuName: "ジョナサン カラマリ", basis: "official", sourceUrl: nil)

    #expect(basis == .web(source: nil))
  }

  @Test func 調べても見つからなければ写真から推定したことになる() {
    let basis = AnalysisBasis(menuName: "とんから亭 棒ひれかつ定食", basis: "estimate", sourceUrl: nil)

    #expect(basis == .estimatedAfterSearch)
  }

  @Test func 成分表示が写っていれば成分表示の値になる() {
    #expect(AnalysisBasis(menuName: "明治 プロセスチーズ", basis: "label", sourceUrl: nil) == .nutritionLabel)
  }

  @Test func 知らない根拠は写真から推定したことにする() {
    // 公式の値だと言い切れないものを公式として見せない
    #expect(AnalysisBasis(menuName: "スシロー", basis: "unknown", sourceUrl: nil) == .estimatedAfterSearch)
  }

  @Test func 根拠と出典を返さない古いWorkerの返答も読める() throws {
    let json = """
      {"calories":180,"protein":4,"fat":1,"netCarbs":38,"dietaryFiber":1,
       "portionAmount":1,"portionUnit":"個","confidence":"medium","productName":"おにぎり"}
      """

    let response = try JSONDecoder().decode(AIAnalyzeResponse.self, from: Data(json.utf8))

    #expect(response.basis == nil)
    #expect(response.sourceUrl == nil)
  }
}

/// 候補から選んで記録するときの量。
struct FoodMasterServingsToLogTests {

  private func foodMaster(portionSize: Double, usageCount: Int, lastNumberOfServings: Double) -> FoodMasterDTO {
    FoodMasterDTO(
      id: UUID(), brandName: "スシロー", productName: "サーモンアボカド", calories: 140,
      dietaryFiber: 0, netCarbs: 0, fat: 0, protein: 0, portionSize: portionSize, portionUnit: "g",
      uniqueKey: "スシロー|サーモンアボカド|g", createdBy: nil, isMine: false,
      usageCount: usageCount, lastUsedDate: nil, lastNumberOfServings: lastNumberOfServings)
  }

  @Test func 使ったことがあれば前回の量で記録する() {
    #expect(foodMaster(portionSize: 100, usageCount: 3, lastNumberOfServings: 50).servingsToLog == 50)
  }

  @Test func 使ったことが無ければ1食分の量で記録する() {
    // サーバーは使ったことが無い食品の前回量を 1 で返す。100g の食品なら 1g になってしまう
    #expect(foodMaster(portionSize: 100, usageCount: 0, lastNumberOfServings: 1).servingsToLog == 100)
  }
}

/// 結果画面の「登録済みの食品」を探す語。
struct CandidateQueriesTests {

  @Test func 見当があれば見当で探し次に料理名の頭で探す() {
    let queries = AIFoodAnalyzer.candidateQueries(menuGuess: "くら寿司 サーモン", productName: "サーモン（くら寿司）")

    #expect(queries == ["くら寿司 サーモン", "サーモン"])
  }

  @Test func 見当が無ければ料理名の頭だけで探す() {
    #expect(AIFoodAnalyzer.candidateQueries(menuGuess: nil, productName: "親子丼（卵とじ）") == ["親子丼"])
  }

  @Test func 一文字の語では探さない() {
    // 1文字だと関係の無い食品が大量に当たる
    #expect(AIFoodAnalyzer.candidateQueries(menuGuess: nil, productName: "茶") == [])
  }

  @Test func 同じ語は二度探さない() {
    #expect(AIFoodAnalyzer.candidateQueries(menuGuess: "おにぎり", productName: "おにぎり（鮭）") == ["おにぎり"])
  }
}
