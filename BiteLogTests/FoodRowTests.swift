import Testing

@testable import BiteLog

/// 一覧に出す食品名の組み立て。
struct FoodRowDisplayNameTests {

  @Test func ブランド名と商品名が違うときは両方並べる() {
    #expect(
      FoodRow.displayName(brand: "セブンプレミアム", product: "サラダチキン")
        == "セブンプレミアム サラダチキン")
  }

  @Test func ブランド名が空なら商品名だけを出す() {
    #expect(FoodRow.displayName(brand: "", product: "ごはん") == "ごはん")
  }

  /// 実データにはブランド名へ商品名と同じ語を入れている行が多い。
  @Test func ブランド名が商品名と同じなら重ねない() {
    #expect(FoodRow.displayName(brand: "ゆで卵", product: "ゆで卵") == "ゆで卵")
  }

  @Test func 前後の空白は落としてから判定する() {
    #expect(FoodRow.displayName(brand: " ", product: "きゅうり") == "きゅうり")
    #expect(FoodRow.displayName(brand: "トマト ", product: " トマト") == "トマト")
  }

  @Test func 量の表記は数値と単位を空白でつなぐ() {
    #expect(FoodRow.amountText(1, unit: "個") == "1 個")
    #expect(FoodRow.amountText(1.5, unit: "個") == "1.5 個")
    #expect(FoodRow.amountText(100, unit: "g") == "100 g")
  }
}

/// 追加シートの確認バーに出す累計。
struct AddedEntrySummaryTests {

  @Test func 追加が無ければ合計は0() {
    #expect([AddedEntry]().totalCalories == 0)
  }

  @Test func 追加したぶんを足し上げる() {
    let entries = [
      AddedEntry(name: "ゆで卵", calories: 71),
      AddedEntry(name: "きゅうり", calories: 13),
    ]
    #expect(entries.count == 2)
    #expect(entries.totalCalories == 84)
  }
}
