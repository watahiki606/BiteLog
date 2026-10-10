import SwiftUI

/// 体組成計に登録されている個人データを読んで、書き換える。
///
/// 体脂肪率や体内年齢は、体組成計がこの値を使って計算する。間違った値を書くと以降の測定が
/// 全部ずれるので、開いただけでは何もせず、読んでから編集し、書く前に変わる項目を並べて確かめる。
/// 書いたあとは体組成計から読み直した値を出す。
struct ScaleProfileView: View {
  @StateObject private var connection = TanitaScaleConnection()

  /// 体組成計から最後に読んだ値。変更の有無と確認の文面はこれと比べて出す
  @State private var stored: TanitaProfile?
  @State private var draft: TanitaProfile?
  @State private var isConfirming = false
  @State private var didWrite = false

  private var isRunning: Bool {
    switch connection.state {
    case .idle, .finished, .failed: return false
    default: return true
    }
  }

  private var changes: [ScaleProfileChange] {
    guard let stored, let draft else { return [] }
    return ScaleProfileChange.between(stored, draft)
  }

  var body: some View {
    Form {
      Section {
        if isRunning {
          HStack(spacing: 12) {
            ProgressView()
            Text(NSLocalizedString("Connecting to the scale", comment: "Scale profile status"))
              .font(.subheadline)
          }
        } else {
          Button(NSLocalizedString("Read from Scale", comment: "Scale profile button")) {
            didWrite = false
            connection.readProfile()
          }
        }

        if case .failed(let message) = connection.state {
          Text(message)
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        if didWrite, case .finished = connection.state {
          Text(NSLocalizedString("Written to the scale.", comment: "Scale profile result"))
            .font(.footnote)
            .foregroundColor(.secondary)
        }
      } footer: {
        Text(
          NSLocalizedString(
            "Make sure the scale is off before connecting.", comment: "Scale profile help"))
      }

      if let binding = Binding($draft) {
        ScaleProfileForm(profile: binding)
          .disabled(isRunning)

        Section {
          Button(NSLocalizedString("Write to Scale", comment: "Scale profile button")) {
            isConfirming = true
          }
          .disabled(changes.isEmpty || isRunning)
        } footer: {
          Text(
            NSLocalizedString(
              "Body fat and other results are calculated from these values. Wrong values make every later measurement wrong.",
              comment: "Scale profile warning"))
        }
      }
    }
    .navigationTitle(NSLocalizedString("Personal Data", comment: "Scale profile title"))
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      NSLocalizedString("Write these changes to the scale?", comment: "Scale profile confirm"),
      isPresented: $isConfirming,
      titleVisibility: .visible
    ) {
      Button(NSLocalizedString("Write", comment: "Scale profile confirm button")) {
        guard let draft else { return }
        didWrite = true
        connection.writeProfile(draft)
      }
    } message: {
      Text(changes.map(\.summary).joined(separator: "\n"))
    }
    .onAppear {
      connection.onProfile = { profile in
        stored = profile
        draft = profile
      }
    }
    .onDisappear {
      connection.stop()
    }
  }
}

/// 個人データの各項目の入力欄
private struct ScaleProfileForm: View {
  @Binding var profile: TanitaProfile

  var body: some View {
    Section {
      TextField(
        NSLocalizedString("Nickname", comment: "Scale profile field"),
        text: Binding(
          get: { profile.nickname },
          set: { profile.nickname = ScaleProfileFormat.nickname($0) }
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
      DatePicker(
        NSLocalizedString("Date of Birth", comment: "Scale profile field"),
        selection: Binding(
          get: { ScaleProfileFormat.date(profile.birthDate) },
          set: { profile.birthDate = ScaleProfileFormat.components($0) }
        ),
        in: ScaleProfileFormat.birthDateRange,
        displayedComponents: .date
      )

      Picker(
        NSLocalizedString("Height", comment: "Scale profile field"), selection: $profile.heightCm
      ) {
        ForEach(ScaleProfileFormat.heightOptions(including: profile.heightCm), id: \.self) {
          Text(ScaleProfileFormat.height($0)).tag($0)
        }
      }

      Picker(NSLocalizedString("Sex", comment: "Scale profile field"), selection: $profile.sex) {
        ForEach(TanitaProfile.Sex.allCases, id: \.self) {
          Text(ScaleProfileFormat.sex($0)).tag($0)
        }
      }

      Picker(
        NSLocalizedString("Body Type", comment: "Scale profile field"),
        selection: $profile.bodyType
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
        selection: $profile.clothingWeightKg
      ) {
        ForEach(ScaleProfileFormat.clothingOptions(including: profile.clothingWeightKg), id: \.self) {
          Text(ScaleProfileFormat.clothing($0)).tag($0)
        }
      }

      Picker(NSLocalizedString("Region", comment: "Scale profile field"), selection: $profile.region) {
        ForEach(ScaleProfileFormat.regionOptions(including: profile.region), id: \.self) {
          Text(ScaleProfileFormat.region($0)).tag($0)
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

  /// 生年月日は 1900-01-01 から今日まで
  static var birthDateRange: ClosedRange<Date> {
    date(DateComponents(year: 1900, month: 1, day: 1))...Date()
  }

  static func heightOptions(including current: Double) -> [Double] {
    options(heightRange, step: heightStep, including: current)
  }

  static func clothingOptions(including current: Double) -> [Double] {
    options(clothingRange, step: clothingStep, including: current)
  }

  /// 体組成計に入っている値が刻みから外れていても選べるように、いまの値を混ぜる
  private static func options(_ range: ClosedRange<Double>, step: Double, including current: Double)
    -> [Double]
  {
    let count = Int(((range.upperBound - range.lowerBound) / step).rounded())
    var values = (0...count).map { ((range.lowerBound + Double($0) * step) * 10).rounded() / 10 }
    if !values.contains(current) {
      values.append(current)
      values.sort()
    }
    return values
  }

  static func regionOptions(including current: UInt8) -> [UInt8] {
    let codes = regions.map(\.code)
    return codes.contains(current) ? codes : codes + [current]
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
    Calendar.current.dateComponents([.year, .month, .day], from: date)
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
