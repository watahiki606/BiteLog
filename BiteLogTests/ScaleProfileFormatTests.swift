import Foundation
import Testing

@testable import BiteLog

/// 個人データの編集画面で選べる値と、書く前に並べる変更。値は架空のもの
struct ScaleProfileFormatTests {

  private static let profile = TanitaProfile(
    nickname: "ab",
    birthDate: DateComponents(year: 1990, month: 4, day: 1),
    heightCm: 170.0,
    sex: .male,
    bodyType: .standard,
    clothingWeightKg: 0.0,
    region: 2
  )

  @Test func 身長は取扱説明書の範囲を0点5刻みで選べる() {
    let options = ScaleProfileFormat.heightOptions(including: 170.0)

    #expect(options.first == 90.0)
    #expect(options.last == 220.0)
    #expect(options.contains(170.5))
    #expect(options.count == 261)
  }

  @Test func 体組成計の値が刻みから外れていても選べる() {
    let options = ScaleProfileFormat.heightOptions(including: 170.3)

    #expect(options.contains(170.3))
    #expect(options == options.sorted())
  }

  @Test func 着衣の重さは公式アプリと同じく0から2kgを0点1刻みで選べる() {
    let options = ScaleProfileFormat.clothingOptions(including: 0.0)

    #expect(options.first == 0.0)
    #expect(options.last == 2.0)
    #expect(options.count == 21)
    // 体組成計は ÷100 で持つ。0.5kg は 50
    #expect(options.contains(50.0 / 100))
  }

  @Test func ニックネームは英数字だけを枠の長さまで残す() {
    #expect(ScaleProfileFormat.nickname("a b-c1あ23") == "abc12")
  }

  @Test func 変えていなければ確認に並べるものは無い() {
    #expect(ScaleProfileChange.between(Self.profile, Self.profile).isEmpty)
  }

  @Test func 変えた項目だけを確認に並べる() {
    var changed = Self.profile
    changed.heightCm = 171.5
    changed.bodyType = .athlete

    let changes = ScaleProfileChange.between(Self.profile, changed)

    #expect(changes.count == 2)
    #expect(changes.first?.summary.contains("170.0 cm → 171.5 cm") == true)
  }
}
