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

  // MARK: - その日の見出し

  @Test func 最後に測ったものを見出しにする() {
    // 乗った直後にちらっと見る場所なので、いまの状態を出す
    let summary = Self.make([
      Self.measurement("2026-02-15", at: "07:00", weight: 60.9, bodyFat: 18.1),
      Self.measurement("2026-02-15", at: "21:00", weight: 61.9, bodyFat: 18.6),
    ])

    #expect(summary.weight?.latest == 61.9)
    #expect(summary.bodyFat?.latest == 18.6)
  }

  @Test func サーバーが新しい順に返しても最後の1件を取れる() {
    let summary = Self.make([
      Self.measurement("2026-02-15", at: "21:00", weight: 61.9),
      Self.measurement("2026-02-15", at: "07:00", weight: 60.9),
    ])

    #expect(summary.weight?.latest == 61.9)
  }

  @Test func その日に乗ったぶんを早い順に全部持つ() {
    let summary = Self.make([
      Self.measurement("2026-02-15", at: "21:00", weight: 61.9),
      Self.measurement("2026-02-15", at: "07:00", weight: 60.9),
      Self.measurement("2026-02-15", at: "12:00", weight: 61.4),
    ])

    #expect(summary.measurements.compactMap(\.weightKg) == [60.9, 61.4, 61.9])
  }

  @Test func 二回以上乗った日はその日どれだけ動いたかを出す() {
    let summary = Self.make([
      Self.measurement("2026-02-15", at: "07:00", weight: 60.9),
      Self.measurement("2026-02-15", at: "21:00", weight: 61.9),
    ])

    #expect(summary.todayRange == 60.9...61.9)
  }

  @Test func 一度しか乗っていない日に幅を出さない() {
    let summary = Self.make([Self.measurement("2026-02-15", at: "07:00", weight: 60.9)])

    #expect(summary.todayRange == nil)
  }

  @Test func 同じ値で二回乗っても幅は出さない() {
    let summary = Self.make([
      Self.measurement("2026-02-15", at: "07:00", weight: 60.9),
      Self.measurement("2026-02-15", at: "21:00", weight: 60.9),
    ])

    #expect(summary.todayRange == nil)
  }

  // MARK: - 前日との差

  @Test func 前日との差は同じ取り方どうしで比べる() {
    // 前日の朝と今日の夜を比べると、食事で増えたぶんしか出てこない
    let summary = Self.make([
      Self.measurement("2026-02-14", at: "07:00", weight: 60.0),
      Self.measurement("2026-02-14", at: "21:00", weight: 61.5),
      Self.measurement("2026-02-15", at: "07:00", weight: 60.2),
      Self.measurement("2026-02-15", at: "21:00", weight: 61.8),
    ])

    // どちらもその日の最後。61.8 − 61.5
    #expect(abs(summary.weight!.dayChange! - 0.3) < 0.0001)
  }

  @Test func 前日に測っていなければ差は出さない() {
    let summary = Self.make([
      Self.measurement("2026-02-13", at: "07:00", weight: 60.0),
      Self.measurement("2026-02-15", at: "07:00", weight: 60.2),
    ])

    // 2日前と比べて「前日比」と書くのは嘘になる
    #expect(summary.weight?.dayChange == nil)
  }

  @Test func 体脂肪率だけ取れなかった回があっても体重の差は出す() {
    let summary = Self.make([
      Self.measurement("2026-02-14", at: "07:00", weight: 60.0, bodyFat: 18.0),
      Self.measurement("2026-02-15", at: "07:00", weight: 60.5),
    ])

    #expect(summary.weight?.dayChange == 0.5)
    #expect(summary.bodyFat == nil)
  }

  // MARK: - ならした傾向

  /// `day` から数えて `offset` 日前
  private static func daysBefore(_ offset: Int, weight: Double) -> BodyMeasurementDTO {
    let day = BodyCardSummary.offsetDay("2026-02-15", by: -offset, calendar: calendar)
    return measurement(day, at: "07:00", weight: weight)
  }

  @Test func 直近の7日とその前の7日の平均を比べる() {
    // 1日ごとの上下は食事と水分で振れる。窓でならして向きだけを出す
    var measurements: [BodyMeasurementDTO] = []
    for offset in 0..<7 { measurements.append(Self.daysBefore(offset, weight: 60.0)) }
    for offset in 7..<14 { measurements.append(Self.daysBefore(offset, weight: 61.0)) }

    let summary = Self.make(measurements)

    #expect(abs(summary.weightTrend!.change - (-1.0)) < 0.0001)
    #expect(summary.weightTrend?.windowDays == 7)
  }

  @Test func 片側の窓しか無ければ傾向を出さない() {
    // 測り始めた週に大きな変化があったように見せない
    let measurements = (0..<7).map { Self.daysBefore($0, weight: 60.0) }

    #expect(Self.make(measurements).weightTrend == nil)
  }

  @Test func 窓の中で測った日が飛んでいても出す() {
    let measurements = [
      Self.daysBefore(0, weight: 60.0),
      Self.daysBefore(10, weight: 61.0),
    ]

    #expect(Self.make(measurements).weightTrend?.change == -1.0)
  }

  @Test func 同じ日に何度も乗っても傾向は1日1つぶんとして数える() {
    // 乗った回数の多い日に引きずられない
    var measurements = [
      Self.measurement("2026-02-15", at: "07:00", weight: 60.0),
      Self.measurement("2026-02-15", at: "12:00", weight: 60.0),
      Self.measurement("2026-02-15", at: "21:00", weight: 60.0),
    ]
    measurements.append(Self.daysBefore(10, weight: 61.0))

    #expect(Self.make(measurements).weightTrend?.change == -1.0)
  }

  // MARK: - 測っていない日

  @Test func その日に測っていなければ前回の値と何日前かを出す() {
    // 空欄を出さない。間が空いていることも伝わる
    let summary = Self.make([
      Self.measurement("2026-02-12", at: "07:00", weight: 61.0, bodyFat: 18.2)
    ])

    #expect(summary.weight == nil)
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
