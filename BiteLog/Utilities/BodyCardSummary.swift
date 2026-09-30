import Foundation

/// 記録の画面に置く体組成カードに出すもの。
///
/// 体重計には同じ日に何度も乗る。カードは「いまの体の状態」を出す場所なので、
/// その日の最後に測ったものを見出しにして、同じ日に何度乗ったかと、
/// その日どれだけ動いたかを添える。日をまたいだ比較も同じ取り方どうしで行う。
///
/// 代表の取り方を選べるのは体組成の画面のほう。カードは選ばせない。
/// 乗った直後にちらっと見る場所に、設定を置かない。
enum BodyCardSummary {

  /// 1項目ぶんの見出し。
  struct Value: Equatable {
    let latest: Double
    /// 前日の最後に測ったものとの差。前日に測っていなければ出せない
    let dayChange: Double?
  }

  /// 見ている日に測っていないときに出すもの。
  ///
  /// 空欄を出さない。前回いつ何だったかが分かれば、間が空いていることも伝わる。
  struct LastMeasured: Equatable {
    let weightKg: Double?
    let bodyFatPercent: Double?
    let daysAgo: Int
  }

  /// ならした変化。
  struct Trend: Equatable {
    /// 直近の窓の平均 − その前の窓の平均
    let change: Double
    /// 窓1つぶんの日数
    let windowDays: Int
  }

  struct Summary: Equatable {
    /// 見ている日に測ったぶん。早い順
    let measurements: [BodyMeasurementDTO]
    let weight: Value?
    let bodyFat: Value?
    let weightTrend: Trend?
    let lastMeasured: LastMeasured?
    /// 期間内に測ったものが1件でもあるか。無い人にはカードを出さない
    let hasAnyData: Bool

    /// その日に2回以上乗ったときだけ、どれだけ動いたかを出す
    var todayRange: ClosedRange<Double>? {
      let weights = measurements.compactMap(\.weightKg)
      guard let low = weights.min(), let high = weights.max(), high > low else { return nil }
      return low...high
    }
  }

  /// 傾向を見る窓。片側7日。
  ///
  /// 1日ごとの上下は食事と水分で大きく振れるので、日ごとの差からは何も読めない。
  /// 7日ずつならすと向きだけが残る。「昨日食べすぎたから増えた」と読ませない。
  static let trendWindowDays = 7

  static func make(
    _ measurements: [BodyMeasurementDTO], day: String, calendar: Calendar = .current
  ) -> Summary {
    let byDay = BodyMeasurementDTO.byDay(measurements)
    let today = byDay[day] ?? []
    let yesterday = byDay[offsetDay(day, by: -1, calendar: calendar)] ?? []

    return Summary(
      measurements: today,
      weight: value(today, yesterday) { $0.weightKg },
      bodyFat: value(today, yesterday) { $0.bodyFatPercent },
      weightTrend: trend(byDay, endingAt: day, calendar: calendar),
      lastMeasured: today.isEmpty
        ? lastMeasured(byDay, before: day, calendar: calendar) : nil,
      hasAnyData: !byDay.isEmpty)
  }

  // MARK: - 内側

  /// 見出しの1項目。その日の最後に測ったものを取り、前日の最後と比べる。
  ///
  /// 前日の朝と今日の夜を比べても、食事で増えたぶんしか出てこない。
  private static func value(
    _ today: [BodyMeasurementDTO], _ yesterday: [BodyMeasurementDTO],
    _ pick: (BodyMeasurementDTO) -> Double?
  ) -> Value? {
    guard let latest = today.compactMap(pick).last else { return nil }
    return Value(latest: latest, dayChange: yesterday.compactMap(pick).last.map { latest - $0 })
  }

  /// 直近7日と、その前の7日の平均の差。
  ///
  /// どちらの窓も測った日が無ければ出さない。片側だけで出すと、
  /// 測り始めた週に大きな変化があったように見える。
  private static func trend(
    _ byDay: [String: [BodyMeasurementDTO]], endingAt day: String, calendar: Calendar
  ) -> Trend? {
    func average(from start: Int, to end: Int) -> Double? {
      let values = (start...end).compactMap { offset -> Double? in
        byDay[offsetDay(day, by: offset, calendar: calendar)]?.compactMap(\.weightKg).last
      }
      guard !values.isEmpty else { return nil }
      return values.reduce(0, +) / Double(values.count)
    }

    let window = trendWindowDays
    guard let recent = average(from: -(window - 1), to: 0),
      let earlier = average(from: -(window * 2 - 1), to: -window)
    else { return nil }
    return Trend(change: recent - earlier, windowDays: window)
  }

  /// 見ている日より前で、最後に測った日。
  private static func lastMeasured(
    _ byDay: [String: [BodyMeasurementDTO]], before day: String, calendar: Calendar
  ) -> LastMeasured? {
    guard let previous = byDay.keys.filter({ $0 < day }).max(),
      let last = byDay[previous]?.last
    else { return nil }
    let days = dayGap(from: previous, to: day, calendar: calendar)
    return LastMeasured(
      weightKg: last.weightKg, bodyFatPercent: last.bodyFatPercent, daysAgo: days)
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
