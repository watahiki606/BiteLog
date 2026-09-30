import Charts
import SwiftUI

/// 体組成を見る画面。
///
/// 食べ方が体にどう出ているかは、栄養と体組成を並べないと読めない。
/// 上のグラフで棒が栄養、折れ線が体組成。下に9項目それぞれの推移を置く。
///
/// 測っていない日は折れ線を途切れさせる。0 で埋めると、測らなかった日に
/// 体重が 0 まで落ちる谷ができる。
struct BodyCompositionView: View {
  @EnvironmentObject private var languageManager: LanguageManager
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var period: StatPeriod = .month
  @State private var offset = 0
  @State private var nutrient: TrendMetric = .calories
  @State private var bodyMetric: BodyMetric = .weightKg
  @State private var bucket: StatBucket = .day
  @State private var aggregation: StatAggregation = .average
  /// 同じ日に何度も乗るので、その日をどれで代表させるかを選べるようにする
  @State private var pick: DailyPick = .first

  @State private var nutrition: [DailyStatDTO] = []
  @State private var measurements: [BodyMeasurementDTO] = []
  @State private var isLoading = false
  @State private var loadFailed = false

  private let cal = Calendar.current

  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        if isLoading && measurements.isEmpty {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 240)
        } else if loadFailed {
          LoadFailureView { await load() }
        } else if !BodyCorrelation.hasBodyData(measurements) {
          emptyView
        } else {
          periodBar
          correlationCard
          trendCard
        }
      }
      .padding()
    }
    .background(Color(UIColor.systemGroupedBackground))
    .navigationTitle(NSLocalizedString("Body Composition", comment: "Body composition section"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker(NSLocalizedString("Period", comment: "Statistics period"), selection: $period) {
            ForEach(Self.periods) { p in
              Text(p.localizedName).tag(p)
            }
          }
        } label: {
          Text(period.localizedName)
        }
        .accessibilityLabel(NSLocalizedString("Period", comment: "Statistics period"))
      }
    }
    .task(id: reloadKey) { await load() }
    .onChange(of: period) { _, _ in
      offset = 0
      if !availableBuckets.contains(bucket) { bucket = .day }
    }
  }

  /// この画面はスクロールではなくページで送るので、期間を決め打ちにする。
  /// 自由入力の期間はここに置かない。
  private static let periods: [StatPeriod] = [.week, .month, .year]

  private var reloadKey: String { "\(period.rawValue)-\(offset)" }

  // MARK: - 期間

  private var visibleDays: Int { period.visibleDays }

  private var range: (from: Date, to: Date) {
    let today = cal.startOfDay(for: Date())
    let to = cal.date(byAdding: .day, value: -offset * visibleDays, to: today) ?? today
    let from = cal.date(byAdding: .day, value: -(visibleDays - 1), to: to) ?? to
    return (from, to)
  }

  /// 棒が1本しか出ない組み合わせを出さない。
  private var availableBuckets: [StatBucket] {
    switch period {
    case .week: return [.day]
    case .month: return [.day, .week]
    case .year, .custom: return [.day, .week, .month]
    }
  }

  private var periodBar: some View {
    let formatter = DateFormatter()
    formatter.locale = languageManager.locale
    formatter.dateStyle = dynamicTypeSize.isAccessibilitySize ? .short : .medium
    formatter.timeStyle = .none

    return HStack {
      Button { offset += 1 } label: {
        Image(systemName: "chevron.left")
          .font(.body.weight(.semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(NSLocalizedString("Previous period", comment: "Statistics paging"))

      Spacer()
      Text("\(formatter.string(from: range.from)) – \(formatter.string(from: range.to))")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .multilineTextAlignment(.center)
      Spacer()

      Button { offset = max(offset - 1, 0) } label: {
        Image(systemName: "chevron.right")
          .font(.body.weight(.semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .disabled(offset == 0)
      .accessibilityLabel(NSLocalizedString("Next period", comment: "Statistics paging"))
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - 何も持っていない人

  /// 体組成を1件も持っていない人に、軸だけのグラフを見せない。
  /// 空のグラフは「壊れている」と読まれる。
  private var emptyView: some View {
    VStack(spacing: 10) {
      Image(systemName: "figure.stand")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text(NSLocalizedString("No body composition yet", comment: "Body composition empty"))
        .font(.headline)
      Text(
        NSLocalizedString(
          "Measure once from the Log screen and your weight and body fat show up here.",
          comment: "Body composition empty help")
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, minHeight: 240)
    .padding()
  }

  // MARK: - 栄養 × 体組成

  private var series: [BodyCorrelation.Point] {
    BodyCorrelation.series(
      nutrition: nutrition, measurements: measurements, from: range.from, to: range.to,
      bucket: bucket, average: aggregation == .average, nutrient: nutrient, body: bodyMetric,
      pick: pick, calendar: cal)
  }

  /// 同じ日に2回以上乗った日がいくつあるか。代表を選ぶ意味があるかの目安にする。
  private var multiMeasurementDays: Int {
    BodyMeasurementDTO.byDay(measurements).values.filter { $0.count > 1 }.count
  }

  private var correlationCard: some View {
    CardView {
      VStack(alignment: .leading, spacing: 10) {
        Picker("", selection: $nutrient) {
          ForEach(TrendMetric.allCases) { metric in
            Text(metric.localizedName).tag(metric)
          }
        }
        .pickerStyle(.segmented)

        HStack(spacing: 8) {
          Picker("", selection: $bodyMetric) {
            ForEach(BodyMetric.allCases) { metric in
              Text(metric.localizedName).tag(metric)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()

          Spacer()

          if availableBuckets.count > 1 {
            Picker("", selection: $bucket) {
              ForEach(availableBuckets) { b in
                Text(b.localizedName).tag(b)
              }
            }
            .pickerStyle(.segmented)
            .fixedSize()
          }
        }

        // 日ごとに見ているときは、合計も平均も同じ1日ぶんなので選ばせない
        if bucket != .day {
          Picker("", selection: $aggregation) {
            ForEach(StatAggregation.allCases) { option in
              Text(option.localizedName).tag(option)
            }
          }
          .pickerStyle(.segmented)
        }

        BodyCorrelationChart(
          points: series, nutrient: nutrient, metric: bodyMetric, bucket: bucket,
          xAxisStride: xAxisStride)

        legend

        dailyPickPicker
      }
    }
  }

  /// その日をどれで代表させるか。同じ日に何度も乗る日が無ければ出さない。
  ///
  /// 体重は1日のうちに1kg以上動くので、朝いちばんと夜では別の数字になる。
  /// 黙って平均にすると、乗った回数で日ごとの値が変わってしまう。
  @ViewBuilder
  private var dailyPickPicker: some View {
    if multiMeasurementDays > 0 {
      VStack(alignment: .leading, spacing: 4) {
        Picker("", selection: $pick) {
          ForEach(DailyPick.allCases) { option in
            Text(option.localizedName).tag(option)
          }
        }
        .pickerStyle(.segmented)

        Text(
          String(
            format: NSLocalizedString(
              "%d days have more than one measurement. The band shows how much they moved that day.",
              comment: "Daily pick help"),
            multiMeasurementDays)
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var legend: some View {
    HStack(spacing: 16) {
      legendItem(color: nutrient.color, label: nutrient.localizedName, unit: nutrient.unit)
      legendItem(
        color: Color("BodyMetric"), label: bodyMetric.localizedName, unit: bodyMetric.unit)
      Spacer()
    }
    .font(.caption)
  }

  private func legendItem(color: Color, label: String, unit: String) -> some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(unit.isEmpty ? label : "\(label) (\(unit))")
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  private var xAxisStride: Int {
    let base: Int
    switch period {
    case .week: base = 1
    case .month: base = 5
    case .year, .custom: base = 30
    }
    // 大きな文字では日付が「Sep…」と切れて読めない。本数を間引く
    return dynamicTypeSize.isAccessibilitySize ? base * 3 : base
  }

  // MARK: - 9項目の推移

  private var trendCard: some View {
    let deltas = BodyCorrelation.deltas(measurements, pick: pick)
    return CardView {
      VStack(alignment: .leading, spacing: 12) {
        Text(NSLocalizedString("Change over this period", comment: "Body composition section"))
          .font(.subheadline.weight(.semibold))

        ForEach(deltas) { delta in
          deltaRow(delta)
          if delta.id != deltas.last?.id { Divider() }
        }
      }
    }
  }

  private func deltaRow(_ delta: BodyCorrelation.Delta) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(delta.metric.localizedName)
        .font(.subheadline)
      Spacer()
      if let latest = delta.latest {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(delta.metric.format(latest))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
          if !delta.metric.unit.isEmpty {
            Text(delta.metric.unit)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        changeLabel(delta)
      } else {
        // 期間内に1度も測っていない項目。0 と書くと測った日があるように読める
        Text("–")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// 期間の始めからの差。1日しか測っていない期間では出さない。
  @ViewBuilder
  private func changeLabel(_ delta: BodyCorrelation.Delta) -> some View {
    if let change = delta.change {
      let sign = change > 0 ? "+" : change < 0 ? "−" : "±"
      Text("\(sign)\(delta.metric.format(abs(change)))")
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(changeColor(delta.metric, change))
        .frame(minWidth: 52, alignment: .trailing)
    } else {
      Text(" ")
        .font(.caption)
        .frame(minWidth: 52, alignment: .trailing)
    }
  }

  /// 良し悪しが決まる項目だけ色を付ける。
  /// 体重の増減は目標次第で良くも悪くもなるので、色を付けない。
  private func changeColor(_ metric: BodyMetric, _ change: Double) -> Color {
    guard change != 0, let increaseIsGood = metric.increaseIsGood else { return .secondary }
    return (change > 0) == increaseIsGood ? .green : .orange
  }

  // MARK: - 読み込み

  private func load() async {
    guard AuthManager.shared.isSignedIn else {
      nutrition = []
      measurements = []
      return
    }
    isLoading = true
    loadFailed = false
    let from = BodyCorrelation.dayFormatter.string(from: range.from)
    let to = BodyCorrelation.dayFormatter.string(from: range.to)
    do {
      // 栄養はサーバーで日次に集計済みのものを使う。体組成は1回ずつ受け取る。
      // 日次平均に潰されると、同じ日に何度も乗ったことが見えなくなる。
      async let stats = APIClient.shared.fetchDailyStatistics(from: from, to: to)
      async let rows = APIClient.shared.fetchBodyMeasurements(from: from, to: to)
      (nutrition, measurements) = try await (stats, rows)
    } catch {
      loadFailed = true
    }
    isLoading = false
  }
}

/// 栄養の棒と体組成の折れ線を1枚に重ねる。
///
/// Swift Charts の Y 軸は1本なので、体組成の値は `BodyAxisScale` で棒側の高さへ
/// 写してから描き、右の軸に写す前の値を書く。
struct BodyCorrelationChart: View {
  let points: [BodyCorrelation.Point]
  let nutrient: TrendMetric
  let metric: BodyMetric
  let bucket: StatBucket
  let xAxisStride: Int

  private var nutrientMax: Double {
    // 棒の頭が天井に貼り付かないように少し上を取る
    max((points.map(\.nutrient).max() ?? 0) * 1.1, 1)
  }

  /// 折れ線だけでなく幅の上下も収める。代表値だけで範囲を決めると帯が枠から出る。
  private var scale: BodyAxisScale? {
    let values = points.compactMap(\.body) + points.compactMap(\.low) + points.compactMap(\.high)
    return BodyAxisScale(bodyValues: values, plotMax: nutrientMax)
  }

  /// 折れ線の1点。
  ///
  /// `series` を切れ目ごとに変えて、測っていない日をまたいでつながらないようにする。
  /// 点を飛ばして1本に描くと、間が空いたところが直線でつながって
  /// 「その間も測っていた」に見える。0 を置けば谷ができる。どちらも嘘になる。
  private func bodyLine(
    _ point: BodyCorrelation.Point, value: Double, run: Int
  ) -> some ChartContent {
    LineMark(
      x: .value(NSLocalizedString("Date", comment: "Chart axis"), point.date, unit: .day),
      y: .value(metric.localizedName, value),
      series: .value("run", run)
    )
    .foregroundStyle(Color("BodyMetric"))
    .lineStyle(StrokeStyle(lineWidth: 2))
    .interpolationMethod(.monotone)
    .symbol(.circle)
    .symbolSize(points.count > 60 ? 0 : 20)
  }

  var body: some View {
    Chart {
      ForEach(points) { point in
        BarMark(
          x: .value(NSLocalizedString("Date", comment: "Chart axis"), point.date, unit: .day),
          y: .value(nutrient.localizedName, point.nutrient)
        )
        .foregroundStyle(nutrient.color.opacity(0.55))
      }

      if let scale {
        // 同じ日に何度も乗った日の幅。折れ線1本だと、朝と夜で1kg以上違うことが消える
        ForEach(points.filter(\.hasSpread)) { point in
          if let low = point.low, let high = point.high {
            RectangleMark(
              x: .value(NSLocalizedString("Date", comment: "Chart axis"), point.date, unit: .day),
              yStart: .value(metric.localizedName, scale.project(low)),
              yEnd: .value(metric.localizedName, scale.project(high)),
              width: .fixed(3)
            )
            .foregroundStyle(Color("BodyMetric").opacity(0.3))
            .cornerRadius(1.5)
          }
        }

        // 測っていない日は y を nil のまま渡して折れ線を切る。
        // 点を飛ばすだけだと前後がつながって、測ったように見える。
        // 0 を置けば谷ができる。どちらも嘘になる。
        ForEach(Array(BodyCorrelation.measuredRuns(points).enumerated()), id: \.offset) {
          index, run in
          ForEach(run) { point in
            bodyLine(point, value: scale.project(point.body ?? 0), run: index)
          }
        }
      }
    }
    .chartYScale(domain: 0...nutrientMax)
    .chartYAxis {
      AxisMarks(position: .leading)

      if let scale {
        AxisMarks(position: .trailing, values: scale.tickPositions()) { mark in
          AxisGridLine().foregroundStyle(.clear)
          AxisValueLabel {
            if let plotted = mark.as(Double.self) {
              Text(metric.format(scale.unproject(plotted)))
                .foregroundStyle(Color("BodyMetric"))
            }
          }
        }
      }
    }
    .chartXAxis {
      AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
        AxisGridLine()
        AxisValueLabel(format: bucket == .month ? .dateTime.month() : .dateTime.month().day())
      }
    }
    // 軸ラベルは Dynamic Type に上限なく追随し、AX5 では数字がグラフの幅を食う
    .dynamicTypeSize(...DynamicTypeSize.xLarge)
    .frame(height: 220)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      String(
        format: NSLocalizedString(
          "%@ and %@ over this period", comment: "Body composition chart"),
        nutrient.localizedName, metric.localizedName))
  }

}
