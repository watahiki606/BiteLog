import Foundation
import Testing

@testable import BiteLog

/// 体組成計の独自プロトコルの仕様。
///
/// 入力のバイト列は仕様どおりに組み立てた架空の値で、実機の測定記録は使っていない。
/// 実機のトレースとの突き合わせは手元で済ませてある。
struct TanitaProtocolTests {

  // MARK: - メッセージ

  @Test func チェックサムは直前までの総和のビット反転() {
    // 00 04 00 20 00 の総和は 0x24、反転して 0xdb
    #expect(TanitaMessage.checksum(Data([0x00, 0x04, 0x00, 0x20, 0x00])) == 0xDB)
    #expect(TanitaMessage.checksum(Data([0x00, 0x04, 0x10, 0x00, 0x00])) == 0xEB)
  }

  @Test func メッセージに全長とチェックサムが付く() {
    let message = TanitaMessage(command: 0x0020, payload: Data([0x00]))

    // [全長-2: 2バイトBE][コマンド: 2バイト][データ][チェックサム]
    #expect(message.encoded == Data([0x00, 0x04, 0x00, 0x20, 0x00, 0xDB]))
  }

  @Test func 組み立てたメッセージは読み直せる() throws {
    let original = TanitaMessage(command: 0x3010, payload: Data([0x01, 0x02, 0x03]))

    let decoded = try TanitaMessage(decoding: original.encoded)

    #expect(decoded == original)
  }

  @Test func 壊れたチェックサムを弾く() {
    var broken = TanitaMessage(command: 0x0020, payload: Data([0x00])).encoded
    broken[broken.count - 1] = 0x00

    #expect(throws: TanitaProtocolError.checksumMismatch(expected: 0xDB, actual: 0x00)) {
      try TanitaMessage(decoding: broken)
    }
  }

  @Test func 宣言された長さと実際の長さが合わなければ弾く() {
    // 全長フィールドは 0x0004 なので6バイトあるべきところを5バイトしか渡さない
    let truncated = Data([0x00, 0x04, 0x00, 0x20, 0x00])

    #expect(throws: TanitaProtocolError.lengthMismatch(declared: 6, actual: 5)) {
      try TanitaMessage(decoding: truncated)
    }
  }

  @Test func 短すぎるメッセージを弾く() {
    #expect(throws: TanitaProtocolError.tooShort) {
      try TanitaMessage(decoding: Data([0x00, 0x04]))
    }
  }

  @Test func 応答コマンドは要求コマンドに0x80を立てたもの() {
    #expect(TanitaMessage(command: 0x0003, payload: Data()).isResponse == false)
    #expect(TanitaMessage(command: 0x8003, payload: Data()).isResponse)
    #expect(TanitaCommand.deviceInfo.responseCommand == 0x8020)
    #expect(TanitaCommand.readMeasurement.responseCommand == 0xB010)
  }

  // MARK: - TLV

  @Test func タグごとの固定長で値を切り出す() throws {
    // 0x6028 体内年齢は1バイト、0x6021 体重は2バイト
    let bytes = Data([0x60, 0x28, 0x1E, 0x60, 0x21, 0x17, 0x70])

    let fields = try TanitaField.parse(bytes)

    #expect(fields.count == 2)
    #expect(fields[0] == TanitaField(tag: 0x6028, value: Data([0x1E])))
    #expect(fields[1] == TanitaField(tag: 0x6021, value: Data([0x17, 0x70])))
  }

  @Test func 未知のタグはエラーにする() {
    // 知らないタグは値の長さが分からず、以降の切り出しが全部ずれる。
    // 黙って読み飛ばすと機種差に気づけないので落とす。
    let bytes = Data([0x60, 0x01, 0x00])

    #expect(throws: TanitaProtocolError.unknownTag(0x6001)) {
      try TanitaField.parse(bytes)
    }
  }

  @Test func 値が途中で切れていたらエラーにする() {
    // 0x6021 は2バイト必要なのに1バイトしかない
    let bytes = Data([0x60, 0x21, 0x17])

    #expect(throws: TanitaProtocolError.truncatedValue(tag: 0x6021)) {
      try TanitaField.parse(bytes)
    }
  }

  // MARK: - フレーミング

  @Test func メッセージを20バイトのフレームに分割する() {
    let message = Data(repeating: 0xAA, count: 40)

    let frames = TanitaFraming.frames(for: message, sequence: 0x07)

    #expect(frames.count == 3)
    // 00 <offset> <seq> <このフレームのペイロード長>
    #expect(frames[0].prefix(4) == Data([0x00, 0x00, 0x07, 0x10]))
    #expect(frames[1].prefix(4) == Data([0x00, 0x10, 0x07, 0x10]))
    #expect(frames[2].prefix(4) == Data([0x00, 0x20, 0x07, 0x08]))
    #expect(frames[0].count == 20)
    #expect(frames[2].count == 12)
  }

  @Test func フレームを組み直すと元のメッセージに戻る() {
    let message = TanitaMessage(command: 0xB010, payload: Data(repeating: 0x5A, count: 60)).encoded
    var assembler = TanitaFraming.Assembler()

    var assembled: Data?
    for frame in TanitaFraming.frames(for: message, sequence: 0x03) {
      assembled = assembler.append(frame)
    }

    #expect(assembled == message)
  }

  @Test func 最後のフレームが来るまでは組み立てない() {
    let message = TanitaMessage(command: 0xB010, payload: Data(repeating: 0x5A, count: 60)).encoded
    let frames = TanitaFraming.frames(for: message, sequence: 0x03)
    var assembler = TanitaFraming.Assembler()

    #expect(assembler.append(frames[0]) == nil)
    #expect(assembler.append(frames[1]) == nil)
  }

  @Test func 別のメッセージが始まったら組み立て中の断片を捨てる() {
    let first = TanitaMessage(command: 0xB010, payload: Data(repeating: 0x5A, count: 60)).encoded
    let second = TanitaMessage(command: 0x8003, payload: Data([0x00, 0x00])).encoded
    var assembler = TanitaFraming.Assembler()

    _ = assembler.append(TanitaFraming.frames(for: first, sequence: 0x03)[0])
    let assembled = assembler.append(TanitaFraming.frames(for: second, sequence: 0x00)[0])

    #expect(assembled == second)
  }

  // MARK: - 測定データ

  /// 仕様どおりに組み立てた架空の測定データ。
  /// 先頭2バイトはステータスと連番で、その後ろが TLV。
  private static func fakeMeasurementPayload() -> Data {
    var payload = Data([0x00, 0x01])
    payload += Data([0x6A, 0x32, 0x25, 0x19])  // 日付: 2026-01-01 (9497日)
    payload += Data([0x6A, 0x33, 0x00, 0xD2, 0xF0])  // 時刻: 07:30:00 (54000 × 0.5秒)
    payload += Data([0x6A, 0x3E, 0x06, 0xA4])  // 身長 170.0cm
    payload += Data([0x60, 0x21, 0x17, 0x70])  // 体重 60.00kg
    payload += Data([0x60, 0x56, 0x00, 0xDA])  // BMI 21.8
    payload += Data([0x60, 0x22, 0x00, 0xC8])  // 体脂肪率 20.0%
    payload += Data([0x60, 0x23, 0x11, 0x94])  // 筋肉量 45.00kg
    payload += Data([0x60, 0x29, 0x00, 0xFA])  // 推定骨量 2.50kg
    payload += Data([0x60, 0x24, 0x81])  // 筋肉スコア -1
    payload += Data([0x60, 0x27, 0x05, 0x78])  // 基礎代謝量 1400kcal
    payload += Data([0x60, 0x28, 0x1E])  // 体内年齢 30歳
    payload += Data([0x60, 0x25, 0x00, 0x32])  // 内臓脂肪レベル 5.0
    payload += Data([0x60, 0x2B, 0x02, 0x26])  // 体水分率 55.0%
    return payload
  }

  @Test func 測定データから9項目を取り出す() throws {
    let measurement = try TanitaBodyMeasurement(
      measurementPayload: Self.fakeMeasurementPayload(),
      timeZone: TimeZone(identifier: "Asia/Tokyo")!
    )

    #expect(measurement.weightKg == 60.0)
    #expect(measurement.bodyFatPercent == 20.0)
    #expect(measurement.muscleMassKg == 45.0)
    #expect(measurement.muscleScore == -1)
    #expect(measurement.visceralFatLevel == 5.0)
    #expect(measurement.basalMetabolismKcal == 1400)
    #expect(measurement.metabolicAge == 30)
    #expect(measurement.boneMassKg == 2.5)
    #expect(measurement.bodyWaterPercent == 55.0)
  }

  @Test func 測定データからBMIと身長も取れる() throws {
    let measurement = try TanitaBodyMeasurement(
      measurementPayload: Self.fakeMeasurementPayload(),
      timeZone: TimeZone(identifier: "Asia/Tokyo")!
    )

    #expect(measurement.bmi == 21.8)
    #expect(measurement.heightCm == 170.0)
  }

  @Test func 日付は起点からの日数で時刻は半秒刻み() throws {
    let measurement = try TanitaBodyMeasurement(
      measurementPayload: Self.fakeMeasurementPayload(),
      timeZone: TimeZone(identifier: "Asia/Tokyo")!
    )

    var expected = DateComponents()
    expected.year = 2026
    expected.month = 1
    expected.day = 1
    expected.hour = 7
    expected.minute = 30
    expected.second = 0
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

    #expect(measurement.measuredAt == calendar.date(from: expected))
  }

  @Test func 筋肉スコアは最上位ビットが符号() throws {
    // 0x80 が立っていなければ正の値
    var payload = Self.fakeMeasurementPayload()
    payload += Data([0x60, 0x24, 0x03])

    let measurement = try TanitaBodyMeasurement(
      measurementPayload: payload,
      timeZone: TimeZone(identifier: "Asia/Tokyo")!
    )

    #expect(measurement.muscleScore == 3)
  }

  @Test func 項目が無ければnilのままにする() throws {
    // 体重だけを含む最小の測定データ
    let payload = Data([0x00, 0x01, 0x60, 0x21, 0x17, 0x70])

    let measurement = try TanitaBodyMeasurement(
      measurementPayload: payload,
      timeZone: TimeZone(identifier: "Asia/Tokyo")!
    )

    #expect(measurement.weightKg == 60.0)
    #expect(measurement.bodyFatPercent == nil)
    #expect(measurement.measuredAt == nil)
  }
}
