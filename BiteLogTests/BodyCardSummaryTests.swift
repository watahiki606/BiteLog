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

  // MARK: - 前日の最後

  @Test func 前日の最後に測ったものを持つ() {
    // 1件を開いたときの差に使う。前日の朝と今日の夜を比べても食事のぶんしか出ない
    let summary = Self.make([
      Self.measurement("2026-02-14", at: "07:00", weight: 60.0),
      Self.measurement("2026-02-14", at: "21:00", weight: 61.5),
      Self.measurement("2026-02-15", at: "07:00", weight: 60.2),
    ])

    #expect(summary.previousDayLast?.weightKg == 61.5)
  }

  @Test func 前日に測っていなければ持たない() {
    let summary = Self.make([
      Self.measurement("2026-02-13", at: "07:00", weight: 60.0),
      Self.measurement("2026-02-15", at: "07:00", weight: 60.2),
    ])

    // 2日前と比べて「前日比」と書くのは嘘になる
    #expect(summary.previousDayLast == nil)
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
    let rows = BodyMeasurementDetail.rows(for: Self.measurement(), previousDay: nil)

    #expect(rows.map(\.metric) == BodyMetric.allCases)
  }

  @Test func 前日と比べた差を出す() {
    let rows = BodyMeasurementDetail.rows(
      for: Self.measurement(weight: 60.2),
      previousDay: Self.measurement(weight: 61.5))

    #expect(abs(Self.row(rows, .weightKg)!.change! - (-1.3)) < 0.0001)
  }

  @Test func 前日が無ければ差は出さない() {
    let rows = BodyMeasurementDetail.rows(for: Self.measurement(weight: 60.2), previousDay: nil)

    #expect(Self.row(rows, .weightKg)?.value == 60.2)
    #expect(Self.row(rows, .weightKg)?.change == nil)
  }

  @Test func 前日にその項目が無ければ差は出さない() {
    // 体重は入ったが体脂肪率が取れなかった回がある
    let rows = BodyMeasurementDetail.rows(
      for: Self.measurement(weight: 60.2, bodyFat: 18.0),
      previousDay: Self.measurement(weight: 61.5))

    #expect(Self.row(rows, .weightKg)?.change != nil)
    #expect(Self.row(rows, .bodyFatPercent)?.change == nil)
  }

  @Test func 取れなかった項目は値も差も出さない() {
    let rows = BodyMeasurementDetail.rows(
      for: Self.measurement(weight: 60.2),
      previousDay: Self.measurement(weight: 61.5, muscle: 47.0))

    // 0 と書くと測れたことになる
    #expect(Self.row(rows, .muscleMassKg)?.value == nil)
    #expect(Self.row(rows, .muscleMassKg)?.change == nil)
  }

  @Test func 整数で持っている項目も差を出せる() {
    let rows = BodyMeasurementDetail.rows(
      for: Self.measurement(metabolicAge: 34),
      previousDay: Self.measurement(metabolicAge: 35))

    #expect(Self.row(rows, .metabolicAge)?.change == -1)
  }
}
