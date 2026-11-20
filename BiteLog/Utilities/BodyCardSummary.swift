import Foundation

/// 記録の画面に置く体組成カードに出すもの。
///
/// 体重計には同じ日に何度も乗る。1つの数字にまとめず、乗った回数だけ行を並べる。
/// 何回乗ったかも、そのたびの値も、消したい1件も、行になっていればそのまま扱える。
///
/// カードに差は出さない。1日の上下は食事と水分で大きく振れるので、
/// 並んだ数字の横に差を添えると、読めないものを読ませることになる。
/// 前の日の同じ頃との差は1件を開いたとき、ならした傾向は統計の画面にある。
enum BodyCardSummary {

  /// 見ている日に測っていないときに出すもの。
  ///
  /// 空欄を出さない。前回いつ何だったかが分かれば、間が空いていることも伝わる。
  struct LastMeasured: Equatable {
    let weightKg: Double?
    let bodyFatPercent: Double?
    let daysAgo: Int
  }

  struct Summary: Equatable {
    /// 見ている日に測ったぶん。早い順
    let measurements: [BodyMeasurementDTO]
    /// 取ってきた範囲の測定すべて。早い順。1件を開いたときに比べる相手を探す
    let recent: [BodyMeasurementDTO]
    let lastMeasured: LastMeasured?
    /// 取ってきた範囲に測ったものが1件でもあるか。無い人にはカードを出さない
    let hasAnyData: Bool
  }

  /// 前回いつ測ったかを遡る範囲。
  ///
  /// 見ている日と前日だけでは「前回は何日前か」を出せない。1か月あいだが空いた人には
  /// 前回の値を出さずに、測る導線だけを出す。
  static let lookbackDays = 30

  static func make(
    _ measurements: [BodyMeasurementDTO], day: String, calendar: Calendar = .current
  ) -> Summary {
    let byDay = BodyMeasurementDTO.byDay(measurements)
    let today = byDay[day] ?? []

    return Summary(
      measurements: today,
      recent: byDay.keys.sorted().flatMap { byDay[$0] ?? [] },
      lastMeasured: today.isEmpty
        ? lastMeasured(byDay, before: day, calendar: calendar) : nil,
      hasAnyData: !byDay.isEmpty)
  }

  // MARK: - 内側

  /// 見ている日より前で、最後に測った日。
  private static func lastMeasured(
    _ byDay: [String: [BodyMeasurementDTO]], before day: String, calendar: Calendar
  ) -> LastMeasured? {
    guard let previous = byDay.keys.filter({ $0 < day }).max(),
      let last = byDay[previous]?.last
    else { return nil }
    return LastMeasured(
      weightKg: last.weightKg, bodyFatPercent: last.bodyFatPercent,
      daysAgo: dayGap(from: previous, to: day, calendar: calendar))
  }

  static func offsetDay(_ day: String, by offset: Int, calendar: Calendar) -> String {
    guard let date = BodyCorrelation.dayFormatter.date(from: day),
      let shifted = calendar.date(byAdding: .day, value: offset, to: date)
    else { return day }
    return BodyCorrelation.dayFormatter.string(from: shifted)
  }

  private static func dayGap(from: String, to: String, calendar: Calendar) -> Int {
    guard let start = BodyCorrelation.dayFormatter.date(from: from),
      let end = BodyCorrelation.dayFormatter.date(from: to)
    else { return 0 }
    return calendar.dateComponents([.day], from: start, to: end).day ?? 0
  }
}

/// 測定1件を開いたときに並べる9項目と、比べる相手。
///
/// 比べるのは、前に測った日のうち最後の日の、時刻がいちばん近い回。
/// 体重は1日のうちに1kg以上動くので、昨日の夜と今朝を比べると寝ている間に
/// 抜けた水分しか出てこない。朝は朝と、夜は夜と比べれば、日をまたいだ変化として読める。
/// 同じ日の先の回とは比べない。その差は食事と水分のぶんでしかない。
enum BodyMeasurementDetail {
  struct Row: Equatable, Identifiable {
    let metric: BodyMetric
    /// 取れなかった項目は `nil`。0 と書くと測れたことになる
    let value: Double?
    /// 比べる相手が同じ項目を測っていなければ出せない
    let change: Double?

    var id: String { metric.rawValue }
  }

  static func rows(
    for measurement: BodyMeasurementDTO, reference: BodyMeasurementDTO?
  ) -> [Row] {
    BodyMetric.allCases.map { metric in
      let value = metric.value(of: measurement)
      let previous = reference.flatMap { metric.value(of: $0) }
      return Row(
        metric: metric, value: value,
        change: zip2(value, previous).map { $0 - $1 })
    }
  }

  /// 比べる相手。前に測った日が無ければ `nil`。
  ///
  /// 前日に測っていなくても、最後に測った日と比べる。いつと比べたかは画面に書くので、
  /// 間が空いていても読み違えない。
  static func reference(
    for measurement: BodyMeasurementDTO, among recent: [BodyMeasurementDTO],
    calendar: Calendar
  ) -> BodyMeasurementDTO? {
    guard let day = measurement.sourceDate,
      let target = minuteOfDay(measurement, calendar: calendar)
    else { return nil }
    let byDay = BodyMeasurementDTO.byDay(recent)
    guard let previousDay = byDay.keys.filter({ $0 < day }).max() else { return nil }
    return byDay[previousDay]?.min { lhs, rhs in
      clockDistance(lhs, to: target, calendar: calendar)
        < clockDistance(rhs, to: target, calendar: calendar)
    }
  }

  /// 時計の上での離れ具合。23:50 と 0:10 は20分しか離れていない
  private static func clockDistance(
    _ measurement: BodyMeasurementDTO, to target: Int, calendar: Calendar
  ) -> Int {
    guard let minute = minuteOfDay(measurement, calendar: calendar) else { return .max }
    let gap = abs(minute - target)
    return min(gap, 24 * 60 - gap)
  }

  private static func minuteOfDay(_ measurement: BodyMeasurementDTO, calendar: Calendar) -> Int? {
    guard let date = measurement.measuredAtDate else { return nil }
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  /// 両方そろっているときだけ組にする。片方でも欠けていれば差は出せない
  private static func zip2(_ lhs: Double?, _ rhs: Double?) -> (Double, Double)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
  }
}
