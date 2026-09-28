import Foundation

/// タニタ体組成計の独自プロトコル。
///
/// 体重計は Bluetooth SIG の Weight Scale Service / Body Composition Service を実装しておらず、
/// 独自サービスの書き込み用キャラクタリスティックにコマンドを書き、notify で応答を受け取る。
/// 1回の書き込みは20バイトまでなので、メッセージはフレームに分割して送る。
///
/// 体組成の各値は体重計が計算済みで送ってくるため、インピーダンスからの換算は不要。
enum TanitaProtocolError: Error, Equatable {
  case tooShort
  case lengthMismatch(declared: Int, actual: Int)
  case checksumMismatch(expected: UInt8, actual: UInt8)
  case unknownTag(UInt16)
  case truncatedValue(tag: UInt16)
}

// MARK: - メッセージ

/// やり取りの1単位。
///
/// `[全長-2: 2バイトBE][コマンド: 2バイト][データ][チェックサム: 1バイト]`
struct TanitaMessage: Equatable {
  let command: UInt16
  let payload: Data

  /// 全長フィールド2バイト + コマンド2バイト + チェックサム1バイト
  private static let overhead = 5

  init(command: UInt16, payload: Data) {
    self.command = command
    self.payload = payload
  }

  init(decoding bytes: Data) throws {
    let raw = [UInt8](bytes)
    guard raw.count >= Self.overhead else { throw TanitaProtocolError.tooShort }

    let declared = (Int(raw[0]) << 8 | Int(raw[1])) + 2
    guard raw.count == declared else {
      throw TanitaProtocolError.lengthMismatch(declared: declared, actual: raw.count)
    }

    let expected = Self.checksum(Data(raw.dropLast()))
    guard let actual = raw.last, actual == expected else {
      throw TanitaProtocolError.checksumMismatch(expected: expected, actual: raw.last ?? 0)
    }

    self.command = UInt16(raw[2]) << 8 | UInt16(raw[3])
    self.payload = Data(raw[4..<(raw.count - 1)])
  }

  var encoded: Data {
    var bytes = Data()
    let total = Self.overhead + payload.count
    bytes.append(UInt8((total - 2) >> 8))
    bytes.append(UInt8((total - 2) & 0xFF))
    bytes.append(UInt8(command >> 8))
    bytes.append(UInt8(command & 0xFF))
    bytes.append(payload)
    bytes.append(Self.checksum(bytes))
    return bytes
  }

  /// 応答のコマンドは要求のコマンドに 0x80 を立てたもの。
  var isResponse: Bool { command & 0x8000 != 0 }

  /// チェックサムは直前までの全バイトの総和のビット反転。
  static func checksum(_ bytes: Data) -> UInt8 {
    ~bytes.reduce(UInt8(0)) { $0 &+ $1 }
  }
}

/// 測定1件を取り出すまでに使うコマンド。
enum TanitaCommand: UInt16 {
  /// アプリ識別子を送る。接続のたびに最初に必要
  case identify = 0x0003
  /// 体重計の時計を合わせる。測定日時はこの時計で記録される
  case setClock = 0x0010
  /// 機種名やシリアルを取る
  case deviceInfo = 0x0020
  /// 個人データを読む
  case readProfile = 0x1000
  /// 個人データを書く
  case writeProfile = 0x1002
  /// 測定待機に入る。応答は測定が終わってから返る
  case startMeasurement = 0x2010
  /// 未送信データの件数を取る
  case measurementCount = 0x3000
  /// 測定データを取る
  case readMeasurement = 0x3010
  /// 通信を終える
  case finish = 0x0001

  var responseCommand: UInt16 { rawValue | 0x8000 }
}

// MARK: - TLV

/// メッセージのデータ部を構成するタグと値の組。
///
/// 値の長さはタグごとに固定で、長さフィールドは無い。テーブルで引く。
struct TanitaField: Equatable {
  let tag: UInt16
  let value: Data

  static func parse(_ bytes: Data) throws -> [TanitaField] {
    let raw = [UInt8](bytes)
    var fields: [TanitaField] = []
    var index = 0

    while index + 2 <= raw.count {
      let tag = UInt16(raw[index]) << 8 | UInt16(raw[index + 1])
      // 知らないタグは値の長さが分からず、以降の切り出しが全部ずれる。
      // 黙って読み飛ばすと機種差や仕様追加に気づけないので落とす。
      guard let length = TanitaTag.valueLength[tag] else {
        throw TanitaProtocolError.unknownTag(tag)
      }
      guard index + 2 + length <= raw.count else {
        throw TanitaProtocolError.truncatedValue(tag: tag)
      }
      fields.append(TanitaField(tag: tag, value: Data(raw[(index + 2)..<(index + 2 + length)])))
      index += 2 + length
    }

    return fields
  }
}

enum TanitaTag {
  static let weight: UInt16 = 0x6021
  static let bodyFatPercent: UInt16 = 0x6022
  static let muscleMass: UInt16 = 0x6023
  static let muscleScore: UInt16 = 0x6024
  static let visceralFatLevel: UInt16 = 0x6025
  static let basalMetabolism: UInt16 = 0x6027
  static let metabolicAge: UInt16 = 0x6028
  static let boneMass: UInt16 = 0x6029
  static let bodyWaterPercent: UInt16 = 0x602B
  static let bmi: UInt16 = 0x6056
  static let model: UInt16 = 0x6A16
  static let date: UInt16 = 0x6A32
  static let time: UInt16 = 0x6A33
  static let height: UInt16 = 0x6A3E

  /// タグごとの値の長さ。RD-902 の通信を全メッセージ解けるまで突き合わせて確定させた。
  /// 意味が分かっていないタグも、長さが分からないと後続が読めないので載せている。
  static let valueLength: [UInt16: Int] = [
    0x6021: 2, 0x6022: 2, 0x6023: 2, 0x6024: 1, 0x6025: 2, 0x6027: 2,
    0x6028: 1, 0x6029: 2, 0x602B: 2, 0x602F: 2, 0x604F: 2, 0x6056: 2,
    0x605A: 1, 0x605B: 1, 0x6070: 1, 0x6076: 1, 0x6077: 1, 0x607D: 1,
    0x607E: 1, 0x614B: 2, 0x614C: 2, 0x6151: 2, 0x6152: 2, 0x6A11: 4,
    0x6A12: 2, 0x6A13: 1, 0x6A14: 1, 0x6A15: 4, 0x6A16: 8, 0x6A29: 6,
    0x6A2E: 4, 0x6A2F: 1, 0x6A30: 1, 0x6A32: 2, 0x6A33: 3, 0x6A37: 1,
    0x6A38: 1, 0x6A3B: 1, 0x6A3C: 2, 0x6A3D: 5, 0x6A3E: 2, 0x6F21: 2,
    0x6F22: 2, 0x7E21: 1, 0x7E22: 11, 0x7E2F: 2,
  ]
}

// MARK: - フレーミング

/// メッセージを20バイトのフレームに分割して送り、受け取った断片を組み直す。
///
/// `00 <offset> <seq> <このフレームのペイロード長> <ペイロード 最大16バイト>`
enum TanitaFraming {
  static let frameSize = 20
  static let payloadPerFrame = 16

  static func frames(for message: Data, sequence: UInt8) -> [Data] {
    let raw = [UInt8](message)
    var frames: [Data] = []
    var offset = 0

    while offset < raw.count {
      let length = min(payloadPerFrame, raw.count - offset)
      var frame = Data([0x00, UInt8(offset & 0xFF), sequence, UInt8(length)])
      frame.append(Data(raw[offset..<(offset + length)]))
      frames.append(frame)
      offset += length
    }

    return frames
  }

  /// notify で届いた断片を溜めて、メッセージが揃ったところで返す。
  struct Assembler {
    private var buffer = Data()

    /// - Returns: メッセージが完成したらそのバイト列。まだ途中なら nil
    mutating func append(_ frame: Data) -> Data? {
      let raw = [UInt8](frame)
      guard raw.count >= 4 else { return nil }

      let offset = Int(raw[1])
      let length = Int(raw[3])
      guard raw.count >= 4 + length else { return nil }
      let chunk = Data(raw[4..<(4 + length)])

      // offset 0 は新しいメッセージの先頭。途中で別のメッセージが始まったら
      // それまでの断片は完成しないので捨てる
      if offset == 0 {
        buffer = chunk
      } else {
        buffer.append(chunk)
      }

      guard buffer.count >= 2 else { return nil }
      let declared = (Int(buffer[buffer.startIndex]) << 8 | Int(buffer[buffer.startIndex + 1])) + 2
      guard buffer.count >= declared else { return nil }

      let message = buffer.prefix(declared)
      buffer = Data()
      return Data(message)
    }
  }
}

// MARK: - 測定データ

/// 測定1件。体重計が計算済みの値を送ってくる。
struct TanitaBodyMeasurement: Equatable {
  var measuredAt: Date?
  var weightKg: Double?
  var bodyFatPercent: Double?
  var muscleMassKg: Double?
  var muscleScore: Int?
  var visceralFatLevel: Double?
  var basalMetabolismKcal: Int?
  var metabolicAge: Int?
  var boneMassKg: Double?
  var bodyWaterPercent: Double?
  var bmi: Double?
  var heightCm: Double?

  /// 日付の起点。タグ 0x6A32 はここからの日数
  private static let epoch = DateComponents(year: 2000, month: 1, day: 1)

  /// `0x3010` の応答のデータ部から組み立てる。先頭2バイトはステータスと連番。
  init(measurementPayload: Data, timeZone: TimeZone) throws {
    guard measurementPayload.count >= 2 else { throw TanitaProtocolError.tooShort }

    var days: Int?
    var halfSeconds: Int?

    for field in try TanitaField.parse(measurementPayload.dropFirst(2)) {
      switch field.tag {
      case TanitaTag.weight: weightKg = Self.scaled(field.value, by: 100)
      case TanitaTag.bodyFatPercent: bodyFatPercent = Self.scaled(field.value, by: 10)
      case TanitaTag.muscleMass: muscleMassKg = Self.scaled(field.value, by: 100)
      case TanitaTag.muscleScore: muscleScore = Self.signed(field.value)
      case TanitaTag.visceralFatLevel: visceralFatLevel = Self.scaled(field.value, by: 10)
      case TanitaTag.basalMetabolism: basalMetabolismKcal = Self.integer(field.value)
      case TanitaTag.metabolicAge: metabolicAge = Self.integer(field.value)
      case TanitaTag.boneMass: boneMassKg = Self.scaled(field.value, by: 100)
      case TanitaTag.bodyWaterPercent: bodyWaterPercent = Self.scaled(field.value, by: 10)
      case TanitaTag.bmi: bmi = Self.scaled(field.value, by: 10)
      case TanitaTag.height: heightCm = Self.scaled(field.value, by: 10)
      case TanitaTag.date: days = Self.integer(field.value)
      case TanitaTag.time: halfSeconds = Self.integer(field.value)
      default: break
      }
    }

    if let days, let halfSeconds {
      measuredAt = Self.date(days: days, halfSeconds: halfSeconds, timeZone: timeZone)
    }
  }

  static func date(days: Int, halfSeconds: Int, timeZone: TimeZone) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    guard let epoch = calendar.date(from: Self.epoch),
      let day = calendar.date(byAdding: .day, value: days, to: epoch)
    else { return nil }
    return day.addingTimeInterval(Double(halfSeconds) / 2)
  }

  private static func integer(_ value: Data) -> Int {
    value.reduce(0) { $0 << 8 | Int($1) }
  }

  private static func scaled(_ value: Data, by divisor: Double) -> Double {
    Double(integer(value)) / divisor
  }

  /// 筋肉スコアは最上位ビットが符号で、下位7ビットが値。
  private static func signed(_ value: Data) -> Int? {
    guard let byte = value.first else { return nil }
    return byte & 0x80 != 0 ? -Int(byte & 0x7F) : Int(byte)
  }
}
