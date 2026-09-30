import Foundation
import Testing

@testable import BiteLog

/// 栄養と体組成を1枚のグラフに載せるための計算。
///
/// 体重計には同じ日に何度も乗る。その前提で、代表の選び方と1日の幅を確かめる。
/// 数値はすべて架空。実際の記録は使っていない。
struct BodyCorrelationTests {

  /// 端末の地域で結果が変わらないように、週の始まりまで決め打ちにする。
  /// アプリ本体は `Calendar.current` を使うので、週の始まりは端末の設定に従う。
  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    calendar.firstWeekday = 1
    return calendar
  }

  private static func day(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: string)!
  }

  private static func stat(
    _ date: String, calories: Double = 0, netCarbs: Double = 0, fiber: Double = 0
  ) -> DailyStatDTO {
    DailyStatDTO(
      date: date, calories: calories, protein: 0, fat: 0, netCarbs: netCarbs,
      dietaryFiber: fiber, weightKg: nil, bodyFatPercent: nil, muscleMassKg: nil,
      muscleScore: nil, visceralFatLevel: nil, basalMetabolismKcal: nil, metabolicAge: nil,
      boneMassKg: nil, bodyWaterPercent: nil)
  }

  /// 暦日と計測時刻を分けて渡す。
  ///
  /// `measuredAt` は UTC なので、朝いちばんの計測は前日の日付になる。
  /// そのずれを書けるように、UTC 側の日付を `utcDay` で上書きできるようにしている。
  private static func measurement(
    _ day: String, at time: String, utcDay: String? = nil, weight: Double? = nil,
    bodyFat: Double? = nil, muscle: Double? = nil
  ) -> BodyMeasurementDTO {
    let stamp = "\(utcDay ?? day)T\(time):00.000Z"
    return BodyMeasurementDTO(
      id: stamp, sourceDate: day, measuredAt: stamp,
      weightKg: weight, bodyFatPercent: bodyFat, muscleMassKg: muscle, muscleScore: nil,
      visceralFatLevel: nil, basalMetabolismKcal: nil, metabolicAge: nil, boneMassKg: nil,
      bodyWaterPercent: nil)
  }

  private static func series(
    nutrition: [DailyStatDTO] = [], measurements: [BodyMeasurementDTO] = [], from: String,
    to: String, bucket: StatBucket = .day, average: Bool = false,
    nutrient: TrendMetric = .calories, body: BodyMetric = .weightKg, pick: DailyPick = .first
  ) -> [BodyCorrelation.Point] {
    BodyCorrelation.series(
      nutrition: nutrition, measurements: measurements, from: day(from), to: day(to),
      bucket: bucket, average: average, nutrient: nutrient, body: body, pick: pick,
      calendar: calendar)
  }

  // MARK: - 日次の系列

  @Test func 期間の両端まで1日も飛ばさずに並べる() {
    let points = Self.series(
      nutrition: [Self.stat("2026-01-02", calories: 1800)], from: "2026-01-01", to: "2026-01-05")

    #expect(points.count == 5)
    #expect(points.first?.date == Self.day("2026-01-01"))
    #expect(points.last?.date == Self.day("2026-01-05"))
  }

  @Test func 記録の無い日の栄養は0にする() {
    let points = Self.series(
      nutrition: [Self.stat("2026-01-02", calories: 1800)], from: "2026-01-01", to: "2026-01-03")

    #expect(points[0].nutrient == 0)
    #expect(points[1].nutrient == 1800)
  }

  @Test func 測っていない日の体組成はnilにする() {
    // 0 で埋めると、測らなかった日に体重が 0 まで落ちる谷ができる
    let points = Self.series(
      measurements: [
        Self.measurement("2026-01-01", at: "07:00", weight: 61.0),
        Self.measurement("2026-01-03", at: "07:00", weight: 60.8),
      ], from: "2026-01-01", to: "2026-01-03")

    #expect(points[0].body == 61.0)
    #expect(points[1].body == nil)
    #expect(points[2].body == 60.8)
  }

  @Test func 炭水化物は糖質と食物繊維の合計にする() {
    let points = Self.series(
      nutrition: [Self.stat("2026-01-01", netCarbs: 180, fiber: 20)], from: "2026-01-01",
      to: "2026-01-01", nutrient: .carbs)

    #expect(points[0].nutrient == 200)
  }

  // MARK: - 同じ日に何度も乗る

  /// 同じ日の朝いちばん・昼・夜。体重は1日のうちにこれくらい動く。
  /// 朝の回だけ UTC では前日に入る
  private static var threeTimesADay: [BodyMeasurementDTO] {
    [
      Self.measurement("2026-01-02", at: "22:00", utcDay: "2026-01-01", weight: 60.2),
      Self.measurement("2026-01-02", at: "03:30", weight: 61.0),
      Self.measurement("2026-01-02", at: "12:00", weight: 61.4),
    ]
  }

  @Test func 朝いちばんを代表にできる() {
    // サーバーは新しい順に返す。並び順に引きずられて最後の1件を拾ってはいけない
    let points = Self.series(
      measurements: Self.threeTimesADay.reversed(), from: "2026-01-02", to: "2026-01-02",
      pick: .first)

    #expect(points[0].body == 60.2)
  }

  @Test func その日の最後を代表にできる() {
    let points = Self.series(
      measurements: Self.threeTimesADay, from: "2026-01-02", to: "2026-01-02", pick: .last)

    #expect(points[0].body == 61.4)
  }

  @Test func その日の平均を代表にできる() {
    let points = Self.series(
      measurements: Self.threeTimesADay, from: "2026-01-02", to: "2026-01-02", pick: .average)

    #expect(abs(points[0].body! - (60.2 + 61.0 + 61.4) / 3) < 0.0001)
  }

  @Test func その日どれだけ動いたかを幅として残す() {
    let points = Self.series(
      measurements: Self.threeTimesADay, from: "2026-01-02", to: "2026-01-02")

    #expect(points[0].low == 60.2)
    #expect(points[0].high == 61.4)
    #expect(points[0].measurementCount == 3)
    #expect(points[0].hasSpread)
  }

  @Test func 一度しか乗らなかった日に幅は出さない() {
    let points = Self.series(
      measurements: [Self.measurement("2026-01-02", at: "03:30", weight: 61.0)],
      from: "2026-01-02", to: "2026-01-02")

    #expect(points[0].measurementCount == 1)
    #expect(!points[0].hasSpread)
  }

  @Test func 暦日は計測時刻ではなくsourceDateで決める() {
    // 3件とも UTC では 2026-01-01 と 2026-01-02 にまたがるが、暦日は同じ 2026-01-02
    let points = Self.series(
      measurements: Self.threeTimesADay, from: "2026-01-01", to: "2026-01-02")

    #expect(points[0].measurementCount == 0)
    #expect(points[1].measurementCount == 3)
  }

  @Test func 選んだ項目を測っていない回は数に入れない() {
    // 体重だけ入って体脂肪率が取れなかった回がある
    let points = Self.series(
      measurements: [
        Self.measurement("2026-01-02", at: "03:30", weight: 61.0, bodyFat: 18.0),
        Self.measurement("2026-01-02", at: "12:00", weight: 61.4),
      ], from: "2026-01-02", to: "2026-01-02", body: .bodyFatPercent)

    #expect(points[0].measurementCount == 1)
    #expect(points[0].body == 18.0)
  }

  // MARK: - 週・月へまとめる

  @Test func 週へまとめると栄養は合計になる() {
    let nutrition = (1...7).map { Self.stat(String(format: "2026-01-%02d", $0), calories: 100) }
    let points = Self.series(
      nutrition: nutrition, from: "2026-01-01", to: "2026-01-07", bucket: .week)

    #expect(points.map(\.nutrient).reduce(0, +) == 700)
  }

  @Test func 週の平均は暦日数で割る() {
    // 3日しか記録しなかった週が、毎日食べた週より多く見えてはいけない
    let nutrition = [
      Self.stat("2026-01-05", calories: 2100),
      Self.stat("2026-01-06", calories: 2100),
      Self.stat("2026-01-07", calories: 2100),
    ]
    // 2026-01-04 は日曜。この暦で1週ちょうどになる範囲を取る
    let points = Self.series(
      nutrition: nutrition, from: "2026-01-04", to: "2026-01-10", bucket: .week, average: true)

    #expect(points.count == 1)
    // 記録のあった3日ではなく、週の7日で割る
    #expect(points[0].nutrient == 6300.0 / 7.0)
  }

  @Test func 週の折れ線は日ごとの代表の平均にする() {
    // 乗った回数の多い日に引きずられないこと。5日は2回、7日は1回
    let measurements = [
      Self.measurement("2026-01-05", at: "03:00", weight: 60.0),
      Self.measurement("2026-01-05", at: "12:00", weight: 62.0),
      Self.measurement("2026-01-07", at: "03:00", weight: 61.0),
    ]
    let points = Self.series(
      measurements: measurements, from: "2026-01-04", to: "2026-01-10", bucket: .week,
      pick: .first)

    // 朝いちばんどうしの平均。全6件の平均 61.0 ではなく (60.0 + 61.0) / 2
    #expect(points[0].body == 60.5)
  }

  @Test func 週の幅はその週に測った全部の幅にする() {
    let measurements = [
      Self.measurement("2026-01-05", at: "03:00", weight: 60.0),
      Self.measurement("2026-01-05", at: "12:00", weight: 62.0),
      Self.measurement("2026-01-07", at: "03:00", weight: 61.0),
    ]
    let points = Self.series(
      measurements: measurements, from: "2026-01-04", to: "2026-01-10", bucket: .week)

    #expect(points[0].low == 60.0)
    #expect(points[0].high == 62.0)
    #expect(points[0].measurementCount == 3)
  }

  @Test func 一度も測らなかった週の体組成はnilにする() {
    let points = Self.series(
      nutrition: [Self.stat("2026-01-05", calories: 2000)], from: "2026-01-04", to: "2026-01-10",
      bucket: .week)

    #expect(points[0].body == nil)
  }

  @Test func まとめた結果は日付の昇順で返す() {
    let nutrition = (1...28).map { Self.stat(String(format: "2026-01-%02d", $0), calories: 100) }
    let points = Self.series(
      nutrition: nutrition, from: "2026-01-01", to: "2026-01-28", bucket: .week)

    #expect(points.map(\.date) == points.map(\.date).sorted())
  }

  // MARK: - 体組成を持っているか

  @Test func 体組成が1件も無ければ持っていないと判断する() {
    #expect(!BodyCorrelation.hasBodyData([]))
  }

  @Test func どれか1項目でもあれば持っていると判断する() {
    // 体重だけ入っていない回もある。9項目のどれかがあればよい
    #expect(
      BodyCorrelation.hasBodyData([Self.measurement("2026-01-01", at: "07:00", muscle: 47.5)]))
  }

  @Test func 値がすべて空の行は持っていないと判断する() {
    #expect(!BodyCorrelation.hasBodyData([Self.measurement("2026-01-01", at: "07:00")]))
  }

  // MARK: - 期間の変化

  @Test func 期間の端から端までの差を出す() {
    let deltas = BodyCorrelation.deltas(
      [
        Self.measurement("2026-01-01", at: "03:00", weight: 62.0),
        Self.measurement("2026-01-05", at: "03:00", weight: 60.5),
      ], pick: .first)

    #expect(deltas.first { $0.metric == .weightKg }?.change == -1.5)
  }

  @Test func 期間の外の測定は差に混ぜない() {
    // サーバーが期間の外まで返してくることがある。そのまま使うと、
    // 期間を変えても「この期間の変化」が動かない
    let all = [
      Self.measurement("2025-06-01", at: "03:00", weight: 70.0),
      Self.measurement("2026-01-20", at: "03:00", weight: 61.5),
      Self.measurement("2026-01-31", at: "03:00", weight: 61.0),
    ]

    let inRange = BodyMeasurementDTO.within(all, from: "2026-01-01", to: "2026-01-31")

    #expect(inRange.count == 2)
    #expect(BodyCorrelation.deltas(inRange, pick: .first).first { $0.metric == .weightKg }?
      .change == -0.5)
  }

  @Test func 期間の両端はどちらも含める() {
    let all = [
      Self.measurement("2026-01-01", at: "03:00", weight: 62.0),
      Self.measurement("2026-01-31", at: "03:00", weight: 61.0),
    ]

    #expect(BodyMeasurementDTO.within(all, from: "2026-01-01", to: "2026-01-31").count == 2)
    #expect(BodyMeasurementDTO.within(all, from: "2026-01-02", to: "2026-01-30").isEmpty)
  }

  @Test func 期間を広げると差も変わる() {
    // 「この期間の変化」が期間に連動していること。
    // 最新の値だけを出していたころは、期間を変えても数字が動かなかった
    let measurements = [
      Self.measurement("2026-01-01", at: "03:00", weight: 63.0),
      Self.measurement("2026-01-20", at: "03:00", weight: 61.5),
      Self.measurement("2026-01-31", at: "03:00", weight: 61.0),
    ]
    let narrow = Array(measurements.dropFirst())

    let wide = BodyCorrelation.deltas(measurements, pick: .first)
    let short = BodyCorrelation.deltas(narrow, pick: .first)

    #expect(wide.first { $0.metric == .weightKg }?.change == -2.0)
    #expect(short.first { $0.metric == .weightKg }?.change == -0.5)
  }

  @Test func 日をまたいだ差は代表どうしで比べる() {
    // 朝 60.0 → 翌朝 60.2。夜の 61.5 と朝の 60.0 を引き算すると、
    // 食事の影響しか出てこない
    let deltas = BodyCorrelation.deltas(
      [
        Self.measurement("2026-01-01", at: "03:00", weight: 60.0),
        Self.measurement("2026-01-01", at: "12:00", weight: 61.5),
        Self.measurement("2026-01-02", at: "03:00", weight: 60.2),
      ], pick: .first)

    #expect(abs(deltas.first { $0.metric == .weightKg }!.change! - 0.2) < 0.0001)
  }

  @Test func 代表の選び方を変えると差も変わる() {
    let measurements = [
      Self.measurement("2026-01-01", at: "03:00", weight: 60.0),
      Self.measurement("2026-01-01", at: "12:00", weight: 61.5),
      Self.measurement("2026-01-02", at: "03:00", weight: 60.2),
      Self.measurement("2026-01-02", at: "12:00", weight: 61.0),
    ]

    let byFirst = BodyCorrelation.deltas(measurements, pick: .first)
    let byLast = BodyCorrelation.deltas(measurements, pick: .last)

    #expect(abs(byFirst.first { $0.metric == .weightKg }!.change! - 0.2) < 0.0001)
    #expect(abs(byLast.first { $0.metric == .weightKg }!.change! - (-0.5)) < 0.0001)
  }

  @Test func 並びが前後していても期間の始めから見る() {
    let deltas = BodyCorrelation.deltas(
      [
        Self.measurement("2026-01-05", at: "03:00", weight: 60.5),
        Self.measurement("2026-01-01", at: "03:00", weight: 62.0),
      ], pick: .first)

    #expect(deltas.first { $0.metric == .weightKg }?.change == -1.5)
  }

  @Test func 測った日が1日だけなら差は出さない() {
    // 同じ日に2回乗っても、日をまたいでいなければ比べる相手が無い
    let deltas = BodyCorrelation.deltas(
      [
        Self.measurement("2026-01-01", at: "03:00", weight: 62.0),
        Self.measurement("2026-01-01", at: "12:00", weight: 63.1),
      ], pick: .first)
    let weight = deltas.first { $0.metric == .weightKg }

    // 0 と書くと「変わらなかった」に読める
    #expect(weight?.change == nil)
    #expect(weight?.measuredDays == 1)
  }

  @Test func 一度も測っていない項目は差も日数も出さない() {
    let deltas = BodyCorrelation.deltas(
      [Self.measurement("2026-01-01", at: "03:00", weight: 62.0)], pick: .first)
    let bodyFat = deltas.first { $0.metric == .bodyFatPercent }

    #expect(bodyFat?.change == nil)
    #expect(bodyFat?.measuredDays == 0)
  }

  @Test func どの項目も同じ並びで返す() {
    #expect(BodyCorrelation.deltas([], pick: .first).map(\.metric) == BodyMetric.allCases)
  }

  // MARK: - 折れ線の切れ目

  private static func point(_ day: Int, body: Double?) -> BodyCorrelation.Point {
    BodyCorrelation.Point(
      date: Self.day(String(format: "2026-01-%02d", day)), nutrient: 0, body: body,
      low: body, high: body, measurementCount: body == nil ? 0 : 1)
  }

  @Test func 測っていない日で折れ線を切る() {
    // 測った日だけを拾って1本に描くと、間の空いたところが直線でつながる
    let runs = BodyCorrelation.measuredRuns([
      Self.point(1, body: 61.0),
      Self.point(2, body: 60.8),
      Self.point(3, body: nil),
      Self.point(4, body: 60.5),
    ])

    #expect(runs.count == 2)
    #expect(runs[0].map(\.body) == [61.0, 60.8])
    #expect(runs[1].map(\.body) == [60.5])
  }

  @Test func 切れ目が無ければ1本にまとめる() {
    let runs = BodyCorrelation.measuredRuns([
      Self.point(1, body: 61.0), Self.point(2, body: 60.8),
    ])

    #expect(runs.count == 1)
  }

  @Test func 両端が空いていても中身だけを拾う() {
    let runs = BodyCorrelation.measuredRuns([
      Self.point(1, body: nil), Self.point(2, body: 60.8), Self.point(3, body: nil),
    ])

    #expect(runs.count == 1)
    #expect(runs[0].map(\.body) == [60.8])
  }

  @Test func 一度も測っていなければ線を1本も描かない() {
    #expect(BodyCorrelation.measuredRuns([Self.point(1, body: nil)]).isEmpty)
  }

  // MARK: - 暦日ごとのまとめ

  @Test func 暦日ごとに測った順へ並べ直す() {
    // サーバーは新しい順に返すので、向きを揃えないと朝いちばんが取れない
    let byDay = BodyMeasurementDTO.byDay(Self.threeTimesADay.reversed())

    #expect(byDay["2026-01-02"]?.map(\.weightKg) == [60.2, 61.0, 61.4])
  }

  @Test func 暦日が分からない行は落とす() {
    let orphan = BodyMeasurementDTO(
      id: "x", sourceDate: nil, measuredAt: "2026-01-02T03:00:00.000Z", weightKg: 60,
      bodyFatPercent: nil, muscleMassKg: nil, muscleScore: nil, visceralFatLevel: nil,
      basalMetabolismKcal: nil, metabolicAge: nil, boneMassKg: nil, bodyWaterPercent: nil)

    #expect(BodyMeasurementDTO.byDay([orphan]).isEmpty)
  }
}

/// 体組成の折れ線を栄養の棒と同じ高さに載せるための対応付け。
struct BodyAxisScaleTests {

  @Test func 写して戻すと元の値になる() {
    let scale = BodyAxisScale(bodyValues: [59.0, 62.0, 60.5], plotMax: 2400)!

    #expect(abs(scale.unproject(scale.project(60.5)) - 60.5) < 0.0001)
  }

  @Test func 値の幅いっぱいに広げず上下に余白を残す() {
    let scale = BodyAxisScale(bodyValues: [59.0, 62.0], plotMax: 2400)!

    // 上端と下端が枠に貼り付くと、折れ線が切れているように見える
    #expect(scale.lower < 59.0)
    #expect(scale.upper > 62.0)
  }

  @Test func 同じ値しか無くても高さを持たせる() {
    // 幅が 0 だと写すときに 0 で割る
    let scale = BodyAxisScale(bodyValues: [60.0, 60.0], plotMax: 2400)!

    #expect(scale.upper > scale.lower)
    #expect(scale.project(60.0).isFinite)
  }

  @Test func 測った値が無ければ作らない() {
    #expect(BodyAxisScale(bodyValues: [], plotMax: 2400) == nil)
  }

  @Test func 棒の高さが無ければ作らない() {
    // 記録がまったく無い期間。写す先の高さが 0 になる
    #expect(BodyAxisScale(bodyValues: [60.0], plotMax: 0) == nil)
  }

  @Test func 目盛りは高さの範囲に収める() {
    let scale = BodyAxisScale(bodyValues: [59.0, 62.0], plotMax: 2400)!
    let ticks = scale.tickPositions(count: 4)

    #expect(ticks.count == 4)
    #expect(ticks.first == 0)
    #expect(ticks.last == 2400)
  }
}
