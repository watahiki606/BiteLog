import Foundation

/// 体組成計の個人データ。体脂肪率や体内年齢は、体組成計がこの値を使って計算する。
///
/// 持ち主は BiteLog で、体組成計の枠は写し。書くときは体組成計から読んだフィールドの並びを土台にして、
/// この項目だけ差し替える。意味の分かっていないタグも混ざっているので、一から組み立てずに読んだものを残す。
struct TanitaProfile: Equatable, Codable {
  enum Sex: UInt8, CaseIterable, Codable {
    case male = 0
    case female = 1
  }

  enum BodyType: UInt8, CaseIterable, Codable {
    case standard = 0
    case athlete = 1
  }

  enum DecodeError: Error, Equatable {
    case missing(tag: UInt16)
  }

  /// 呼び名を入れる枠のバイト数
  static let nicknameBytes = 5
  /// 生年月日の起点。タグの値はここからの日数
  private static let birthEpoch = DateComponents(year: 1899, month: 12, day: 31)

  var nickname: String
  /// 年・月・日だけを持つ。時刻もタイムゾーンも持たない暦の日付
  var birthDate: DateComponents
  var heightCm: Double
  var sex: Sex
  var bodyType: BodyType
  var clothingWeightKg: Double
  var region: UInt8

  init(
    nickname: String, birthDate: DateComponents, heightCm: Double, sex: Sex,
    bodyType: BodyType, clothingWeightKg: Double, region: UInt8
  ) {
    self.nickname = nickname
    self.birthDate = Self.day(birthDate)
    self.heightCm = heightCm
    self.sex = sex
    self.bodyType = bodyType
    self.clothingWeightKg = clothingWeightKg
    self.region = region
  }

  init(fields: [TanitaField]) throws {
    func value(_ tag: UInt16) throws -> Data {
      guard let field = fields.first(where: { $0.tag == tag }) else {
        throw DecodeError.missing(tag: tag)
      }
      return field.value
    }

    let name = try value(TanitaTag.nickname).prefix { $0 != 0 }
    nickname = String(decoding: name, as: UTF8.self)
    birthDate = Self.date(daysSinceEpoch: Self.integer(try value(TanitaTag.birthDate)))
    heightCm = Double(Self.integer(try value(TanitaTag.height))) / 10
    sex = Sex(rawValue: try value(TanitaTag.sex).first ?? 0) ?? .male
    bodyType = BodyType(rawValue: try value(TanitaTag.bodyType).first ?? 0) ?? .standard
    clothingWeightKg = Double(Self.integer(try value(TanitaTag.clothingWeight))) / 100
    region = try value(TanitaTag.region).first ?? 0
  }

  /// 読んだフィールドの並びのまま、この個人データの項目だけ値を差し替える
  func applied(to stored: [TanitaField]) -> [TanitaField] {
    stored.map { field in
      guard let value = encodedValue(for: field.tag) else { return field }
      return TanitaField(tag: field.tag, value: value)
    }
  }

  private func encodedValue(for tag: UInt16) -> Data? {
    switch tag {
    case TanitaTag.nickname:
      var bytes = Data(nickname.utf8.prefix(Self.nicknameBytes))
      bytes.append(Data(repeating: 0, count: Self.nicknameBytes - bytes.count))
      return bytes
    case TanitaTag.birthDate:
      return Self.twoBytes(Self.daysSinceEpoch(birthDate))
    case TanitaTag.height:
      return Self.twoBytes(Int((heightCm * 10).rounded()))
    case TanitaTag.sex:
      return Data([sex.rawValue])
    case TanitaTag.bodyType:
      return Data([bodyType.rawValue])
    case TanitaTag.clothingWeight:
      return Self.twoBytes(Int((clothingWeightKg * 100).rounded()))
    case TanitaTag.region:
      return Data([region])
    default:
      return nil
    }
  }

  /// 暦の計算は UTC で行う。生年月日は日付だけで、どの時間帯で見ても同じ日になるように
  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private static func date(daysSinceEpoch days: Int) -> DateComponents {
    guard let epoch = calendar.date(from: birthEpoch),
      let date = calendar.date(byAdding: .day, value: days, to: epoch)
    else { return DateComponents() }
    return day(calendar.dateComponents([.year, .month, .day], from: date))
  }

  /// 年・月・日だけを残す。暦やタイムゾーンが混ざると、同じ日でも等しくならない
  private static func day(_ components: DateComponents) -> DateComponents {
    DateComponents(year: components.year, month: components.month, day: components.day)
  }

  private static func daysSinceEpoch(_ components: DateComponents) -> Int {
    let day = DateComponents(year: components.year, month: components.month, day: components.day)
    guard let epoch = calendar.date(from: birthEpoch), let date = calendar.date(from: day) else {
      return 0
    }
    return calendar.dateComponents([.day], from: epoch, to: date).day ?? 0
  }

  private static func integer(_ value: Data) -> Int {
    value.reduce(0) { $0 << 8 | Int($1) }
  }

  private static func twoBytes(_ value: Int) -> Data {
    Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
  }
}
