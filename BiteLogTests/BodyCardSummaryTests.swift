import Foundation
import Testing

@testable import BiteLog

/// 記録の画面のカードに出すもの。
///
/// 体重計には同じ日に何度も乗る。その前提で、見出しの取り方と日をまたいだ比べ方を確かめる。
/// 数値はすべて架空。実際の記録は使っていない。
struct BodyCardSummaryTests {

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }

  private static func measurement(
    _ day: String, at time: String, weight: Double? = nil, bodyFat: Double? = nil
  ) -> BodyMeasurementDTO {
    BodyMeasurementDTO(
      id: "\(day)T\(time)", sourceDate: day, measuredAt: "\(day)T\(time):00.000Z",
      weightKg: weight, bodyFatPercent: bodyFat, muscleMassKg: nil, muscleScore: nil,
      visceralFatLevel: nil, basalMetabolismKcal: nil, metabolicAge: nil, boneMassKg: nil,
      bodyWaterPercent: nil)
  }

  private static func make(
    _ measurements: [BodyMeasurementDTO], day: String = "2026-02-15"
  ) -> BodyCardSummary.Summary {
    BodyCardSummary.make(measurements, day: day, calendar: calendar)
  }

  // MARK: - その日に乗ったぶん

  @Test func その日に乗ったぶんを早い順に全部持つ() {
    // 1つにまとめない。乗った回数だけ行になる
    let summary = Self.make([
      Self.measurement("2026-02-15", at: "21:00", weight: 61.9),
      Self.measurement("2026-02-15", at: "07:00", weight: 60.9),
      Self.measurement("2026-02-15", at: "12:00", weight: 61.4),
    ])

    #expect(summary.measurements.compactMap(\.weightKg) == [60.9, 61.4, 61.9])
  }

  @Test func 見ている日のぶんだけ持つ() {
    let summary = Self.make([
      Self.measurement("2026-02-14", at: "07:00", weight: 60.0),
      Self.measurement("2026-02-15", at: "07:00", weight: 60.2),
    ])

    #expect(summary.measurements.count == 1)
    #expect(summary.measurements.first?.weightKg == 60.2)
  }

  // MARK: - 比べる相手を探す範囲

  @Test func 取ってきた範囲の測定を早い順に全部持つ() {
    // 1件を開いたときに、比べる相手を探すのに使う
    let summary = Self.make([
      Self.measurement("2026-02-15", at: "07:00", weight: 60.2),
      Self.measurement("2026-02-12", at: "07:00", weight: 60.0),
      Self.measurement("2026-02-14", at: "21:00", weight: 61.5),
    ])

    #expect(summary.recent.compactMap(\.weightKg) == [60.0, 61.5, 60.2])
  }

  // MARK: - 測っていない日

  @Test func その日に測っていなければ前回の値と何日前かを出す() {
    // 空欄を出さない。間が空いていることも伝わる
    let summary = Self.make([
      Self.measurement("2026-02-12", at: "07:00", weight: 61.0, bodyFat: 18.2)
    ])

    #expect(summary.measurements.isEmpty)
    #expect(summary.lastMeasured?.weightKg == 61.0)
    #expect(summary.lastMeasured?.bodyFatPercent == 18.2)
    #expect(summary.lastMeasured?.daysAgo == 3)
  }

  @Test func その日に測っていれば前回の表示は出さない() {
    let summary = Self.make([
      Self.measurement("2026-02-12", at: "07:00", weight: 61.0),
      Self.measurement("2026-02-15", at: "07:00", weight: 60.8),
    ])

    #expect(summary.lastMeasured == nil)
  }

  @Test func 見ている日より後の測定は前回として出さない() {
    // 過去の日を開いたとき、そこから先の測定を「前回」と呼ばない
    let summary = Self.make(
      [Self.measurement("2026-02-20", at: "07:00", weight: 60.0)], day: "2026-02-15")

    #expect(summary.lastMeasured == nil)
  }

  // MARK: - 何も持っていない人

  @Test func 体組成を1件も持っていなければカードを出さない() {
    #expect(!Self.make([]).hasAnyData)
  }

  @Test func 過去に測っていればその日に測っていなくてもカードを出す() {
    #expect(Self.make([Self.measurement("2026-02-12", at: "07:00", weight: 61.0)]).hasAnyData)
  }
}

/// 測定1件を開いたときに並べる9項目。
struct BodyMeasurementDetailTests {

  private static func measurement(
    weight: Double? = nil, bodyFat: Double? = nil, muscle: Double? = nil,
    metabolicAge: Int? = nil
  ) -> BodyMeasurementDTO {
    BodyMeasurementDTO(
      id: UUID().uuidString, sourceDate: "2026-02-15",
      measuredAt: "2026-02-15T07:00:00.000Z", weightKg: weight, bodyFatPercent: bodyFat,
      muscleMassKg: muscle, muscleScore: nil, visceralFatLevel: nil,
      basalMetabolismKcal: nil, metabolicAge: metabolicAge, boneMassKg: nil,
      bodyWaterPercent: nil)
  }

  private static func row(
    _ rows: [BodyMeasurementDetail.Row], _ metric: BodyMetric
  ) -> BodyMeasurementDetail.Row? {
    rows.first { $0.metric == metric }
  }

  @Test func どの項目も同じ並びで返す() {
    let rows = BodyMeasurementDetail.rows(for: Self.measurement(), reference: nil)

    #expect(rows.map(\.metric) == BodyMetric.allCases)
  }

  @Test func 比べる相手との差を出す() {
    let rows = BodyMeasurementDetail.rows(
      for: Self.measurement(weight: 60.2),
      reference: Self.measurement(weight: 61.5))

    #expect(abs(Self.row(rows, .weightKg)!.change! - (-1.3)) < 0.0001)
  }

  @Test func 比べる相手が無ければ差は出さない() {
    let rows = BodyMeasurementDetail.rows(for: Self.measurement(weight: 60.2), reference: nil)

    #expect(Self.row(rows, .weightKg)?.value == 60.2)
    #expect(Self.row(rows, .weightKg)?.change == nil)
  }

  @Test func 比べる相手にその項目が無ければ差は出さない() {
    // 体重は入ったが体脂肪率が取れなかった回がある
    let rows = BodyMeasurementDetail.rows(
      for: Self.measurement(weight: 60.2, bodyFat: 18.0),
      reference: Self.measurement(weight: 61.5))

    #expect(Self.row(rows, .weightKg)?.change != nil)
    #expect(Self.row(rows, .bodyFatPercent)?.change == nil)
  }

  @Test func 取れなかった項目は値も差も出さない() {
    let rows = BodyMeasurementDetail.rows(
      for: Self.measurement(weight: 60.2),
      reference: Self.measurement(weight: 61.5, muscle: 47.0))

    // 0 と書くと測れたことになる
    #expect(Self.row(rows, .muscleMassKg)?.value == nil)
    #expect(Self.row(rows, .muscleMassKg)?.change == nil)
  }

  @Test func 整数で持っている項目も差を出せる() {
    let rows = BodyMeasurementDetail.rows(
      for: Self.measurement(metabolicAge: 34),
      reference: Self.measurement(metabolicAge: 35))

    #expect(Self.row(rows, .metabolicAge)?.change == -1)
  }
}

/// 測定1件を開いたとき、どの回と比べるか。
///
/// 体重は1日のうちに1kg以上動くので、朝の回は朝の回と、夜の回は夜の回と比べる。
struct BodyMeasurementReferenceTests {

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }

  /// 時刻は JST で書く。`measuredAt` は UTC で持つので9時間戻して入れる
  private static func measurement(
    _ day: String, at time: String, weight: Double
  ) -> BodyMeasurementDTO {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    let date = formatter.date(from: "\(day) \(time)")!
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return BodyMeasurementDTO(
      id: "\(day)T\(time)", sourceDate: day, measuredAt: formatter.string(from: date),
      weightKg: weight, bodyFatPercent: nil, muscleMassKg: nil, muscleScore: nil,
      visceralFatLevel: nil, basalMetabolismKcal: nil, metabolicAge: nil, boneMassKg: nil,
      bodyWaterPercent: nil)
  }

  private static func reference(
    for measurement: BodyMeasurementDTO, among recent: [BodyMeasurementDTO]
  ) -> BodyMeasurementDTO? {
    BodyMeasurementDetail.reference(for: measurement, among: recent, calendar: calendar)
  }

  @Test func 朝の回は前日の朝の回と比べる() {
    let morning = Self.measurement("2026-02-14", at: "07:00", weight: 60.0)
    let night = Self.measurement("2026-02-14", at: "22:00", weight: 61.5)
    let today = Self.measurement("2026-02-15", at: "07:10", weight: 60.2)

    #expect(Self.reference(for: today, among: [morning, night, today]) == morning)
  }

  @Test func 夜の回は前日の夜の回と比べる() {
    let morning = Self.measurement("2026-02-14", at: "07:00", weight: 60.0)
    let night = Self.measurement("2026-02-14", at: "22:00", weight: 61.5)
    let today = Self.measurement("2026-02-15", at: "21:30", weight: 61.4)

    #expect(Self.reference(for: today, among: [morning, night, today]) == night)
  }

  @Test func 日付をまたぐ近さも近いと数える() {
    // 23:50 と 0:10 は20分しか離れていない
    let lateNight = Self.measurement("2026-02-14", at: "23:50", weight: 61.0)
    let noon = Self.measurement("2026-02-14", at: "12:00", weight: 61.2)
    let today = Self.measurement("2026-02-15", at: "00:10", weight: 60.9)

    #expect(Self.reference(for: today, among: [noon, lateNight, today]) == lateNight)
  }

  @Test func 同じ日の先の回とは比べない() {
    // 朝と夜の差は食事と水分のぶんで、変化として読めない
    let morning = Self.measurement("2026-02-15", at: "07:00", weight: 60.2)
    let night = Self.measurement("2026-02-15", at: "21:00", weight: 61.4)

    #expect(Self.reference(for: night, among: [morning, night]) == nil)
  }

  @Test func 前日に測っていなければ最後に測った日と比べる() {
    let earlier = Self.measurement("2026-02-12", at: "07:00", weight: 60.5)
    let today = Self.measurement("2026-02-15", at: "07:00", weight: 60.2)

    #expect(Self.reference(for: today, among: [earlier, today]) == earlier)
  }

  @Test func 後の日の測定とは比べない() {
    // 過去の1件を開いたとき、そこから先の測定を前回と呼ばない
    let past = Self.measurement("2026-02-12", at: "07:00", weight: 60.5)
    let later = Self.measurement("2026-02-15", at: "07:00", weight: 60.2)

    #expect(Self.reference(for: past, among: [past, later]) == nil)
  }
}

/// 1件の画面に出す差の書き方と色。
struct BodyMetricChangeTests {

  @Test func 差は符号を付けて項目の桁で書く() {
    #expect(BodyMetric.weightKg.formatChange(-0.43) == "−0.4")
    #expect(BodyMetric.weightKg.formatChange(0.25) == "+0.3")
    #expect(BodyMetric.basalMetabolismKcal.formatChange(5) == "+5")
  }

  @Test func 表示の桁で0になる差は増減なしと書く() {
    #expect(BodyMetric.weightKg.formatChange(0.04) == "±0.0")
    #expect(BodyMetric.weightKg.formatChange(-0.04) == "±0.0")
  }

  @Test func 良し悪しが決まる項目だけ色を付ける() {
    #expect(BodyMetric.muscleMassKg.changeColor(0.3) == .green)
    #expect(BodyMetric.bodyFatPercent.changeColor(0.3) == .orange)
    // 体重は目標次第で良し悪しが変わる
    #expect(BodyMetric.weightKg.changeColor(-0.4) == nil)
  }

  @Test func 表示の桁で0になる差には色を付けない() {
    // 「±0.0」が緑だと良くなったように見える
    #expect(BodyMetric.muscleMassKg.changeColor(0.04) == nil)
  }
}
