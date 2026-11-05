import Foundation

/// 自分についての情報。生年月日・身長・性別・体型。
///
/// 体組成計はこの値で体脂肪率などを計算するが、体組成計の持ち物ではない。
/// 体組成計を持っていない人も入れられるよう、プロフィールに置く。
/// 端末の中にだけ持ち、サーバーには送らない。
struct PersonalProfile: Equatable, Codable {
  /// 年・月・日だけを持つ。時刻もタイムゾーンも持たない暦の日付
  var birthDate: DateComponents
  var heightCm: Double
  var sex: TanitaProfile.Sex
  var bodyType: TanitaProfile.BodyType

  static let storageKey = "PersonalProfile"

  /// 保存済みの値。分ける前に体組成計の個人データとして保存していた人は、そこから読む
  static func load(defaults: UserDefaults = .standard) -> PersonalProfile? {
    if let data = defaults.data(forKey: storageKey),
      let profile = try? JSONDecoder().decode(PersonalProfile.self, from: data)
    {
      return profile
    }
    return TanitaScaleConnection.legacyProfile(defaults: defaults).map(\.personal)
  }

  static func save(_ profile: PersonalProfile, defaults: UserDefaults = .standard) {
    guard let data = try? JSONEncoder().encode(profile) else { return }
    defaults.set(data, forKey: storageKey)
  }

  /// 「42歳 · 166.0 cm」。プロフィールの一覧に添える要約
  func summary(today: Date = Date(), calendar: Calendar = .current) -> String {
    var parts: [String] = []
    if let birth = calendar.date(from: birthDate),
      let age = calendar.dateComponents([.year], from: birth, to: today).year
    {
      parts.append(String(format: NSLocalizedString("%d years old", comment: "Age"), age))
    }
    parts.append(ScaleProfileFormat.height(heightCm))
    return parts.joined(separator: " · ")
  }
}

/// 体組成計にだけ関係する設定。体組成計に出す呼び名、差し引く服の重さ、重力を補う地域。
struct ScaleOwnerSettings: Equatable, Codable {
  var nickname: String
  var clothingWeightKg: Double
  var region: UInt8
}

extension TanitaProfile {
  /// 体組成計に書く個人データは、自分についての情報と体組成計の設定を合わせたもの
  init(personal: PersonalProfile, scale: ScaleOwnerSettings) {
    self.init(
      nickname: scale.nickname, birthDate: personal.birthDate, heightCm: personal.heightCm,
      sex: personal.sex, bodyType: personal.bodyType, clothingWeightKg: scale.clothingWeightKg,
      region: scale.region)
  }

  var personal: PersonalProfile {
    PersonalProfile(birthDate: birthDate, heightCm: heightCm, sex: sex, bodyType: bodyType)
  }

  var scaleSettings: ScaleOwnerSettings {
    ScaleOwnerSettings(nickname: nickname, clothingWeightKg: clothingWeightKg, region: region)
  }
}
