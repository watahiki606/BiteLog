import Foundation
import SwiftUI

/// 体組成の9項目。体重計が測って返すものと同じ並び。
///
/// 合計に意味が無い値ばかりなので、集計はいつも平均。
/// 測っていない日は `nil` のままにする。0 で埋めると体重が 0 の日ができる。
enum BodyMetric: String, CaseIterable, Identifiable {
  case weightKg
  case bodyFatPercent
  case muscleMassKg
  case muscleScore
  case visceralFatLevel
  case basalMetabolismKcal
  case metabolicAge
  case boneMassKg
  case bodyWaterPercent

  var id: String { rawValue }

  var localizedName: String {
    switch self {
    case .weightKg: return NSLocalizedString("Weight", comment: "Body metric")
    case .bodyFatPercent: return NSLocalizedString("Body Fat", comment: "Body metric")
    case .muscleMassKg: return NSLocalizedString("Muscle Mass", comment: "Body metric")
    case .muscleScore: return NSLocalizedString("Muscle Score", comment: "Body metric")
    case .visceralFatLevel: return NSLocalizedString("Visceral Fat", comment: "Body metric")
    case .basalMetabolismKcal: return NSLocalizedString("BMR", comment: "Body metric")
    case .metabolicAge: return NSLocalizedString("Metabolic Age", comment: "Body metric")
    case .boneMassKg: return NSLocalizedString("Bone Mass", comment: "Body metric")
    case .bodyWaterPercent: return NSLocalizedString("Body Water", comment: "Body metric")
    }
  }

  var unit: String {
    switch self {
    case .weightKg, .muscleMassKg, .boneMassKg: return "kg"
    case .bodyFatPercent, .bodyWaterPercent: return "%"
    case .basalMetabolismKcal: return "kcal"
    case .metabolicAge: return NSLocalizedString("Unit.Years", comment: "Age unit")
    case .muscleScore, .visceralFatLevel: return ""
    }
  }

  /// 小数の桁数。体重は 0.1kg 刻みで意味があるが、基礎代謝や体内年齢は整数で足りる。
  var fractionDigits: Int {
    switch self {
    case .basalMetabolismKcal, .metabolicAge: return 0
    case .weightKg, .muscleMassKg, .boneMassKg, .bodyFatPercent, .bodyWaterPercent,
      .visceralFatLevel:
      return 1
    case .muscleScore: return 0
    }
  }

  func format(_ value: Double) -> String {
    String(format: "%.\(fractionDigits)f", value)
  }

  /// 増えたときに良い向きか。差分に色を付けるのに使う。
  ///
  /// 体重や体脂肪率は「増えた／減った」だけでは良し悪しが決まらないので、
  /// 向きを持たせない。筋肉量のように明らかに増えてほしいものだけを持つ。
  var increaseIsGood: Bool? {
    switch self {
    case .muscleMassKg, .muscleScore, .bodyWaterPercent: return true
    case .bodyFatPercent, .visceralFatLevel, .metabolicAge: return false
    case .weightKg, .basalMetabolismKcal, .boneMassKg: return nil
    }
  }

  func value(of measurement: BodyMeasurementDTO) -> Double? {
    switch self {
    case .weightKg: return measurement.weightKg
    case .bodyFatPercent: return measurement.bodyFatPercent
    case .muscleMassKg: return measurement.muscleMassKg
    case .muscleScore: return measurement.muscleScore
    case .visceralFatLevel: return measurement.visceralFatLevel
    case .basalMetabolismKcal: return measurement.basalMetabolismKcal
    case .metabolicAge: return measurement.metabolicAge.map(Double.init)
    case .boneMassKg: return measurement.boneMassKg
    case .bodyWaterPercent: return measurement.bodyWaterPercent
    }
  }
}

/// 同じ日に何度も乗ったとき、その日を代表する値の決め方。
///
/// 体重は1日のうちに1kg以上動く。起きた直後と食後では別の数字になるので、
/// 何を代表にするかで「増えた／減った」の答えが変わる。黙って平均にしない。
enum DailyPick: String, CaseIterable, Identifiable {
  /// その日いちばん早い回。起きてすぐは条件が揃うので日をまたいで比べやすい
  case first
  /// その日の平均。1日の中の上下をならす
  case average
  /// その日いちばん遅い回
  case last

  var id: String { rawValue }

  var localizedName: String {
    switch self {
    case .first: return NSLocalizedString("First of day", comment: "Daily pick")
    case .average: return NSLocalizedString("Day average", comment: "Daily pick")
    case .last: return NSLocalizedString("Last of day", comment: "Daily pick")
    }
  }

  /// 測った順（早い順）に並んだ値から、その日の代表を取る。
  func apply(_ valuesInOrder: [Double]) -> Double? {
    guard let firstValue = valuesInOrder.first, let lastValue = valuesInOrder.last else {
      return nil
    }
    switch self {
    case .first: return firstValue
    case .last: return lastValue
    case .average: return valuesInOrder.reduce(0, +) / Double(valuesInOrder.count)
    }
  }
}

extension BodyMeasurementDTO {
  /// 期間の中に入るものだけを残す。
  ///
  /// サーバーが何を返してきたかに関わらず、画面が見ている期間で切る。
  /// 期間の外の測定が混ざると、「この期間の変化」が期間を変えても動かなくなる。
  static func within(_ measurements: [BodyMeasurementDTO], from: String, to: String)
    -> [BodyMeasurementDTO]
  {
    measurements.filter { measurement in
      guard let day = measurement.sourceDate else { return false }
      return day >= from && day <= to
    }
  }

  /// 暦日ごとにまとめる。同じ日に何度も乗るので1件には潰さない。
  ///
  /// 各日の中は測った順に並べる。サーバーは新しい順で返すので、ここで向きを揃える。
  /// `sourceDate` が無い行は、どの暦日のものか決められないので落とす。
  static func byDay(_ measurements: [BodyMeasurementDTO]) -> [String: [BodyMeasurementDTO]] {
    var byDay: [String: [BodyMeasurementDTO]] = [:]
    for measurement in measurements {
      guard let day = measurement.sourceDate else { continue }
      byDay[day, default: []].append(measurement)
    }
    // ISO 8601 は桁が揃っているので、文字列の大小がそのまま時刻の前後になる
    return byDay.mapValues { $0.sorted { $0.measuredAt < $1.measuredAt } }
  }
}

/// 体組成を栄養のグラフに重ねるための計算。
///
/// 表示に必要な形へ整えるだけで、どう描くかは持たない。
/// 元は web の `apps/web/src/lib/correlation.ts` だが、日次平均ではなく
/// 1回ずつの測定から組み立てる。同じ日に何度も乗るので、平均に潰すと
/// 朝の 60.2kg と夜の 61.5kg が「その日は 60.85kg だった」になってしまう。
enum BodyCorrelation {

  /// 折れ線の1点。
  ///
  /// `body` が `nil` なのは「測っていない」。折れ線はそこで途切れるのが正しい。
  /// `low` と `high` はその区間で測った値の幅で、同じ日に何度も乗ったぶんが見える。
  struct Point: Equatable, Identifiable {
    let date: Date
    let body: Double?
    let low: Double?
    let high: Double?
    /// その区間に何回乗ったか
    let measurementCount: Int

    var id: Date { date }

    /// 幅が出るのは同じ区間で2回以上測ったときだけ
    var hasSpread: Bool {
      guard let low, let high else { return false }
      return high > low
    }
  }

  /// 体組成を1件でも持っているか。
  ///
  /// 持っていない人に折れ線の選択肢を出さない。
  static func hasBodyData(_ measurements: [BodyMeasurementDTO]) -> Bool {
    measurements.contains { measurement in
      BodyMetric.allCases.contains { $0.value(of: measurement) != nil }
    }
  }

  /// 折れ線の系列。
  ///
  /// `from` から `to` までを1日も飛ばさずに並べる。測っていない日は `nil`。
  /// 同じ日に何度も乗った日は `pick` で代表を1つ選び、その日の幅を `low`/`high` に残す。
  /// 週や月へまとめるときは、代表の平均を折れ線にし、幅はその区間で測った全部の幅にする。
  static func bodySeries(
    _ measurements: [BodyMeasurementDTO], from: Date, to: Date, bucket: StatBucket,
    body: BodyMetric, pick: DailyPick, calendar: Calendar = .current
  ) -> [Point] {
    let measurementsByDay = BodyMeasurementDTO.byDay(measurements)

    var daily: [Point] = []
    var cursor = calendar.startOfDay(for: from)
    let end = calendar.startOfDay(for: to)
    while cursor <= end {
      let key = dayFormatter.string(from: cursor)
      let values = (measurementsByDay[key] ?? []).compactMap { body.value(of: $0) }
      daily.append(
        Point(
          date: cursor, body: pick.apply(values), low: values.min(), high: values.max(),
          measurementCount: values.count))
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }

    guard let component = bucket.component else { return daily }

    let groups = Dictionary(grouping: daily) { point in
      calendar.dateInterval(of: component, for: point.date)?.start ?? point.date
    }

    return groups.map { start, points in
      let representatives = points.compactMap(\.body)
      return Point(
        date: start,
        body: representatives.isEmpty
          ? nil : representatives.reduce(0, +) / Double(representatives.count),
        low: points.compactMap(\.low).min(),
        high: points.compactMap(\.high).max(),
        measurementCount: points.reduce(0) { $0 + $1.measurementCount })
    }
    .sorted { $0.date < $1.date }
  }

  /// 期間の始めから終わりまでで、各項目がどう動いたか。
  ///
  /// いまいくつかは持たない。最新の値は期間を変えても動かないので、
  /// 「この期間の変化」と書いた場所に置くと、期間を変えても数字が変わらないように見える。
  /// いまの値は記録の画面にある。
  struct Delta: Equatable, Identifiable {
    let metric: BodyMetric
    /// 最後に測った日の代表値 − 最初に測った日の代表値。
    /// 測った日が1日だけなら比べる相手が無いので出せない
    let change: Double?
    /// 期間内にその項目を測った日数
    let measuredDays: Int

    var id: String { metric.rawValue }
  }

  /// 日をまたいだ差は、日ごとの代表どうしで比べる。
  ///
  /// 朝の値と夜の値を引き算しても、食事の影響しか出てこない。
  static func deltas(_ measurements: [BodyMeasurementDTO], pick: DailyPick) -> [Delta] {
    let byDay = BodyMeasurementDTO.byDay(measurements)
    let days = byDay.keys.sorted()

    return BodyMetric.allCases.map { metric in
      let representatives = days.compactMap { day -> Double? in
        pick.apply((byDay[day] ?? []).compactMap { metric.value(of: $0) })
      }
      // 1日分しか無ければ比べる相手が無い。0 と書くと「変わらなかった」になる
      let change =
        representatives.count > 1 ? representatives.last! - representatives[0] : nil
      return Delta(metric: metric, change: change, measuredDays: representatives.count)
    }
  }

  /// 測った点のひとつづきの並びに切り分ける。
  ///
  /// 折れ線は、測っていない日をまたいでつなげてはいけない。測った日だけを拾って
  /// 1本に描くと、間が空いたところが直線でつながって「その間も測っていた」に見える。
  /// 切れ目で分けて、それぞれを別の線として描くための下ごしらえ。
  static func measuredRuns(_ points: [Point]) -> [[Point]] {
    var runs: [[Point]] = []
    var current: [Point] = []
    for point in points {
      if point.body == nil {
        if !current.isEmpty { runs.append(current) }
        current = []
      } else {
        current.append(point)
      }
    }
    if !current.isEmpty { runs.append(current) }
    return runs
  }

  static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
}

/// 体組成の折れ線を、栄養の棒と同じグラフに載せるための対応付け。
///
/// Swift Charts の Y 軸は1本しかないので、体組成の値を栄養側の高さへ写してから描き、
/// 右側の軸には写す前の値を書く。こうしないと、60kg の体重が 2000kcal の棒に潰れて
/// 横一直線になる。
struct BodyAxisScale: Equatable {
  /// 写す前の体組成の範囲。上下に少し余白を足してある
  let lower: Double
  let upper: Double
  /// 写した先の高さ。栄養の棒の上限に合わせる
  let plotMax: Double

  /// 測った値が無ければ作らない。折れ線を描く相手がいない
  init?(bodyValues: [Double], plotMax: Double) {
    guard let min = bodyValues.min(), let max = bodyValues.max(), plotMax > 0 else { return nil }
    // 全部同じ値の日が続くと幅が 0 になる。前後に幅を作って中央に置く
    let padding = max == min ? Swift.max(abs(max) * 0.05, 0.5) : (max - min) * 0.15
    self.lower = min - padding
    self.upper = max + padding
    self.plotMax = plotMax
  }

  /// 体組成の値 → グラフ上の高さ
  func project(_ value: Double) -> Double {
    (value - lower) / (upper - lower) * plotMax
  }

  /// グラフ上の高さ → 体組成の値。右の軸のラベルに使う
  func unproject(_ plotted: Double) -> Double {
    lower + plotted / plotMax * (upper - lower)
  }

  /// 右の軸に置く目盛りの位置。高さで等間隔に取る
  func tickPositions(count: Int = 4) -> [Double] {
    guard count > 1 else { return [] }
    return (0..<count).map { plotMax * Double($0) / Double(count - 1) }
  }
}
