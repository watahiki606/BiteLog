import Foundation
import Testing

@testable import BiteLog

/// 最初の5項目のあとに足した栄養素。値が分からない品があるので、0 とは区別して扱う。
struct AddedNutrientsTests {

  private static func values(salt: Double? = nil, saturatedFat: Double? = nil, calories: Double = 100)
    -> NutritionValues
  {
    var amounts = NutrientAmounts(calories: calories, protein: 1, fat: 1, netCarbs: 1, dietaryFiber: 1)
    amounts[.saltEquivalent] = salt
    amounts[.saturatedFat] = saturatedFat
    return NutritionValues(amounts)
  }

  // MARK: 合計

  @Test func 分かっている品だけを足す() {
    let sum = Self.values(salt: 1.5) + Self.values() + Self.values(salt: 2)

    #expect(sum.amounts[.saltEquivalent] == 3.5)
    #expect(sum.calories == 300)
  }

  @Test func どの品も分からなければ合計も分からない() {
    let sum = Self.values() + Self.values()

    #expect(sum.amounts[.saltEquivalent] == nil)
  }

  @Test func 品数を数える() {
    let totals = NutrientTotals(items: [Self.values(salt: 1.5), Self.values(), Self.values(salt: 2, saturatedFat: 3)])

    #expect(totals.itemCount == 3)
    #expect(totals.knownCount(.saltEquivalent) == 2)
    #expect(totals.knownCount(.saturatedFat) == 1)
    #expect(totals.isComplete(.calories))
    #expect(!totals.isComplete(.saltEquivalent))
  }

  @Test func 日ごとの集計から品数を読む() throws {
    let json = Data(
      """
      {"logDate": "2026-11-01", "mealType": "Lunch", "calories": 650, "protein": 15, "fat": 20,
       "netCarbs": 90, "dietaryFiber": 3, "saltEquivalent": 6, "itemCount": 3,
       "knownCounts": {"saltEquivalent": 2, "saturatedFat": 0}}
      """.utf8)

    let summary = try JSONDecoder().decode(DaySummaryDTO.self, from: json)
    let totals = summary.totals + summary.totals

    #expect(summary.nutrients[.saltEquivalent] == 6)
    #expect(summary.nutrients[.saturatedFat] == nil)
    #expect(totals.itemCount == 6)
    #expect(totals.knownCount(.saltEquivalent) == 4)
    #expect(totals.knownCount(.saturatedFat) == 0)
    #expect(totals.values.amounts[.saltEquivalent] == 12)
  }

  // MARK: 送る本文

  @Test func 食品を直す本文で分からないに戻す栄養素はnullを送る() throws {
    var dto = FoodMasterUpdateDTO(fat: 25)
    dto.nutrients[.saturatedFat] = 3
    dto.clearedNutrients = [.saltEquivalent]

    let data = try JSONEncoder().encode(dto)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["saturatedFat"] as? Double == 3)
    #expect(object["saltEquivalent"] is NSNull)
    #expect(object.keys.contains("protein") == false)
  }

  @Test func 食品を作る本文は出典を送る() throws {
    var dto = FoodMasterCreateDTO(
      id: "x", brandName: "AI", productName: "おにぎり", calories: 180, dietaryFiber: 1, netCarbs: 38,
      fat: 1, protein: 4, portionSize: 1, portionUnit: "個", uniqueKey: "k")
    dto.nutrients[.saltEquivalent] = 1.2
    dto.nutrientSource = "label"

    let data = try JSONEncoder().encode(dto)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["saltEquivalent"] as? Double == 1.2)
    #expect(object["nutrientSource"] as? String == "label")
    #expect(object["nutrientSourceRef"] == nil)
    #expect(object["saturatedFat"] == nil)
  }

  // MARK: 写真の解析の出典

  private static func analysis(basis: AnalysisBasis, confidence: String) -> FoodAnalysisResult {
    FoodAnalysisResult(
      productName: "おにぎり", calories: 180, protein: 4, fat: 1, netCarbs: 38, dietaryFiber: 1,
      portionAmount: 1, portionUnit: "個", confidence: confidence, basis: basis)
  }

  @Test func 写真だけの解析は信頼度が高ければ栄養成分表示を出典にする() {
    #expect(Self.analysis(basis: .photoOnly, confidence: "high").nutrientSource == ("label", nil))
    #expect(Self.analysis(basis: .photoOnly, confidence: "medium").nutrientSource == ("ai_estimate", nil))
  }

  @Test func 公式の値は出典のURLと一緒に保存する() {
    let url = URL(string: "https://example.com/menu")!

    #expect(Self.analysis(basis: .web(source: url), confidence: "medium").nutrientSource == ("manual", url.absoluteString))
    #expect(Self.analysis(basis: .nutritionLabel, confidence: "high").nutrientSource == ("label", nil))
    #expect(Self.analysis(basis: .estimatedAfterSearch, confidence: "low").nutrientSource == ("ai_estimate", nil))
  }

  // MARK: 目標量

  private static let intakes = DietaryReferenceIntakes.bundled!

  @Test func 食塩相当量の目標量は性別と年齢で引く() {
    #expect(Self.intakes.goal(for: .saltEquivalent, sex: .male, age: 40)?.value == 7.5)
    #expect(Self.intakes.goal(for: .saltEquivalent, sex: .female, age: 40)?.value == 6.5)
    #expect(Self.intakes.goal(for: .saltEquivalent, sex: .male, age: 13)?.value == 7.0)
    #expect(Self.intakes.goal(for: .saltEquivalent, sex: .female, age: 2)?.value == 2.5)
    #expect(Self.intakes.goal(for: .saltEquivalent, sex: .male, age: 80)?.comparison == .lessThan)
    #expect(Self.intakes.goal(for: .saltEquivalent, sex: .male, age: 0) == nil)
  }

  @Test func 飽和脂肪酸の目標量はエネルギーに占める割合で引く() {
    let adult = Self.intakes.goal(for: .saturatedFat, sex: .female, age: 40)

    #expect(adult?.value == 7)
    #expect(adult?.comparison == .atMostPercentOfEnergy)
    #expect(Self.intakes.goal(for: .saturatedFat, sex: .male, age: 16)?.value == 9)
    #expect(Self.intakes.goal(for: .saturatedFat, sex: .male, age: 2) == nil)
  }

  @Test func カリウムは目標量で以上と比べる() {
    let goal = Self.intakes.goal(for: .potassium, sex: .female, age: 40)
    #expect(goal?.value == 2600)
    #expect(goal?.comparison == .atLeast)
    #expect(goal?.indicator == .tentativeDietaryGoal)
    #expect(Self.intakes.goal(for: .potassium, sex: .male, age: 2) == nil)
  }

  @Test func ミネラルとビタミンは推奨量や目安量と並べるだけ() {
    #expect(Self.intakes.goal(for: .calcium, sex: .male, age: 40)?.value == 750)
    #expect(Self.intakes.goal(for: .calcium, sex: .male, age: 40)?.comparison == .reference)
    #expect(Self.intakes.goal(for: .calcium, sex: .male, age: 40)?.indicator == .recommendedDietaryAllowance)
    #expect(Self.intakes.goal(for: .magnesium, sex: .female, age: 40)?.value == 290)
    #expect(Self.intakes.goal(for: .vitaminA, sex: .male, age: 40)?.value == 900)
    #expect(Self.intakes.goal(for: .vitaminC, sex: .female, age: 80)?.value == 100)
    #expect(Self.intakes.goal(for: .vitaminD, sex: .female, age: 40)?.indicator == .adequateIntake)
    #expect(Self.intakes.goal(for: .vitaminD, sex: .female, age: 40)?.value == 9)
  }

  @Test func 女性の鉄は月経の有無で2つの値を持つ() {
    let woman = Self.intakes.goal(for: .iron, sex: .female, age: 40)
    #expect(woman?.value == 6.0)
    #expect(woman?.menstruatingValue == 10.5)
    #expect(Self.intakes.goal(for: .iron, sex: .female, age: 70)?.menstruatingValue == nil)
    #expect(Self.intakes.goal(for: .iron, sex: .male, age: 40)?.menstruatingValue == nil)
  }

  @Test func 詳しい栄養素は推奨量か目安量と並べる() {
    #expect(Self.intakes.goal(for: .zinc, sex: .male, age: 40)?.value == 9.5)
    #expect(Self.intakes.goal(for: .zinc, sex: .male, age: 40)?.indicator == .recommendedDietaryAllowance)
    #expect(Self.intakes.goal(for: .folate, sex: .female, age: 40)?.value == 240)
    #expect(Self.intakes.goal(for: .niacin, sex: .female, age: 40)?.value == 12)
    #expect(Self.intakes.goal(for: .vitaminK, sex: .female, age: 40)?.indicator == .adequateIntake)
    #expect(Self.intakes.goal(for: .n3FattyAcids, sex: .male, age: 55)?.value == 2.3)
    #expect(Self.intakes.goal(for: .pantothenicAcid, sex: .female, age: 13)?.value == 6)
    #expect(Self.intakes.goal(for: .vitaminE, sex: .female, age: 20)?.value == 5.0)
    for id in NutrientID.detailNutrients {
      #expect(Self.intakes.goal(for: id, sex: .female, age: 40)?.comparison == .reference, "\(id)")
    }
  }

  @Test func どの栄養素も最初の5項目か入力欄に出すものか詳しい栄養素のどれか1つ() {
    for id in NutrientID.allCases {
      let kinds = [id.definition.core, NutrientID.labelNutrients.contains(id), NutrientID.detailNutrients.contains(id)]
      #expect(kinds.filter { $0 }.count == 1, "\(id)")
    }
    #expect(NutrientID.labelNutrients.contains(.vitaminC))
    #expect(NutrientID.detailNutrients.contains(.zinc))
  }

  @Test func 目標量の無い栄養素は引けない() {
    #expect(Self.intakes.goal(for: .calories, sex: .male, age: 40) == nil)
  }

  // MARK: CSV

  @Test func CSVの書き出しは末尾に足した栄養素の列を置き分からない値は空にする() throws {
    let food = FoodMasterDTO(
      id: UUID(), brandName: "Home", productName: "カレー", calories: 650, dietaryFiber: 3, netCarbs: 90,
      fat: 20, protein: 15, portionSize: 1, portionUnit: "皿", uniqueKey: "k", usageCount: 0,
      lastNumberOfServings: 1)
    var withSalt = food
    withSalt.nutrients[.saltEquivalent] = 2.5
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    func item(_ food: FoodMasterDTO) -> LogItemDTO {
      LogItemDTO(
        id: UUID(), timestamp: Date(timeIntervalSince1970: 0), logDate: "1970-01-01", mealType: .lunch,
        numberOfServings: 1, isMasterDeleted: false, foodMaster: food, nutritionSnapshot: nil)
    }

    let added = NutrientID.allCases.filter { !$0.definition.core }
    #expect(added.first == .saltEquivalent)
    #expect(CSVExporter.header.hasSuffix("portion_unit," + added.map(\.definition.column).joined(separator: ",")))
    // 食塩の後ろに、分からない栄養素の空のセルが続く
    #expect(
      CSVExporter.row(for: item(withSalt), dateFormatter: formatter)
        .hasSuffix(",皿,2.5" + String(repeating: ",", count: added.count - 1)))
    #expect(
      CSVExporter.row(for: item(food), dateFormatter: formatter).hasSuffix(",皿" + String(repeating: ",", count: added.count)))
  }
}
