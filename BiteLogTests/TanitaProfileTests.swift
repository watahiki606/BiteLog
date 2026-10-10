import Foundation
import Testing

@testable import BiteLog

/// 体組成計の個人データ。
///
/// バイト列は仕様どおりに組み立てた架空のもので、実在の人の個人データは使っていない。
struct TanitaProfileTests {

  /// 呼び名「ab」、1990-04-01 生まれ、170.0cm、女性、標準、着衣 0.5kg、地域 02。
  /// 意味の分かっていない `6A3B` `6A15` も、体組成計が返すとおりに混ぜておく
  private static let stored: [TanitaField] = [
    TanitaField(tag: 0x6A32, value: Data([0x25, 0x00])),
    TanitaField(tag: 0x6A33, value: Data([0x00, 0x00, 0x10])),
    TanitaField(tag: 0x6A3D, value: Data([0x61, 0x62, 0x00, 0x00, 0x00])),
    TanitaField(tag: 0x6A3C, value: Data([0x80, 0xC3])),
    TanitaField(tag: 0x6A37, value: Data([0x01])),
    TanitaField(tag: 0x6A38, value: Data([0x00])),
    TanitaField(tag: 0x6A3E, value: Data([0x06, 0xA4])),
    TanitaField(tag: 0x6A3B, value: Data([0x00])),
    TanitaField(tag: 0x604F, value: Data([0x00, 0x32])),
    TanitaField(tag: 0x6A13, value: Data([0x02])),
    TanitaField(tag: 0x6A15, value: Data([0x00, 0x00, 0x00, 0x01])),
  ]

  @Test func 読んだ個人データから項目を取り出す() throws {
    let profile = try TanitaProfile(fields: Self.stored)

    #expect(profile.nickname == "ab")
    #expect(profile.birthDate == DateComponents(year: 1990, month: 4, day: 1))
    #expect(profile.heightCm == 170.0)
    #expect(profile.sex == .female)
    #expect(profile.bodyType == .standard)
    #expect(profile.clothingWeightKg == 0.5)
    #expect(profile.region == 0x02)
  }

  @Test func 項目が欠けていれば読めない() {
    let withoutHeight = Self.stored.filter { $0.tag != 0x6A3E }

    #expect(throws: TanitaProfile.DecodeError.missing(tag: 0x6A3E)) {
      try TanitaProfile(fields: withoutHeight)
    }
  }

  @Test func 書き戻すときは変えた項目だけ差し替え並びと知らないタグはそのまま残す() throws {
    var profile = try TanitaProfile(fields: Self.stored)
    profile.heightCm = 170.5
    profile.sex = .male

    let written = profile.applied(to: Self.stored)

    #expect(written.map(\.tag) == Self.stored.map(\.tag))
    #expect(written.first { $0.tag == 0x6A3E }?.value == Data([0x06, 0xA9]))
    #expect(written.first { $0.tag == 0x6A37 }?.value == Data([0x00]))
    let untouched = written.filter { ![0x6A3E, 0x6A37].contains($0.tag) }
    #expect(untouched == Self.stored.filter { ![0x6A3E, 0x6A37].contains($0.tag) })
  }

  @Test func どの項目も書いて読み直すと同じ値に戻る() throws {
    let profile = TanitaProfile(
      nickname: "xyz",
      birthDate: DateComponents(year: 2001, month: 12, day: 31),
      heightCm: 155.5,
      sex: .male,
      bodyType: .athlete,
      clothingWeightKg: 1.2,
      region: 0x00
    )

    let reread = try TanitaProfile(fields: profile.applied(to: Self.stored))

    #expect(reread == profile)
  }

  @Test func 呼び名は5バイトに収めて余りを0で埋める() throws {
    var profile = try TanitaProfile(fields: Self.stored)
    profile.nickname = "z"

    let written = profile.applied(to: Self.stored)

    #expect(written.first { $0.tag == 0x6A3D }?.value == Data([0x7A, 0x00, 0x00, 0x00, 0x00]))
  }
}
