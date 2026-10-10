import SwiftUI

/// 体組成計に書く個人データを入力して、端末に保存する。
///
/// 持ち主は BiteLog で、体組成計の枠は写し。登録のときと測るたびに、ここで保存した値を体組成計へ書く。
/// 体脂肪率や体内年齢は体組成計がこの値で計算するので、登録したあとに直すときは、変わる項目を並べて確かめる。
struct ScaleProfileView: View {
  @Environment(\.dismiss) private var dismiss

  /// 保存済みの値。初めてなら nil
  @State private var stored = TanitaScaleConnection.profile()
  @State private var draft = ScaleProfileDraft(TanitaScaleConnection.profile())
  @State private var isConfirming = false

  private var changes: [ScaleProfileChange] {
    guard let stored, let profile = draft.profile else { return [] }
    return ScaleProfileChange.between(stored, profile)
  }

  private var canSave: Bool {
    guard draft.profile != nil else { return false }
    return stored == nil || !changes.isEmpty
  }

  var body: some View {
    Form {
      ScaleProfileForm(draft: $draft)

      Section {
        Button(NSLocalizedString("Save", comment: "Scale profile save")) {
          // 登録したあとに変えると、次の測定から計算が変わる。黙って変えずに確かめる
          if stored != nil && TanitaScaleConnection.isPaired() {
            isConfirming = true
          } else {
            save()
          }
        }
        .disabled(!canSave)
      } footer: {
        Text(
          NSLocalizedString(
            "Body fat and other results are calculated from these values. They are sent to the scale when you register and each time you measure.",
            comment: "Scale profile help"))
      }
    }
    .navigationTitle(NSLocalizedString("Personal Data", comment: "Scale profile title"))
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      NSLocalizedString(
        "These values will be sent to the scale the next time you measure.",
        comment: "Scale profile confirm"),
      isPresented: $isConfirming,
      titleVisibility: .visible
    ) {
      Button(NSLocalizedString("Save", comment: "Scale profile save")) { save() }
    } message: {
      Text(changes.map(\.summary).joined(separator: "\n"))
    }
  }

  private func save() {
    guard let profile = draft.profile else { return }
    TanitaScaleConnection.setProfile(profile)
    dismiss()
  }
}

/// 入力の途中の個人データ。身長や生年月日は、初めは決まっていない。
///
/// それらしい初期値を置くと、確かめずに保存されて体組成計の計算がずれるので、選ぶまで空にしておく。
/// 体型と着衣は、ほとんどの人が「標準」「0.0kg」のままでよいので初めから入れておく。
struct ScaleProfileDraft: Equatable {
  var nickname = ""
  var birthDate: DateComponents?
  var heightCm: Double?
  var sex: TanitaProfile.Sex?
  var bodyType = TanitaProfile.BodyType.standard
  var clothingWeightKg = 0.0
  var region: UInt8?

  init(_ profile: TanitaProfile?) {
    guard let profile else { return }
    nickname = profile.nickname
    birthDate = profile.birthDate
    heightCm = profile.heightCm
    sex = profile.sex
    bodyType = profile.bodyType
    clothingWeightKg = profile.clothingWeightKg
    region = profile.region
  }

  /// すべての項目がそろっていれば、体組成計に書ける個人データ
  var profile: TanitaProfile? {
    guard let birthDate, let heightCm, let sex, let region else { return nil }
    return TanitaProfile(
      nickname: nickname, birthDate: birthDate, heightCm: heightCm, sex: sex, bodyType: bodyType,
      clothingWeightKg: clothingWeightKg, region: region)
  }
}

/// 個人データの各項目の入力欄
private struct ScaleProfileForm: View {
  @Binding var draft: ScaleProfileDraft

  var body: some View {
    Section {
      TextField(
        NSLocalizedString("Nickname", comment: "Scale profile field"),
        text: Binding(
          get: { draft.nickname },
          set: { draft.nickname = ScaleProfileFormat.nickname($0) }
        )
      )
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
    } header: {
      Text(NSLocalizedString("Nickname", comment: "Scale profile field"))
    } footer: {
      Text(
        String(
          format: NSLocalizedString(
            "Shown on the scale. Up to %d letters or digits.", comment: "Scale profile nickname help"),
          TanitaProfile.nicknameBytes))
    }

    Section {
      if let birthDate = draft.birthDate {
        DatePicker(
          NSLocalizedString("Date of Birth", comment: "Scale profile field"),
          selection: Binding(
            get: { ScaleProfileFormat.date(birthDate) },
            set: { draft.birthDate = ScaleProfileFormat.components($0) }
          ),
          in: ScaleProfileFormat.birthDateRange,
          displayedComponents: .date
        )
      } else {
        // 日付の選択は今日から始まるので、そのまま出すと生年月日を遠くまで戻すことになる。
        // 押したときに、多くの人の生年月日に近いところから始める
        HStack {
          Text(NSLocalizedString("Date of Birth", comment: "Scale profile field"))
          Spacer()
          Button(NSLocalizedString("Choose", comment: "Scale profile choose")) {
            draft.birthDate = ScaleProfileFormat.birthDatePickerStart
          }
        }
      }

      Picker(
        NSLocalizedString("Height", comment: "Scale profile field"), selection: $draft.heightCm
      ) {
        Text(NSLocalizedString("Not Set", comment: "Scale profile unset")).tag(Double?.none)
        ForEach(ScaleProfileFormat.heightOptions(including: draft.heightCm), id: \.self) {
          Text(ScaleProfileFormat.height($0)).tag(Double?.some($0))
        }
      }

      Picker(NSLocalizedString("Sex", comment: "Scale profile field"), selection: $draft.sex) {
        Text(NSLocalizedString("Not Set", comment: "Scale profile unset"))
          .tag(TanitaProfile.Sex?.none)
        ForEach(TanitaProfile.Sex.allCases, id: \.self) {
          Text(ScaleProfileFormat.sex($0)).tag(TanitaProfile.Sex?.some($0))
        }
      }

      Picker(
        NSLocalizedString("Body Type", comment: "Scale profile field"),
        selection: $draft.bodyType
      ) {
        ForEach(TanitaProfile.BodyType.allCases, id: \.self) {
          Text(ScaleProfileFormat.bodyType($0)).tag($0)
        }
      }
    } footer: {
      Text(
        NSLocalizedString(
          "Choose Athlete only if you are 18 or older and train 12 hours or more a week.",
          comment: "Scale profile athlete help"))
    }

    Section {
      Picker(
        NSLocalizedString("Clothes and Phone", comment: "Scale profile field"),
        selection: $draft.clothingWeightKg
      ) {
        ForEach(ScaleProfileFormat.clothingOptions(including: draft.clothingWeightKg), id: \.self) {
          Text(ScaleProfileFormat.clothing($0)).tag($0)
        }
      }

      Picker(NSLocalizedString("Region", comment: "Scale profile field"), selection: $draft.region) {
        Text(NSLocalizedString("Not Set", comment: "Scale profile unset")).tag(UInt8?.none)
        ForEach(ScaleProfileFormat.regionOptions(including: draft.region), id: \.self) {
          Text(ScaleProfileFormat.region($0)).tag(UInt8?.some($0))
        }
      }
    } footer: {
      Text(
        NSLocalizedString(
          "The weight of clothes and phone is subtracted from your weight. The region corrects for gravity.",
          comment: "Scale profile clothing help"))
    }
  }
}

/// 確認のときに並べる変更1つ
struct ScaleProfileChange: Equatable {
  let summary: String

  static func between(_ before: TanitaProfile, _ after: TanitaProfile) -> [ScaleProfileChange] {
    typealias F = ScaleProfileFormat
    var changes: [ScaleProfileChange] = []
    func add(_ label: String, _ from: String, _ to: String) {
      guard from != to else { return }
      changes.append(ScaleProfileChange(summary: "\(label): \(from) → \(to)"))
    }
    add(NSLocalizedString("Nickname", comment: "Scale profile field"), before.nickname, after.nickname)
    add(
      NSLocalizedString("Date of Birth", comment: "Scale profile field"),
      F.birthDate(before.birthDate), F.birthDate(after.birthDate))
    add(
      NSLocalizedString("Height", comment: "Scale profile field"),
      F.height(before.heightCm), F.height(after.heightCm))
    add(NSLocalizedString("Sex", comment: "Scale profile field"), F.sex(before.sex), F.sex(after.sex))
    add(
      NSLocalizedString("Body Type", comment: "Scale profile field"),
      F.bodyType(before.bodyType), F.bodyType(after.bodyType))
    add(
      NSLocalizedString("Clothes and Phone", comment: "Scale profile field"),
      F.clothing(before.clothingWeightKg), F.clothing(after.clothingWeightKg))
    add(
      NSLocalizedString("Region", comment: "Scale profile field"),
      F.region(before.region), F.region(after.region))
    return changes
  }
}

/// 個人データの値の範囲と表記。範囲は RD-902 の取扱説明書の仕様による
enum ScaleProfileFormat {
  /// 身長は 90.0〜220.0cm を 0.5cm 刻みで選ぶ
  static let heightRange: ClosedRange<Double> = 90.0...220.0
  static let heightStep = 0.5
  /// 着衣やスマホの重さは、公式アプリと同じく 0.0〜2.0kg を 0.1kg 刻みで選ぶ
  static let clothingRange: ClosedRange<Double> = 0.0...2.0
  static let clothingStep = 0.1
  /// 地域の番号と名前。取扱説明書の5区分の表の順に番号が付いている。
  /// 公式アプリは都道府県から選ばせるが、体組成計に入るのは区分の番号だけなので、区分で選ぶ
  static let regions: [(code: UInt8, name: String)] = [
    (0, NSLocalizedString("Hokkaido", comment: "Scale region")),
    (1, NSLocalizedString("Tohoku", comment: "Scale region")),
    (2, NSLocalizedString("Kanto, Chubu, Kinki, Chugoku, Shikoku", comment: "Scale region")),
    (3, NSLocalizedString("Kyushu", comment: "Scale region")),
    (4, NSLocalizedString("Okinawa", comment: "Scale region")),
  ]

  /// 生年月日を選び始める日。30年前の1月1日
  static var birthDatePickerStart: DateComponents {
    let year = Calendar.current.component(.year, from: Date()) - 30
    return DateComponents(year: year, month: 1, day: 1)
  }

  /// 生年月日は 1900-01-01 から今日まで
  static var birthDateRange: ClosedRange<Date> {
    date(DateComponents(year: 1900, month: 1, day: 1))...Date()
  }

  static func heightOptions(including current: Double?) -> [Double] {
    options(heightRange, step: heightStep, including: current)
  }

  static func clothingOptions(including current: Double) -> [Double] {
    options(clothingRange, step: clothingStep, including: current)
  }

  /// 体組成計に入っている値が刻みから外れていても選べるように、いまの値を混ぜる
  private static func options(_ range: ClosedRange<Double>, step: Double, including current: Double?)
    -> [Double]
  {
    let count = Int(((range.upperBound - range.lowerBound) / step).rounded())
    var values = (0...count).map { ((range.lowerBound + Double($0) * step) * 10).rounded() / 10 }
    if let current, !values.contains(current) {
      values.append(current)
      values.sort()
    }
    return values
  }

  static func regionOptions(including current: UInt8?) -> [UInt8] {
    let codes = regions.map(\.code)
    guard let current, !codes.contains(current) else { return codes }
    return codes + [current]
  }

  /// 英数字だけを、枠に収まる長さまで残す
  static func nickname(_ text: String) -> String {
    String(text.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(TanitaProfile.nicknameBytes))
  }

  /// 暦の日付を、いまの暦の正午に置く。日付だけを扱うので、時差で日がずれないようにする
  static func date(_ components: DateComponents) -> Date {
    var noon = components
    noon.hour = 12
    return Calendar.current.date(from: noon) ?? Date()
  }

  static func components(_ date: Date) -> DateComponents {
    let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return DateComponents(year: day.year, month: day.month, day: day.day)
  }

  static func birthDate(_ components: DateComponents) -> String {
    date(components).formatted(date: .long, time: .omitted)
  }

  static func height(_ cm: Double) -> String {
    String(format: "%.1f cm", cm)
  }

  static func clothing(_ kg: Double) -> String {
    String(format: "%.1f kg", kg)
  }

  static func sex(_ sex: TanitaProfile.Sex) -> String {
    switch sex {
    case .male: return NSLocalizedString("Male", comment: "Scale profile sex")
    case .female: return NSLocalizedString("Female", comment: "Scale profile sex")
    }
  }

  static func bodyType(_ type: TanitaProfile.BodyType) -> String {
    switch type {
    case .standard: return NSLocalizedString("Standard", comment: "Scale profile body type")
    case .athlete: return NSLocalizedString("Athlete", comment: "Scale profile body type")
    }
  }

  static func region(_ code: UInt8) -> String {
    regions.first { $0.code == code }?.name
      ?? String(format: NSLocalizedString("Region %d", comment: "Scale region unknown"), code)
  }
}
