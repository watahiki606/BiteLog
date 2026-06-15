import Charts
import SwiftUI

// MARK: - 期間・指標モデル

/// 統計の可視期間。トレンドグラフの表示幅＝各カードの集計範囲を決める。
enum StatPeriod: String, CaseIterable, Identifiable {
  case week, month, year, custom
  var id: String { rawValue }

  var localizedName: String {
    switch self {
    case .week: return NSLocalizedString("Week", comment: "Statistics period")
    case .month: return NSLocalizedString("Month", comment: "Statistics period")
    case .year: return NSLocalizedString("Year", comment: "Statistics period")
    case .custom: return NSLocalizedString("Custom", comment: "Statistics period")
    }
  }

  /// 可視期間の日数（custom は別途算出）。
  var visibleDays: Int {
    switch self {
    case .week: return 7
    case .month: return 30
    case .year: return 365
    case .custom: return 30
    }
  }
}

/// トレンドグラフで時系列表示する栄養指標。
enum TrendMetric: String, CaseIterable, Identifiable {
  case calories, protein, fat, carbs
  var id: String { rawValue }

  var localizedName: String {
    switch self {
    case .calories: return NSLocalizedString("Calories", comment: "Nutrient")
    case .protein: return NSLocalizedString("Protein", comment: "Nutrient")
    case .fat: return NSLocalizedString("Fat", comment: "Nutrient")
    case .carbs: return NSLocalizedString("Carbs", comment: "Nutrient")
    }
  }

  var color: Color {
    switch self {
    case .calories: return .orange
    case .protein: return .blue
    case .fat: return .yellow
    case .carbs: return .green
    }
  }

  var unit: String { self == .calories ? "kcal" : "g" }

  func value(_ v: NutritionValues) -> Double {
    switch self {
    case .calories: return v.calories
    case .protein: return v.protein
    case .fat: return v.fat
    case .carbs: return v.carbs
    }
  }
}

// MARK: - 日付ユーティリティ

private enum StatDate {
  static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  static func string(_ date: Date) -> String { formatter.string(from: date) }
  static func date(_ string: String) -> Date? { formatter.date(from: string) }
}

// MARK: - StatisticsView

struct StatisticsView: View {
  @EnvironmentObject private var nutritionGoalsManager: NutritionGoalsManager
  @EnvironmentObject private var languageManager: LanguageManager

  @State private var period: StatPeriod = .week
  @State private var metric: TrendMetric = .calories

  // カスタム期間
  @State private var customFrom: Date = Calendar.current.date(
    byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date()))!
  @State private var customTo: Date = Calendar.current.startOfDay(for: Date())

  // 読み込み済みバッファ（[bufferFrom, bufferTo]）。日付×食事タイプの集計済みデータ。
  @State private var items: [DaySummaryDTO] = []
  @State private var bufferFrom: Date = Date()
  @State private var bufferTo: Date = Date()
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var loadFailed = false

  // トレンド系列。items 変化時のみ再計算してメモ化（スクロールでは再計算しない）。
  @State private var trendSeries: [DailyNutrition] = []

  // スクロール停止時のみ更新される可視左端。カード集計はこちらに連動させ、
  // スクロール中の毎ティック再集計を避ける。
  @State private var settledScrollX: Date = Date()

  private let cal = Calendar.current

  // MARK: 派生値

  private var visibleDays: Int {
    if period == .custom {
      let days = cal.dateComponents([.day], from: cal.startOfDay(for: customFrom),
        to: cal.startOfDay(for: customTo)).day ?? 0
      return max(days + 1, 1)
    }
    return period.visibleDays
  }

  private var visibleSeconds: TimeInterval { Double(visibleDays) * 86400 }

  /// カードが集計対象とする期間 [from, to]（両端の日付）。スクロール停止時の位置。
  private var settledRange: (from: Date, to: Date) {
    let from = cal.startOfDay(for: settledScrollX)
    let to = cal.date(byAdding: .day, value: visibleDays - 1, to: from) ?? from
    return (from, to)
  }

  private var settledItems: [DaySummaryDTO] {
    let fromStr = StatDate.string(settledRange.from)
    let toStr = StatDate.string(settledRange.to)
    return items.filter { $0.logDate >= fromStr && $0.logDate <= toStr }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        periodSelector

        if isLoading {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if loadFailed {
          errorView
        } else {
          visibleRangeLabel
          trendCard
          averageCard
          pfcBalanceCard
          mealTypeCard
        }
      }
      .padding()
    }
    .background(Color(UIColor.systemGroupedBackground))
    .navigationTitle(NSLocalizedString("Statistics", comment: "Tab name"))
    .navigationBarTitleDisplayMode(.inline)
    .task(id: reloadKey) { await reload() }
  }

  // task(id:) が変わったら全リセット＆再取得
  private var reloadKey: String {
    "\(period.rawValue)-\(StatDate.string(customFrom))-\(StatDate.string(customTo))"
  }

  // MARK: - 期間セレクタ

  private var periodSelector: some View {
    VStack(spacing: 12) {
      Picker("", selection: $period) {
        ForEach(StatPeriod.allCases) { p in
          Text(p.localizedName).tag(p)
        }
      }
      .pickerStyle(.segmented)

      if period == .custom {
        HStack {
          DatePicker(
            NSLocalizedString("From", comment: "Custom period start"),
            selection: $customFrom, in: ...customTo, displayedComponents: .date
          )
          .labelsHidden()
          Text("–").foregroundColor(.secondary)
          DatePicker(
            NSLocalizedString("To", comment: "Custom period end"),
            selection: $customTo, in: customFrom...Date(), displayedComponents: .date
          )
          .labelsHidden()
        }
        .frame(maxWidth: .infinity)
      }
    }
  }

  private var visibleRangeLabel: some View {
    let f = DateFormatter()
    f.locale = languageManager.locale
    f.dateStyle = .medium
    f.timeStyle = .none
    let text = "\(f.string(from: settledRange.from)) – \(f.string(from: settledRange.to))"
    return Text(text)
      .font(.subheadline.weight(.medium))
      .foregroundColor(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var errorView: some View {
    VStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle")
        .font(.largeTitle)
        .foregroundColor(.secondary)
      Text(NSLocalizedString("Failed to load statistics", comment: "Statistics error"))
        .foregroundColor(.secondary)
      Button(NSLocalizedString("Retry", comment: "Retry button")) {
        Task { await reload() }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 200)
  }

  // MARK: - ① 期間トレンド（無限横スクロール）

  private var trendCard: some View {
    CardView(title: NSLocalizedString("Trend", comment: "Statistics section")) {
      VStack(alignment: .leading, spacing: 12) {
        Picker("", selection: $metric) {
          ForEach(TrendMetric.allCases) { m in
            Text(m.localizedName).tag(m)
          }
        }
        .pickerStyle(.segmented)

        TrendChartView(
          series: trendSeries,
          metric: metric,
          visibleDays: visibleDays,
          visibleSeconds: visibleSeconds,
          // スクロール域＝バッファ全体に固定。マークは可視ウィンドウぶんだけ描画（仮想化）しても
          // スクロール extent は縮まない。末日が端で切れないよう右端は +1 日。
          domainStart: cal.startOfDay(for: bufferFrom),
          domainEnd: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: bufferTo))
            ?? bufferTo,
          goalLine: metric == .calories ? nutritionGoalsManager.targetCalories : nil,
          xAxisStride: xAxisStride,
          initialScrollX: settledScrollX,
          onScroll: { x in
            // 同期・軽量: 境界に近いときだけ追加取得を起動（毎ティック Task 生成を回避）。
            if shouldLoadMore(at: x) {
              Task { await loadMoreIfNeeded() }
            }
          },
          onScrollSettled: { x in settledScrollX = x }
        )
        .id(reloadKey)
      }
    }
  }

  private var xAxisStride: Int {
    switch period {
    case .week: return 1
    case .month: return 5
    case .year: return 1
    case .custom: return max(visibleDays / 6, 1)
    }
  }

  // MARK: - ② 1日平均と目標達成日数

  private var averageCard: some View {
    let avg = StatisticsCalculator.dailyAverage(settledItems, dayCount: visibleDays)
    let achieved = StatisticsCalculator.goalAchievedDays(
      settledItems, targetCalories: nutritionGoalsManager.targetCalories)

    return CardView(title: NSLocalizedString("Daily Average", comment: "Statistics section")) {
      VStack(spacing: 16) {
        HStack(alignment: .center, spacing: 20) {
          CalorieRingView(
            calories: avg.calories, targetCalories: nutritionGoalsManager.targetCalories)

          VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("Goal Achieved Days", comment: "Statistics metric"))
              .font(.caption)
              .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
              Text("\(achieved)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
              Text("/ \(visibleDays) " + NSLocalizedString("days", comment: "days unit"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            Text(NSLocalizedString("Calories within ±10% of goal", comment: "Achievement rule"))
              .font(.caption2)
              .foregroundColor(.secondary)
          }
          Spacer()
        }

        VStack(spacing: 8) {
          MacroBarView(
            label: NSLocalizedString("Protein", comment: "Nutrient"), value: avg.protein,
            maxValue: nutritionGoalsManager.targetProtein, color: .blue, icon: "p.circle")
          MacroBarView(
            label: NSLocalizedString("Fat", comment: "Nutrient"), value: avg.fat,
            maxValue: nutritionGoalsManager.targetFat, color: .yellow, icon: "f.circle")
          MacroBarView(
            label: NSLocalizedString("Carbs", comment: "Nutrient"), value: avg.carbs,
            maxValue: nutritionGoalsManager.targetNetCarbs + nutritionGoalsManager.targetFiber,
            color: .green, icon: "c.circle")
        }
      }
    }
  }

  // MARK: - ③ PFCバランス

  private var pfcBalanceCard: some View {
    let balance = StatisticsCalculator.pfcBalance(settledItems)

    return CardView(title: NSLocalizedString("PFC Balance", comment: "Statistics section")) {
      VStack(spacing: 12) {
        GeometryReader { geo in
          HStack(spacing: 0) {
            balanceSegment(width: geo.size.width * balance.protein / 100, color: .blue)
            balanceSegment(width: geo.size.width * balance.fat / 100, color: .yellow)
            balanceSegment(width: geo.size.width * balance.carbs / 100, color: .green)
          }
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: 24)

        HStack(spacing: 16) {
          pfcLegend(NSLocalizedString("Protein", comment: "Nutrient"), balance.protein, .blue)
          pfcLegend(NSLocalizedString("Fat", comment: "Nutrient"), balance.fat, .yellow)
          pfcLegend(NSLocalizedString("Carbs", comment: "Nutrient"), balance.carbs, .green)
        }
      }
    }
  }

  private func balanceSegment(width: CGFloat, color: Color) -> some View {
    Rectangle().fill(color).frame(width: max(width, 0))
  }

  private func pfcLegend(_ name: String, _ pct: Double, _ color: Color) -> some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(name).font(.caption).foregroundColor(.secondary)
      Text("\(pct, specifier: "%.0f")%").font(.caption.weight(.semibold))
    }
  }

  // MARK: - ④ 食事タイプ別内訳

  private var mealTypeCard: some View {
    let total = StatisticsCalculator.periodTotal(settledItems)
    let totals = StatisticsCalculator.mealTypeTotals(settledItems)
    let rows: [(type: MealType, values: NutritionValues)] = MealType.allCases.compactMap { type in
      guard let v = totals[type] else { return nil }
      return (type, v)
    }
    let maxCal = rows.map { $0.values.calories }.max() ?? 0

    return CardView(title: NSLocalizedString("By Meal Type", comment: "Statistics section")) {
      VStack(alignment: .leading, spacing: 16) {
        // 期間合計
        VStack(alignment: .leading, spacing: 6) {
          Text(NSLocalizedString("Period Total", comment: "Statistics metric"))
            .font(.caption).foregroundColor(.secondary)
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(NutritionFormatter.formatNutrition(total.calories))
              .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("kcal").font(.subheadline).foregroundColor(.secondary)
          }
          HStack(spacing: 6) {
            MacroChip(label: "P", value: total.protein, color: .blue)
            MacroChip(label: "F", value: total.fat, color: .yellow)
            MacroChip(label: "C", value: total.carbs, color: .green)
          }
        }

        Divider()

        if rows.isEmpty {
          Text(NSLocalizedString("No records in this period", comment: "Empty statistics"))
            .font(.subheadline).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        } else {
          ForEach(rows, id: \.type) { row in
            mealTypeBar(type: row.type, values: row.values, maxCal: maxCal)
          }
        }
      }
    }
  }

  private func mealTypeBar(type: MealType, values: NutritionValues, maxCal: Double) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: type.iconName)
          .font(.system(size: 12))
          .foregroundColor(type.accentColor)
          .frame(width: 16)
        Text(type.localizedName)
          .font(.system(size: 13, weight: .medium))
        Spacer()
        Text("\(NutritionFormatter.formatNutrition(values.calories)) kcal")
          .font(.system(size: 13, weight: .semibold, design: .rounded))
      }
      GeometryReader { geo in
        RoundedRectangle(cornerRadius: 3)
          .fill(type.accentColor.opacity(0.15))
          .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
              .fill(type.accentColor)
              .frame(width: maxCal > 0 ? geo.size.width * values.calories / maxCal : 0)
          }
      }
      .frame(height: 6)
      HStack(spacing: 6) {
        MacroChip(label: "P", value: values.protein, color: .blue)
        MacroChip(label: "F", value: values.fat, color: .yellow)
        MacroChip(label: "C", value: values.carbs, color: .green)
      }
    }
  }

  // MARK: - データ読み込み

  /// 期間切替時の全リセット＆初回取得。最新側が見えるようスクロール位置を合わせる。
  private func reload() async {
    guard AuthManager.shared.isSignedIn else {
      items = []
      return
    }
    isLoading = true
    loadFailed = false

    let to: Date
    let from: Date
    if period == .custom {
      to = cal.startOfDay(for: customTo)
      from = cal.startOfDay(for: customFrom)
    } else {
      to = cal.startOfDay(for: Date())
      // 可視期間の約3倍をバッファとして先読み（スクロールの初期余裕）
      from = cal.date(byAdding: .day, value: -(visibleDays * 3 - 1), to: to) ?? to
    }

    do {
      let fetched = try await APIClient.shared.fetchDailySummary(
        from: StatDate.string(from), to: StatDate.string(to))
      items = fetched
      trendSeries = StatisticsCalculator.dailyTotals(items)
      bufferFrom = from
      bufferTo = to
      // 最新の可視期間を表示（左端＝to - (visibleDays-1)）
      settledScrollX = cal.date(byAdding: .day, value: -(visibleDays - 1), to: to) ?? to
      isLoading = false
    } catch {
      loadFailed = true
      isLoading = false
    }
  }

  /// 可視左端がバッファ先頭に近いか（同期・軽量）。true のときだけ追加取得を起動する。
  /// custom では拡張しない。フェッチ中は再発火させない。
  private func shouldLoadMore(at x: Date) -> Bool {
    guard period != .custom, !isLoadingMore, AuthManager.shared.isSignedIn else { return false }
    // 可視左端がバッファ先頭から visibleDays 以内なら拡張
    let threshold = cal.date(byAdding: .day, value: visibleDays, to: bufferFrom) ?? bufferFrom
    return cal.startOfDay(for: x) <= threshold
  }

  /// 過去側を追加取得（無限スクロール）。起動判定は `shouldLoadMore(at:)` が済ませている。
  /// View は @MainActor なので `isLoadingMore` ガードで多重実行を防げる。
  private func loadMoreIfNeeded() async {
    guard period != .custom, !isLoadingMore, AuthManager.shared.isSignedIn else { return }

    isLoadingMore = true
    let newFrom = cal.date(byAdding: .day, value: -(visibleDays * 3), to: bufferFrom) ?? bufferFrom
    let oldFromMinus1 = cal.date(byAdding: .day, value: -1, to: bufferFrom) ?? bufferFrom
    do {
      let older = try await APIClient.shared.fetchDailySummary(
        from: StatDate.string(newFrom), to: StatDate.string(oldFromMinus1))
      // 重複排除して前方に結合
      let existingIDs = Set(items.map(\.id))
      items = older.filter { !existingIDs.contains($0.id) } + items
      trendSeries = StatisticsCalculator.dailyTotals(items)
      bufferFrom = newFrom
    } catch {
      // 追加取得の失敗は致命的でないため握りつぶす（次のスクロールで再試行）
    }
    isLoadingMore = false
  }
}

// MARK: - トレンドチャート（スクロール位置を自前で保持する子 View）

/// `scrollX` を自身で所有することで、横スクロール中の再評価をこの View 内に閉じ込める。
/// 親（カード群）はスクロール停止時（`onScrollSettled`）にのみ再評価される。
///
/// 仮想化: スクロール域は `chartXScale(domain:)` でバッファ全体に固定したうえで、
/// 描画する `LineMark` は毎フレーム可視ウィンドウ（`scrollX ± pad`）ぶんだけに絞る。
/// これで描画マーク数はバッファ増加（無限スクロール）と無関係に O(可視日数) で有界化される。
private struct TrendChartView: View {
  let series: [DailyNutrition]
  let metric: TrendMetric
  let visibleDays: Int
  let visibleSeconds: TimeInterval
  let domainStart: Date
  let domainEnd: Date
  let goalLine: Double?
  let xAxisStride: Int
  let initialScrollX: Date
  let onScroll: (Date) -> Void
  let onScrollSettled: (Date) -> Void

  @State private var scrollX: Date
  @State private var settleTask: Task<Void, Never>?

  init(
    series: [DailyNutrition], metric: TrendMetric, visibleDays: Int, visibleSeconds: TimeInterval,
    domainStart: Date, domainEnd: Date, goalLine: Double?, xAxisStride: Int, initialScrollX: Date,
    onScroll: @escaping (Date) -> Void, onScrollSettled: @escaping (Date) -> Void
  ) {
    self.series = series
    self.metric = metric
    self.visibleDays = visibleDays
    self.visibleSeconds = visibleSeconds
    self.domainStart = domainStart
    self.domainEnd = domainEnd
    self.goalLine = goalLine
    self.xAxisStride = xAxisStride
    self.initialScrollX = initialScrollX
    self.onScroll = onScroll
    self.onScrollSettled = onScrollSettled
    _scrollX = State(initialValue: initialScrollX)
  }

  // 長期間（月/年）は点を省き直線補間にして描画コストを抑える。
  private var simplified: Bool { visibleDays > 60 }

  /// 描画対象の可視ウィンドウ。可視範囲 `[scrollX, scrollX+visibleSeconds]` に
  /// 前後 1 画面ぶんの余白（pad）を足し、速いフリックでも端が空かないようにする。
  private var visibleSlice: ArraySlice<DailyNutrition> {
    let pad = visibleSeconds
    let fromStr = StatDate.string(scrollX.addingTimeInterval(-pad))
    let toStr = StatDate.string(scrollX.addingTimeInterval(visibleSeconds + pad))
    // series は date 昇順ソート済み。二分探索で [fromStr, toStr] のスライスを取り出す。
    let lo = lowerBound { $0.date >= fromStr }
    let hi = lowerBound { $0.date > toStr }
    return series[lo..<hi]
  }

  /// `predicate` が false→true に単調変化する最初の index（lower_bound）。
  private func lowerBound(_ predicate: (DailyNutrition) -> Bool) -> Int {
    var low = 0
    var high = series.count
    while low < high {
      let mid = (low + high) / 2
      if predicate(series[mid]) { high = mid } else { low = mid + 1 }
    }
    return low
  }

  var body: some View {
    Chart {
      ForEach(visibleSlice) { day in
        if let date = StatDate.date(day.date) {
          LineMark(
            x: .value("Date", date, unit: .day),
            y: .value(metric.localizedName, metric.value(day.values))
          )
          .foregroundStyle(metric.color)
          .interpolationMethod(simplified ? .linear : .catmullRom)

          if !simplified {
            PointMark(
              x: .value("Date", date, unit: .day),
              y: .value(metric.localizedName, metric.value(day.values))
            )
            .foregroundStyle(metric.color)
            .symbolSize(28)
          }
        }
      }
      if let goalLine {
        RuleMark(y: .value("Goal", goalLine))
          .foregroundStyle(.secondary.opacity(0.6))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
      }
    }
    .chartXScale(domain: domainStart...domainEnd)
    .chartScrollableAxes(.horizontal)
    .chartXVisibleDomain(length: visibleSeconds)
    .chartScrollPosition(x: $scrollX)
    .chartXAxis {
      AxisMarks(values: .stride(by: visibleDays > 60 ? .month : .day, count: xAxisStride)) { _ in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
      }
    }
    .frame(height: 200)
    .onChange(of: scrollX) { _, x in
      onScroll(x)  // 同期・軽量（境界近傍のみ追加取得を起動）
      // デバウンス: 停止後にのみカード集計を更新する
      settleTask?.cancel()
      settleTask = Task {
        try? await Task.sleep(for: .milliseconds(150))
        if !Task.isCancelled { onScrollSettled(x) }
      }
    }
  }
}
