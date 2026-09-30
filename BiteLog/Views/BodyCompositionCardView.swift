import SwiftUI

/// 記録の画面の体組成カードの1行。測定1回ぶん。
///
/// 体重計には同じ日に何度も乗るので、1つの数字にまとめず、乗った回数だけ行を並べる。
/// 出すのは時刻と、毎日見る3項目だけ。残りの6項目と前日との差は開いた先にある。
///
/// 差をここに添えない。1日の上下は食事と水分で大きく振れるので、
/// 並んだ数字の横に差を置くと、読めないものを読ませることになる。
struct BodyMeasurementRow: View {
  let measurement: BodyMeasurementDTO
  /// 項目名を出すか。同じ日の2行目からは数字だけにして、表のように読ませる
  var showsLabels = true

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// 毎日見る3項目。9項目すべては開いた先で出す
  private static let headlineMetrics: [BodyMetric] = [
    .weightKg, .bodyFatPercent, .muscleMassKg,
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let measuredAt = measurement.measuredAtDate {
        Text(measuredAt.formatted(date: .omitted, time: .shortened))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // 大きな文字では3つを横に並べると数字が折り返して読めなくなる
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 10) { values }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 8) { values }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var values: some View {
    ForEach(Self.headlineMetrics) { metric in
      // 取れなかった項目は列ごと出さない。空欄は測ったのに読めなかったように見える
      if let value = metric.value(of: measurement) {
        BodyMetricValue(metric: metric, value: value, showsLabel: showsLabels)
      }
    }
  }
}

/// 項目名と数値。カードでも1件の画面でも同じ見た目にする。
struct BodyMetricValue: View {
  let metric: BodyMetric
  let value: Double
  /// 項目名を出すか。並べたときに同じ語を繰り返さないために消せるようにしている
  var showsLabel = true

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if showsLabel {
        Text(metric.localizedName)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(metric.format(value))
          .font(.title3)
          .fontWeight(.semibold)
          .monospacedDigit()
        if !metric.unit.isEmpty {
          Text(metric.unit)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    // 横に並べたときに幅を分け合う。左に寄せると右半分が空いたままになる
    .frame(maxWidth: .infinity, alignment: .leading)
    // 項目名を消しても読み上げでは何の値か分かるようにする
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(metric.localizedName)
    .accessibilityValue("\(metric.format(value)) \(metric.unit)")
  }
}

/// その日に測っていないときに出す行。
///
/// 空欄を出さない。前回いつ何だったかが分かれば、間が空いていることも伝わる。
struct BodyLastMeasuredRow: View {
  let last: BodyCardSummary.LastMeasured

  var body: some View {
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
