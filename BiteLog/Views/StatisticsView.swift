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

  // 読み込み済みバッファ（[bufferFrom, bufferTo]）
  @State private var items: [LogItemDTO] = []
  @State private var bufferFrom: Date = Date()
  @State private var bufferTo: Date = Date()
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var loadFailed = false

  // グラフのスクロール位置（可視範囲の左端）
  @State private var scrollX: Date = Date()

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

  /// 現在グラフに見えている期間 [from, to]（両端の日付）。各カードの集計対象。
  private var visibleRange: (from: Date, to: Date) {
    let from = cal.startOfDay(for: scrollX)
    let to = cal.date(byAdding: .day, value: visibleDays - 1, to: from) ?? from
    return (from, to)
  }

  private var visibleItems: [LogItemDTO] {
    let fromStr = StatDate.string(visibleRange.from)
    let toStr = StatDate.string(visibleRange.to)
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
    let text = "\(f.string(from: visibleRange.from)) – \(f.string(from: visibleRange.to))"
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

        trendChart
      }
    }
  }

  private var trendSeries: [DailyNutrition] {
    StatisticsCalculator.dailyTotals(items)
  }

  @ViewBuilder
  private var trendChart: some View {
    let series = trendSeries
    let goalLine = metric == .calories ? nutritionGoalsManager.targetCalories : nil

    Chart {
      ForEach(series) { day in
        if let date = StatDate.date(day.date) {
          LineMark(
            x: .value("Date", date, unit: .day),
            y: .value(metric.localizedName, metric.value(day.values))
          )
          .foregroundStyle(metric.color)
          .interpolationMethod(.catmullRom)

          PointMark(
            x: .value("Date", date, unit: .day),
            y: .value(metric.localizedName, metric.value(day.values))
          )
          .foregroundStyle(metric.color)
          .symbolSize(28)
        }
      }
      if let goalLine {
        RuleMark(y: .value("Goal", goalLine))
          .foregroundStyle(.secondary.opacity(0.6))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
      }
    }
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
    .onChange(of: scrollX) { _, _ in
      Task { await loadMoreIfNeeded() }
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
    let avg = StatisticsCalculator.dailyAverage(visibleItems, dayCount: visibleDays)
    let achieved = StatisticsCalculator.goalAchievedDays(
      visibleItems, targetCalories: nutritionGoalsManager.targetCalories)

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
    let balance = StatisticsCalculator.pfcBalance(visibleItems)

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
    let total = StatisticsCalculator.periodTotal(visibleItems)
    let totals = StatisticsCalculator.mealTypeTotals(visibleItems)
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
      let fetched = try await APIClient.shared.fetchLogItems(
        from: StatDate.string(from), to: StatDate.string(to))
      items = fetched
      bufferFrom = from
      bufferTo = to
      // 最新の可視期間を表示（左端＝to - (visibleDays-1)）
      scrollX = cal.date(byAdding: .day, value: -(visibleDays - 1), to: to) ?? to
      isLoading = false
    } catch {
      loadFailed = true
      isLoading = false
    }
  }

  /// 左端がバッファ先頭に近づいたら過去側を追加取得（無限スクロール）。custom では拡張しない。
  private func loadMoreIfNeeded() async {
    guard period != .custom, !isLoadingMore, AuthManager.shared.isSignedIn else { return }
    // 可視左端がバッファ先頭から visibleDays 以内なら拡張
    let threshold = cal.date(byAdding: .day, value: visibleDays, to: bufferFrom) ?? bufferFrom
    guard cal.startOfDay(for: scrollX) <= threshold else { return }

    isLoadingMore = true
    let newFrom = cal.date(byAdding: .day, value: -(visibleDays * 3), to: bufferFrom) ?? bufferFrom
    let oldFromMinus1 = cal.date(byAdding: .day, value: -1, to: bufferFrom) ?? bufferFrom
    do {
      let older = try await APIClient.shared.fetchLogItems(
        from: StatDate.string(newFrom), to: StatDate.string(oldFromMinus1))
      // 重複排除して前方に結合
      let existingIDs = Set(items.map(\.id))
      items = older.filter { !existingIDs.contains($0.id) } + items
      bufferFrom = newFrom
    } catch {
      // 追加取得の失敗は致命的でないため握りつぶす（次のスクロールで再試行）
    }
    isLoadingMore = false
  }
}
