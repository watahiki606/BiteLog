import Foundation

/// 記録の画面に置く体組成カードに出すもの。
///
/// 体重計には同じ日に何度も乗る。1つの数字にまとめず、乗った回数だけ行を並べる。
/// 何回乗ったかも、そのたびの値も、消したい1件も、行になっていればそのまま扱える。
///
/// カードに差は出さない。1日の上下は食事と水分で大きく振れるので、
/// 並んだ数字の横に差を添えると、読めないものを読ませることになる。
/// 前日との差は1件を開いたとき、ならした傾向は体組成の画面にある。
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
    /// 前日の最後に測ったもの。1件を開いたときの差に使う
    let previousDayLast: BodyMeasurementDTO?
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
    let previousDay = byDay[offsetDay(day, by: -1, calendar: calendar)] ?? []

    return Summary(
      measurements: today,
      previousDayLast: previousDay.last,
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

/// 測定1件を開いたときに並べる9項目。
///
/// 差は前日の最後に測ったものと比べる。前日の朝と今日の夜を引き算しても
/// 食事で増えたぶんしか出てこないが、どちらもその日の最後なら比べる意味がある。
enum BodyMeasurementDetail {
  struct Row: Equatable, Identifiable {
    let metric: BodyMetric
    /// 取れなかった項目は `nil`。0 と書くと測れたことになる
    let value: Double?
    /// 前日に同じ項目を測っていなければ出せない
    let change: Double?

    var id: String { metric.rawValue }
  }

  static func rows(
    for measurement: BodyMeasurementDTO, previousDay: BodyMeasurementDTO?
  ) -> [Row] {
    BodyMetric.allCases.map { metric in
      let value = metric.value(of: measurement)
      let previous = previousDay.flatMap { metric.value(of: $0) }
      return Row(
        metric: metric, value: value,
        change: zip2(value, previous).map { $0 - $1 })
    }
  }

  /// 両方そろっているときだけ組にする。片方でも欠けていれば差は出せない
  private static func zip2(_ lhs: Double?, _ rhs: Double?) -> (Double, Double)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
  }
}
