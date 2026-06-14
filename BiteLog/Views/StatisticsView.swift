import Charts
import SwiftUI

// MARK: - 期間タイプ

enum StatsPeriodType: CaseIterable, Identifiable {
  case week, month, year, custom
  var id: Self { self }

  var localizedName: String {
    switch self {
    case .week: return NSLocalizedString("Week", comment: "Statistics period")
    case .month: return NSLocalizedString("Month", comment: "Statistics period")
    case .year: return NSLocalizedString("Year", comment: "Statistics period")
    case .custom: return NSLocalizedString("Custom", comment: "Statistics period")
    }
  }
}

// MARK: - トレンドで表示する指標

enum TrendMetric: CaseIterable, Identifiable {
  case calories, protein, fat, carbs
  var id: Self { self }

  var localizedName: String {
    switch self {
    case .calories: return NSLocalizedString("Calories", comment: "Nutrient label")
    case .protein: return NSLocalizedString("Protein", comment: "Nutrient label")
    case .fat: return NSLocalizedString("Fat", comment: "Nutrient label")
    case .carbs: return NSLocalizedString("Carbs (Sugar + Fiber)", comment: "Nutrient label")
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

  func value(_ v: NutritionValues) -> Double {
    switch self {
    case .calories: return v.calories
    case .protein: return v.protein
    case .fat: return v.fat
    case .carbs: return v.carbs
    }
  }
}

// MARK: - 日別集計の1点

struct StatsDayPoint: Identifiable {
  let date: Date
  let values: NutritionValues
  var id: Date { date }
}

// MARK: - 統計画面

struct StatisticsView: View {
  @EnvironmentObject private var nutritionGoalsManager: NutritionGoalsManager

  @State private var periodType: StatsPeriodType = .week
  /// スクロール表示中ウィンドウの先頭日（週/月/年モードで使用）
  @State private var scrollPosition = Date()
  @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
  @State private var customEnd = Date()
  @State private var trendMetric: TrendMetric = .calories

  @State private var items: [LogItemDTO] = []
  /// 取得済みの最も古い日。スクロールで端に近づくと過去へ伸ばす
  @State private var loadedStart = Calendar.current.date(byAdding: .day, value: -730, to: Date())!
  @State private var isLoading = false
  @State private var isLoadingMore = false

  private let calendar = Calendar.current
  /// 起動時点の今日（スクロール範囲の基準。ビュー生成中に固定）
  private let referenceDate = Calendar.current.startOfDay(for: Date())

  /// 初回取得する日数（年表示でも遡れるよう2年分）
  private let initialSpanDays = 730
  /// 端に達したとき追加で遡る日数（1年ずつ）
  private let chunkDays = 365

  /// スクロールで一度に見せる日数（週=7 / 月=30 / 年=365 のローリングウィンドウ）
  private var visibleSpanDays: Int {
    switch periodType {
    case .week: return 7
    case .month: return 30
    case .year: return 365
    case .custom: return max(days(in: loadInterval).count, 1)
    }
  }
  private var domainSeconds: TimeInterval { Double(visibleSpanDays) * 86400 }

  /// トレンドグラフのバー単位（年は月次集計、それ以外は日次）
  private var barUnit: Calendar.Component { periodType == .year ? .month : .day }

  // MARK: - 期間計算

  /// データ取得範囲。週/月/年はまとめて取得し、スクロールはメモリ上で処理する
  private var loadInterval: (start: Date, end: Date) {
    switch periodType {
    case .custom:
      return (
        calendar.startOfDay(for: min(customStart, customEnd)),
        calendar.startOfDay(for: max(customStart, customEnd)))
    default:
      return (loadedStart, referenceDate)
    }
  }

  /// 現在表示中（スクロール位置）のウィンドウ。各カードの集計対象
  private var visibleInterval: (start: Date, end: Date) {
    switch periodType {
    case .custom:
      return loadInterval
    default:
      let start = calendar.startOfDay(for: scrollPosition)
      let end = calendar.date(byAdding: .day, value: visibleSpanDays - 1, to: start)!
      return (start, end)
    }
  }

  private func days(in interval: (start: Date, end: Date)) -> [Date] {
    var result: [Date] = []
    var d = calendar.startOfDay(for: interval.start)
    let end = calendar.startOfDay(for: interval.end)
    while d <= end {
      result.append(d)
      guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
      d = next
    }
    return result
  }

  private func monthStart(_ date: Date) -> Date {
    calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
  }

  private func months(in interval: (start: Date, end: Date)) -> [Date] {
    var result: [Date] = []
    var m = monthStart(interval.start)
    let last = monthStart(interval.end)
    while m <= last {
      result.append(m)
      guard let next = calendar.date(byAdding: .month, value: 1, to: m) else { break }
      m = next
    }
    return result
  }

  /// "yyyy-MM-dd" 文字列を Date へ（formatLogDate と対）
  private static let logDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private static func parseLogDate(_ string: String) -> Date? {
    logDateFormatter.date(from: string)
  }

  /// 取得範囲の種類が変わったときだけ再フェッチ（週/月/年は同じ"wide"扱い）
  private var taskID: String {
    periodType == .custom
      ? "custom-\(LogItemDTO.formatLogDate(loadInterval.start))-\(LogItemDTO.formatLogDate(loadInterval.end))"
      : "wide"
  }

  // MARK: - 集計（トレンドグラフ＝全取得分 / カード＝表示中ウィンドウ）

  private var totalsByDate: [String: NutritionValues] {
    Dictionary(grouping: items, by: { $0.logDate })
      .mapValues { dayItems in
        dayItems.reduce(NutritionValues.zero) { $0 + $1.nutritionValues }
      }
  }

  /// 月初日をキーにした月別集計（年表示のトレンド用）
  private var totalsByMonth: [Date: NutritionValues] {
    var dict: [Date: NutritionValues] = [:]
    for item in items {
      guard let d = StatisticsView.parseLogDate(item.logDate) else { continue }
      let key = monthStart(d)
      dict[key] = (dict[key] ?? .zero) + item.nutritionValues
    }
    return dict
  }

  /// トレンドグラフ用の系列（取得範囲全体。記録のない期間は0）。
  /// 年は月次、それ以外は日次で集計する。
  private var trendPoints: [StatsDayPoint] {
    if barUnit == .month {
      let totals = totalsByMonth
      return months(in: loadInterval).map { m in
        StatsDayPoint(date: m, values: totals[m] ?? .zero)
      }
    } else {
      let totals = totalsByDate
      return days(in: loadInterval).map { day in
        StatsDayPoint(date: day, values: totals[LogItemDTO.formatLogDate(day)] ?? .zero)
      }
    }
  }

  /// 表示中ウィンドウ内のログ
  private var visibleItems: [LogItemDTO] {
    let from = LogItemDTO.formatLogDate(visibleInterval.start)
    let to = LogItemDTO.formatLogDate(visibleInterval.end)
    return items.filter { $0.logDate >= from && $0.logDate <= to }
  }

  private var visibleTotalsByDate: [String: NutritionValues] {
    Dictionary(grouping: visibleItems, by: { $0.logDate })
      .mapValues { dayItems in
        dayItems.reduce(NutritionValues.zero) { $0 + $1.nutritionValues }
      }
  }

  private var periodTotal: NutritionValues {
    visibleItems.reduce(NutritionValues.zero) { $0 + $1.nutritionValues }
  }

  /// 記録があった日数（1件以上ログがある日）
  private var recordedDayCount: Int { visibleTotalsByDate.count }

  private var average: NutritionValues {
    let n = Double(recordedDayCount)
    guard n > 0 else { return .zero }
    let t = periodTotal
    return NutritionValues(
      calories: t.calories / n, netCarbs: t.netCarbs / n,
      dietaryFiber: t.dietaryFiber / n, fat: t.fat / n, protein: t.protein / n)
  }

  /// カロリー目標以内だった記録日数
  private var daysOnTarget: Int {
    let target = nutritionGoalsManager.targetCalories
    guard target > 0 else { return 0 }
    return visibleTotalsByDate.values.filter { $0.calories > 0 && $0.calories <= target }.count
  }

  private var mealTypeTotals: [(type: MealType, values: NutritionValues)] {
    MealType.allCases.map { mealType in
      let v = visibleItems.filter { $0.mealType == mealType }
        .reduce(NutritionValues.zero) { $0 + $1.nutritionValues }
      return (mealType, v)
    }
  }

  // MARK: - Body

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        periodSelector

        if items.isEmpty && !isLoading {
          emptyState
        } else {
          trendCard
          averageCard
          pfcBalanceCard
          mealTypeCard
        }
      }
      .padding(.vertical)
    }
    .background(Color(UIColor.systemGroupedBackground))
    .navigationTitle(NSLocalizedString("Statistics", comment: "Statistics tab"))
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if isLoading && items.isEmpty {
        ProgressView()
      }
    }
    .task(id: taskID) {
      await load()
    }
    .refreshable {
      await load()
    }
    .onChange(of: periodType) { _, _ in
      scrollToRecentWindow()
    }
    .onChange(of: scrollPosition) { _, _ in
      Task { await loadOlderIfNeeded() }
    }
    .onAppear {
      scrollToRecentWindow()
    }
  }

  /// 直近のウィンドウ（最新日が今日になる位置）へスクロール位置を合わせる
  private func scrollToRecentWindow() {
    guard periodType != .custom else { return }
    scrollPosition = calendar.date(
      byAdding: .day, value: -(visibleSpanDays - 1), to: referenceDate)!
  }

  // MARK: - 期間セレクタ

  @ViewBuilder
  private var periodSelector: some View {
    VStack(spacing: 12) {
      Picker("", selection: $periodType) {
        ForEach(StatsPeriodType.allCases) { type in
          Text(type.localizedName).tag(type)
        }
      }
      .pickerStyle(.segmented)

      if periodType == .custom {
        HStack {
          DatePicker(
            NSLocalizedString("From", comment: "Range start"),
            selection: $customStart, displayedComponents: .date
          )
          DatePicker(
            NSLocalizedString("To", comment: "Range end"),
            selection: $customEnd, displayedComponents: .date
          )
        }
        .font(.caption)
      } else {
        HStack {
          Button {
            shiftWindow(forward: false)
          } label: {
            Image(systemName: "chevron.left")
          }
          Spacer()
          Text(periodLabel)
            .font(.subheadline.weight(.medium))
          Spacer()
          Button {
            shiftWindow(forward: true)
          } label: {
            Image(systemName: "chevron.right")
          }
          .disabled(isAtLatestWindow)
        }
      }
    }
    .padding()
    .background(Color(UIColor.systemBackground))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    .padding(.horizontal)
  }

  private var periodLabel: String {
    let f = DateFormatter()
    f.dateFormat = "M/d"
    return "\(f.string(from: visibleInterval.start)) - \(f.string(from: visibleInterval.end))"
  }

  /// 表示可能な最新ウィンドウの先頭日
  private var latestWindowStart: Date {
    calendar.date(byAdding: .day, value: -(visibleSpanDays - 1), to: loadInterval.end)!
  }

  private var isAtLatestWindow: Bool {
    calendar.startOfDay(for: scrollPosition) >= calendar.startOfDay(for: latestWindowStart)
  }

  /// チェブロンで1ウィンドウ分スクロール（取得範囲内にクランプ）
  private func shiftWindow(forward: Bool) {
    let delta = (forward ? 1 : -1) * visibleSpanDays
    guard let shifted = calendar.date(byAdding: .day, value: delta, to: scrollPosition) else {
      return
    }
    let clamped = min(max(shifted, loadInterval.start), latestWindowStart)
    withAnimation { scrollPosition = clamped }
  }

  // MARK: - 空状態

  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "chart.bar.xaxis")
        .font(.system(size: 40))
        .foregroundColor(.secondary)
      Text(NSLocalizedString("No records in this period", comment: "Empty statistics"))
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }

  // MARK: - トレンドカード

  @ViewBuilder
  private var trendCard: some View {
    statsCard(title: NSLocalizedString("Trend", comment: "Statistics section")) {
      Picker("", selection: $trendMetric) {
        ForEach(TrendMetric.allCases) { metric in
          Text(metric.localizedName).tag(metric)
        }
      }
      .pickerStyle(.segmented)
      .padding(.bottom, 4)

      if periodType == .custom {
        // カスタムは範囲全体を一画面に表示（スクロールなし）
        trendChart
          .frame(height: 200)
      } else {
        // 週/月は横スクロールで期間を移動（ヘルスケア風）
        trendChart
          .chartScrollableAxes(.horizontal)
          .chartXVisibleDomain(length: domainSeconds)
          .chartScrollPosition(x: $scrollPosition)
          .chartScrollTargetBehavior(.paging)
          .frame(height: 200)
      }
    }
  }

  private var trendChart: some View {
    let goal = trendGoal
    return Chart {
      ForEach(trendPoints) { point in
        BarMark(
          x: .value("Date", point.date, unit: barUnit),
          y: .value("Value", trendMetric.value(point.values))
        )
        .foregroundStyle(trendMetric.color.gradient)
      }
      // 年（月次集計）の目標ラインは月合計の概算（1日目標×30）
      if goal > 0 {
        RuleMark(y: .value("Goal", barUnit == .month ? goal * 30 : goal))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
          .foregroundStyle(.secondary)
      }
    }
    .chartXAxis {
      if barUnit == .month {
        AxisMarks(values: .stride(by: .month, count: 2)) { _ in
          AxisGridLine()
          AxisValueLabel(format: .dateTime.year(.twoDigits).month(.narrow))
        }
      } else {
        AxisMarks(values: .stride(by: .day, count: xAxisStride)) { _ in
          AxisGridLine()
          AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
        }
      }
    }
  }

  private var trendGoal: Double {
    switch trendMetric {
    case .calories: return nutritionGoalsManager.targetCalories
    case .protein: return nutritionGoalsManager.targetProtein
    case .fat: return nutritionGoalsManager.targetFat
    case .carbs: return nutritionGoalsManager.targetNetCarbs + nutritionGoalsManager.targetFiber
    }
  }

  private var xAxisStride: Int {
    switch periodType {
    case .week: return 1
    case .month: return 5
    case .year: return 1
    case .custom:
      let count = days(in: loadInterval).count
      if count <= 8 { return 1 }
      if count <= 16 { return 2 }
      return max(count / 8, 1)
    }
  }

  // MARK: - 平均・達成率カード

  @ViewBuilder
  private var averageCard: some View {
    statsCard(title: NSLocalizedString("Daily Average", comment: "Statistics section")) {
      HStack(spacing: 16) {
        CalorieRingView(
          calories: average.calories,
          targetCalories: nutritionGoalsManager.targetCalories
        )
        VStack(spacing: 8) {
          MacroBarView(
            label: NSLocalizedString("Protein", comment: "Nutrient label"),
            value: average.protein, maxValue: nutritionGoalsManager.targetProtein,
            color: .blue, icon: "p.circle.fill")
          MacroBarView(
            label: NSLocalizedString("Fat", comment: "Nutrient label"),
            value: average.fat, maxValue: nutritionGoalsManager.targetFat,
            color: .yellow, icon: "f.circle.fill")
          MacroBarView(
            label: NSLocalizedString("Sugar", comment: "Nutrient label"),
            value: average.netCarbs, maxValue: nutritionGoalsManager.targetNetCarbs,
            color: .green, icon: "s.circle.fill")
          MacroBarView(
            label: NSLocalizedString("Dietary Fiber", comment: "Nutrient label"),
            value: average.dietaryFiber, maxValue: nutritionGoalsManager.targetFiber,
            color: .brown, icon: "leaf.circle.fill")
        }
      }

      Divider()

      HStack {
        Label(
          NSLocalizedString("Days on Target", comment: "Statistics metric"),
          systemImage: "checkmark.circle.fill"
        )
        .font(.subheadline)
        .foregroundColor(.green)
        Spacer()
        Text(
          String(
            format: NSLocalizedString("%d / %d days", comment: "Days on target / recorded days"),
            daysOnTarget, recordedDayCount)
        )
        .font(.subheadline.weight(.semibold))
      }
    }
  }

  // MARK: - PFCバランスカード

  @ViewBuilder
  private var pfcBalanceCard: some View {
    let p = periodTotal.protein * 4
    let f = periodTotal.fat * 9
    let c = periodTotal.carbs * 4
    let total = p + f + c

    statsCard(title: NSLocalizedString("PFC Balance", comment: "Statistics section")) {
      if total > 0 {
        let segments: [(label: String, value: Double, color: Color)] = [
          (NSLocalizedString("Protein", comment: "Nutrient label"), p, .blue),
          (NSLocalizedString("Fat", comment: "Nutrient label"), f, .yellow),
          (NSLocalizedString("Carbs (Sugar + Fiber)", comment: "Nutrient label"), c, .green),
        ]
        HStack(spacing: 20) {
          Chart(segments, id: \.label) { seg in
            SectorMark(
              angle: .value("Energy", seg.value),
              innerRadius: .ratio(0.6),
              angularInset: 1.5
            )
            .foregroundStyle(seg.color)
          }
          .frame(width: 120, height: 120)

          VStack(alignment: .leading, spacing: 8) {
            ForEach(segments, id: \.label) { seg in
              HStack(spacing: 6) {
                Circle().fill(seg.color).frame(width: 8, height: 8)
                Text(seg.label)
                  .font(.caption)
                  .foregroundColor(.secondary)
                Spacer()
                Text("\(Int((seg.value / total * 100).rounded()))%")
                  .font(.subheadline.weight(.semibold))
              }
            }
          }
        }
      } else {
        Text(NSLocalizedString("No records in this period", comment: "Empty statistics"))
          .font(.subheadline)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 20)
      }
    }
  }

  // MARK: - 食事タイプ別カード

  @ViewBuilder
  private var mealTypeCard: some View {
    let totals = mealTypeTotals.filter { $0.values.calories > 0 }
    let maxCalories = totals.map { $0.values.calories }.max() ?? 0

    statsCard(title: NSLocalizedString("By Meal Type", comment: "Statistics section")) {
      VStack(spacing: 14) {
        // 期間全体の合計
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            Image(systemName: "sum")
              .font(.system(size: 14))
              .foregroundColor(.primary)
              .frame(width: 20)
            Text(NSLocalizedString("Total", comment: "Period total"))
              .font(.subheadline.weight(.bold))
            Spacer()
            Text("\(NutritionFormatter.formatNutrition(periodTotal.calories))")
              .font(.subheadline.weight(.bold))
              + Text(" kcal")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          HStack(spacing: 6) {
            MacroChip(label: "P", value: periodTotal.protein, color: .blue)
            MacroChip(label: "F", value: periodTotal.fat, color: .yellow)
            MacroChip(label: "S", value: periodTotal.netCarbs, color: .green)
            MacroChip(label: "Fb", value: periodTotal.dietaryFiber, color: .brown)
          }
        }

        Divider()

        ForEach(totals, id: \.type) { entry in
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
              Image(systemName: entry.type.iconName)
                .font(.system(size: 14))
                .foregroundColor(entry.type.accentColor)
                .frame(width: 20)
              Text(entry.type.localizedName)
                .font(.subheadline.weight(.medium))
              Spacer()
              Text("\(NutritionFormatter.formatNutrition(entry.values.calories))")
                .font(.subheadline.weight(.semibold))
                + Text(" kcal")
                .font(.caption)
                .foregroundColor(.secondary)
            }

            GeometryReader { geo in
              ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                  .fill(entry.type.accentColor.opacity(0.12))
                  .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                  .fill(entry.type.accentColor)
                  .frame(
                    width: maxCalories > 0
                      ? geo.size.width * (entry.values.calories / maxCalories) : 0,
                    height: 6)
              }
            }
            .frame(height: 6)

            HStack(spacing: 6) {
              MacroChip(label: "P", value: entry.values.protein, color: .blue)
              MacroChip(label: "F", value: entry.values.fat, color: .yellow)
              MacroChip(label: "S", value: entry.values.netCarbs, color: .green)
              MacroChip(label: "Fb", value: entry.values.dietaryFiber, color: .brown)
            }
          }
        }
      }
    }
  }

  // MARK: - 共通カード

  @ViewBuilder
  private func statsCard<Content: View>(
    title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)
      content()
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(UIColor.systemBackground))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    .padding(.horizontal)
  }

  // MARK: - データ取得

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      if periodType == .custom {
        items = try await APIClient.shared.fetchLogItems(
          from: LogItemDTO.formatLogDate(loadInterval.start),
          to: LogItemDTO.formatLogDate(loadInterval.end))
      } else {
        let start = calendar.date(byAdding: .day, value: -initialSpanDays, to: referenceDate)!
        items = try await APIClient.shared.fetchLogItems(
          from: LogItemDTO.formatLogDate(start),
          to: LogItemDTO.formatLogDate(referenceDate))
        loadedStart = start
      }
    } catch {
      print("StatisticsView load error: \(error)")
    }
  }

  /// スクロールで取得済みの端に近づいたら、さらに過去を1年分追加取得する。
  /// 既存データは保持したまま追記し、スクロール位置は維持される。
  /// @MainActor で直列化し、同じ範囲の二重取得（重複集計）を防ぐ。
  @MainActor
  private func loadOlderIfNeeded() async {
    guard periodType != .custom, !isLoadingMore else { return }
    // 表示ウィンドウの先頭が、取得済み開始から1ウィンドウ分以内に来たら先読み
    let threshold = calendar.date(byAdding: .day, value: visibleSpanDays, to: loadedStart)!
    guard calendar.startOfDay(for: scrollPosition) <= threshold else { return }
    // 際限ない取得を避けるため最大10年で打ち切り
    let earliest = calendar.date(byAdding: .year, value: -10, to: referenceDate)!
    guard loadedStart > earliest else { return }

    isLoadingMore = true
    defer { isLoadingMore = false }
    let newStart = calendar.date(byAdding: .day, value: -chunkDays, to: loadedStart)!
    let chunkEnd = calendar.date(byAdding: .day, value: -1, to: loadedStart)!
    do {
      let older = try await APIClient.shared.fetchLogItems(
        from: LogItemDTO.formatLogDate(newStart),
        to: LogItemDTO.formatLogDate(chunkEnd))
      items.append(contentsOf: older)
      loadedStart = newStart
    } catch {
      print("StatisticsView loadOlder error: \(error)")
    }
  }
}
