import SwiftUI

/// 記録の画面の体組成カードに出す数値。
///
/// 体重計には同じ日に何度も乗る。最後に測ったものを見出しにして、
/// その日に何回乗って、どれだけ動いたかを添える。1つの数字にまとめない。
///
/// 日ごとの差は小さく出す。1日の上下は食事と水分で大きく振れるので、
/// そこから読めることは少ない。読めるのはならした傾向のほう。
struct BodyCompositionValuesView: View {
  let summary: BodyCardSummary.Summary

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if summary.weight != nil || summary.bodyFat != nil {
        measuredDay
      } else if let last = summary.lastMeasured {
        // その日に測っていない。空欄を出さずに、前回いつ何だったかを出す
        previously(last)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// 体重・体脂肪率・傾向を横に並べる。
  ///
  /// 傾向も数値の1つとして同じ高さに置く。1日ごとの差は食事と水分で振れるので、
  /// 向きが読めるのは傾向のほう。小さな注釈にすると読まれない。
  private var measuredDay: some View {
    VStack(alignment: .leading, spacing: 8) {
      // 大きな文字では3つを横に並べると数字が折り返して読めなくなる
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) { columns }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 8) { columns }
      }

      if let detail = dayDetail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var columns: some View {
    if let weight = summary.weight {
      value(BodyMetric.weightKg.localizedName, weight, unit: "kg", metric: .weightKg)
    }
    if let bodyFat = summary.bodyFat {
      value(
        BodyMetric.bodyFatPercent.localizedName, bodyFat, unit: "%", metric: .bodyFatPercent)
    }
    if let trend = summary.weightTrend {
      trendColumn(trend)
    }
  }

  /// ならした傾向。窓2つぶんの平均の差なので、前日との差とは別の数字。
  private func trendColumn(_ trend: BodyCardSummary.Trend) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(
        String(
          format: NSLocalizedString("%d-day trend", comment: "Body card trend label"),
          trend.windowDays)
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(signed(trend.change, digits: 1))
          .font(.title3)
          .fontWeight(.semibold)
          .monospacedDigit()
        Text("kg")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  /// 何時に測ったか。2回以上乗った日は回数とその日の幅も添える。
  ///
  /// 「今日」とは書かない。このカードは見ている日のものを出すので、
  /// 過去の日を開いているときに「今日」と書くと嘘になる。
  private var dayDetail: String? {
    let times = summary.measurements.compactMap(\.measuredAtDate)
    guard let latest = times.last else { return nil }
    let clock = latest.formatted(date: .omitted, time: .shortened)

    guard summary.measurements.count > 1 else { return clock }
    let count = String(
      format: NSLocalizedString("%d measurements", comment: "Body card measurement count"),
      summary.measurements.count)
    guard let range = summary.dayRange else { return "\(clock) · \(count)" }
    let spread =
      "\(BodyMetric.weightKg.format(range.lowerBound))–"
      + "\(BodyMetric.weightKg.format(range.upperBound)) kg"
    return "\(clock) · \(count) · \(spread)"
  }

  private func value(
    _ label: String, _ value: BodyCardSummary.Value, unit: String, metric: BodyMetric
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(metric.format(value.latest))
          .font(.title3)
          .fontWeight(.semibold)
          .monospacedDigit()
        Text(unit)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let change = value.dayChange {
          Text(signed(change, digits: metric.fractionDigits))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
        }
      }
    }
    // 3つで幅を分け合う。左に寄せると右半分が空いたままになる
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func previously(_ last: BodyCardSummary.LastMeasured) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(
        String(
          format: NSLocalizedString("Last measured %d days ago", comment: "Body card last seen"),
          last.daysAgo)
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack(alignment: .firstTextBaseline, spacing: 16) {
        if let weight = last.weightKg {
          Text("\(BodyMetric.weightKg.format(weight)) kg")
        }
        if let bodyFat = last.bodyFatPercent {
          Text("\(BodyMetric.bodyFatPercent.format(bodyFat)) %")
        }
      }
      .font(.subheadline)
      .monospacedDigit()
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  /// 増減の向きが一目で分かる形にする。マイナス記号は全角の −
  private func signed(_ value: Double, digits: Int) -> String {
    let rounded = (value * pow(10, Double(digits))).rounded() / pow(10, Double(digits))
    let sign = rounded > 0 ? "+" : rounded < 0 ? "−" : "±"
    return sign + String(format: "%.\(digits)f", abs(rounded))
  }
}

/// カードの下段。測るか、探している途中かを出す。
struct BodyCompositionActionView: View {
  let hasMeasurementToday: Bool
  let activity: BodyCompositionModel.Activity
  /// いまから測れる日か。過去の日には測る導線を出さない
  let canMeasure: Bool
  let failure: String?
  let onMeasure: () -> Void
  let onStop: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if activity != .idle {
        progress
      } else if canMeasure {
        measureButton
      }

      if let failure {
        Text(failure)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// 測っていない日は、測れることをはっきり出す。
  /// 一度測ったあとは控えめにする。同じ日にまた乗ることはあるが、主役は値のほう。
  @ViewBuilder
  private var measureButton: some View {
    if hasMeasurementToday {
      Button(
        NSLocalizedString("Measure again", comment: "Body composition card button"),
        action: onMeasure
      )
      .buttonStyle(.borderless)
      .font(.subheadline)
    } else {
      Button(action: onMeasure) {
        Label(
          NSLocalizedString("Measure", comment: "Body composition card button"),
          systemImage: "scalemass")
      }
      .buttonStyle(.bordered)
    }
  }

  private var progress: some View {
    HStack(spacing: 10) {
      ProgressView()
      Text(activityText)
        .font(.subheadline)
        .foregroundStyle(activity == .waitingForStep ? .primary : .secondary)
      Spacer()
      Button(NSLocalizedString("Stop", comment: "Scale import button"), action: onStop)
        .buttonStyle(.borderless)
        .font(.subheadline)
    }
  }

  private var activityText: String {
    switch activity {
    case .idle:
      return ""
    case .searching:
      return NSLocalizedString("Looking for the scale", comment: "Scale import status")
    case .waitingForStep:
      return NSLocalizedString("Step on the scale", comment: "Scale import status")
    case .reading:
      return NSLocalizedString("Receiving measurements", comment: "Scale import status")
    }
  }
}
