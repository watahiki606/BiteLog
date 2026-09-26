import Foundation
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
      AddedEntry(logItemID: UUID(), name: "ゆで卵", calories: 71),
      AddedEntry(logItemID: UUID(), name: "きゅうり", calories: 13),
    ]
    #expect(entries.count == 2)
    #expect(entries.totalCalories == 84)
  }

  @Test func 取り消すと合計から引かれる() {
    var entries = [
      AddedEntry(logItemID: UUID(), name: "ゆで卵", calories: 71),
      AddedEntry(logItemID: UUID(), name: "きゅうり", calories: 13),
    ]
    entries.removeLast()
    #expect(entries.totalCalories == 71)
  }
}

/// AI が付けた名前から、既存の食品を探すための語を取り出す。
struct AISearchTermTests {

  @Test func 空白の手前までを使う() {
    #expect(AIFoodAnalyzer.searchTerm(for: "おにぎり 国産もち麦入り枝豆と塩昆布") == "おにぎり")
  }

  @Test func 全角括弧の手前までを使う() {
    #expect(AIFoodAnalyzer.searchTerm(for: "アロエヨーグルト（プレーン、約110g カップ）") == "アロエヨーグルト")
  }

  @Test func 連結記号の手前までを使う() {
    #expect(AIFoodAnalyzer.searchTerm(for: "冷やし中華（市販の容器）＋から揚げ数個") == "冷やし中華")
  }

  @Test func 区切りが無ければそのまま使う() {
    #expect(AIFoodAnalyzer.searchTerm(for: "トマトジュース") == "トマトジュース")
  }

  @Test func 先頭の空白は落とす() {
    #expect(AIFoodAnalyzer.searchTerm(for: "  和定食（丼＋小鉢）") == "和定食")
  }
}

/// 記録の時刻。対象の日に、いま記録している時刻を合わせる。
struct LogTimestampTests {

  private func make(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int) -> Date {
    Calendar.current.date(
      from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm, second: 0))!
  }

  @Test func 対象の日は変えずに時刻だけ差し替える() {
    let day = make(2026, 9, 1, 0, 0)
    let now = make(2026, 9, 27, 14, 30)
    let result = LogItemDTO.timestamp(for: day, now: now)
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: result)
    #expect(parts.year == 2026)
    #expect(parts.month == 9)
    #expect(parts.day == 1)
    #expect(parts.hour == 14)
    #expect(parts.minute == 30)
  }

  @Test func 画面が持つ時刻は引き継がない() {
    // 日付を前後に動かすと起動時の時刻を引きずる。それを持ち込ませない。
    let day = make(2026, 9, 1, 23, 59)
    let now = make(2026, 9, 27, 8, 5)
    let result = LogItemDTO.timestamp(for: day, now: now)
    let parts = Calendar.current.dateComponents([.day, .hour, .minute], from: result)
    #expect(parts.day == 1)
    #expect(parts.hour == 8)
    #expect(parts.minute == 5)
  }

  @Test func 続けて記録すると時刻が進む() {
    let day = make(2026, 9, 27, 0, 0)
    let first = LogItemDTO.timestamp(for: day, now: make(2026, 9, 27, 12, 0))
    let second = LogItemDTO.timestamp(for: day, now: make(2026, 9, 27, 12, 1))
    #expect(first < second)
  }
}
