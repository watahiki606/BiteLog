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

  /// 表示名・色・単位は `Nutrient` を唯一の出典にする。
  var nutrient: Nutrient {
    switch self {
    case .calories: return .calories
    case .protein: return .protein
    case .fat: return .fat
    case .carbs: return .carbs
    }
  }

  var localizedName: String { nutrient.localizedName }

  var color: Color { nutrient.color }

  var unit: String { nutrient.unit }

  func value(_ v: NutritionValues) -> Double { nutrient.value(of: v) }
}

/// トレンドの下でセグメント切替する詳細セクション。選択中のカードのみ描画する。
enum StatSection: String, CaseIterable, Identifiable {
  case average, pfc, mealType
  var id: String { rawValue }

  var localizedName: String {
    switch self {
    case .average: return NSLocalizedString("Daily Average", comment: "Statistics section")
    case .pfc: return NSLocalizedString("PFC Balance", comment: "Statistics section")
    case .mealType: return NSLocalizedString("By Meal Type", comment: "Statistics section")
    }
  }
}

/// トレンドグラフの集計単位（X軸の1点が表す期間）。
/// 年単位は複数年を映す期間が無く棒が1本になるため一旦持たない。
enum StatBucket: String, CaseIterable, Identifiable {
  case day, week, month
  var id: String { rawValue }

  var localizedName: String {
    switch self {
    case .day: return NSLocalizedString("Day", comment: "Trend bucket")
    case .week: return NSLocalizedString("Week", comment: "Statistics period")
    case .month: return NSLocalizedString("Month", comment: "Statistics period")
    }
  }

  /// グルーピングに使う暦単位。`.day` は集計せず日次のまま表示するため nil。
  var component: Calendar.Component? {
    switch self {
    case .day: return nil
    case .week: return .weekOfYear
    case .month: return .month
    }
  }
}

/// バケット内の集計方法。
enum StatAggregation: String, CaseIterable, Identifiable {
  case average, total
  var id: String { rawValue }

  var localizedName: String {
    switch self {
    case .average: return NSLocalizedString("Average", comment: "Aggregation")
    case .total: return NSLocalizedString("Total", comment: "Aggregation")
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
  @State private var section: StatSection = .average
  @State private var bucket: StatBucket = .day
  @State private var aggregation: StatAggregation = .total

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

  /// period に対して意味のある集計単位だけを出す（棒が1本しか出ない組み合わせを避ける）。
  private var availableBuckets: [StatBucket] {
    switch period {
    case .week: return [.day]
    case .month: return [.day, .week]
    case .year: return [.day, .week, .month]
    case .custom:
      if visibleDays <= 31 { return [.day, .week] }
      return [.day, .week, .month]
    }
  }

  /// トレンドグラフに描く系列。日次（`trendSeries`）を選択中の単位/集計で丸め直す。
  private var displayTrendSeries: [DailyNutrition] {
    guard let component = bucket.component else { return trendSeries }
    return StatisticsCalculator.bucketed(
      trendSeries, by: component, average: aggregation == .average, calendar: cal)
  }

  /// カロリー目標線。合計バケットでは日次目標と比較できないため出さない。
  private var trendGoalLine: Double? {
    guard metric == .calories else { return nil }
    if bucket != .day && aggregation == .total { return nil }
    return nutritionGoalsManager.targetCalories
  }

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
      VStack(spacing: 10) {
        if period == .custom {
          customRangePicker
        }

        if isLoading {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if loadFailed {
          errorView
        } else {
          dateNavigationBar
          trendCard
          sectionSelector
          switch section {
          case .average: averageCard
          case .pfc: pfcBalanceCard
          case .mealType: mealTypeCard
          }
        }
      }
      .padding()
    }
    .background(Color(UIColor.systemGroupedBackground))
    .navigationTitle(NSLocalizedString("Statistics", comment: "Tab name"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      // 期間・指標・セクションのセグメントが縦に3段重なるとグラフより操作部品が
      // 目立つので、期間だけツールバーに逃がす。
      ToolbarItem(placement: .topBarTrailing) {
        // Picker をそのまま置くとナビゲーションバー幅いっぱいに伸びるので Menu に包む。
        Menu {
          Picker(NSLocalizedString("Period", comment: "Statistics period"), selection: $period) {
            ForEach(StatPeriod.allCases) { p in
              Text(p.localizedName).tag(p)
            }
          }
        } label: {
          // systemImage を付けるとツールバーではアイコンだけになり、
          // 今どの期間を見ているのかが分からなくなるので文字だけにする。
          Text(period.localizedName)
        }
        .accessibilityLabel(NSLocalizedString("Period", comment: "Statistics period"))
      }
    }
    .task(id: reloadKey) { await reload() }
    .onChange(of: period) { _, _ in
      // period を変えると使えない単位が出るので、対象外なら日次に戻す。
      if !availableBuckets.contains(bucket) { bucket = .day }
    }
  }

  // task(id:) が変わったら全リセット＆再取得
  private var reloadKey: String {
    "\(period.rawValue)-\(StatDate.string(customFrom))-\(StatDate.string(customTo))"
  }

  // MARK: - 期間セレクタ

  private var customRangePicker: some View {
    HStack {
      DatePicker(
        NSLocalizedString("From", comment: "Custom period start"),
        selection: $customFrom, in: ...customTo, displayedComponents: .date
      )
      .labelsHidden()

      Text("–").foregroundStyle(.secondary)

      DatePicker(
        NSLocalizedString("To", comment: "Custom period end"),
        selection: $customTo, in: customFrom...Date(), displayedComponents: .date
      )
      .labelsHidden()
    }
    .frame(maxWidth: .infinity)
  }

  /// 期間ラベルの両サイドに前後ページ送りの矢印を備えたナビゲーションバー。
  private var dateNavigationBar: some View {
    let f = DateFormatter()
    f.locale = languageManager.locale
    f.dateStyle = .medium
    f.timeStyle = .none
    let text = "\(f.string(from: settledRange.from)) – \(f.string(from: settledRange.to))"
    // 進む側は最新の可視期間（左端が today-(visibleDays-1)）に達したら無効化
    let latestFrom = cal.date(
      byAdding: .day, value: -(visibleDays - 1), to: cal.startOfDay(for: Date())) ?? Date()
    let atLatest = settledRange.from >= latestFrom

    return HStack {
      Button { page(by: -visibleDays) } label: {
        Image(systemName: "chevron.left")
          .font(.body.weight(.semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .disabled(period == .custom)
      .accessibilityLabel(NSLocalizedString("Previous period", comment: "Statistics paging"))

      Spacer()
      Text(text)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
      Spacer()

      Button { page(by: visibleDays) } label: {
        Image(systemName: "chevron.right")
          .font(.body.weight(.semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .disabled(period == .custom || atLatest)
      .accessibilityLabel(NSLocalizedString("Next period", comment: "Statistics paging"))
    }
    .frame(maxWidth: .infinity)
  }

  /// 表示するセクションを選ぶセグメント。選択中のカードだけを描画する。
  private var sectionSelector: some View {
    Picker("", selection: $section) {
      ForEach(StatSection.allCases) { s in
        Text(s.localizedName).tag(s)
      }
    }
    .pickerStyle(.segmented)
  }

  /// 可視期間を deltaDays 分ずらす。進む側は今日を超えないようクランプし、
  /// 戻る側は既存の無限スクロール機構でバッファを拡張する。custom は固定範囲のため無効。
  private func page(by deltaDays: Int) {
    guard period != .custom else { return }
    let candidate = cal.date(byAdding: .day, value: deltaDays, to: settledScrollX) ?? settledScrollX
    let latestFrom = cal.date(
      byAdding: .day, value: -(visibleDays - 1), to: cal.startOfDay(for: Date())) ?? Date()
    settledScrollX = min(cal.startOfDay(for: candidate), latestFrom)
    if shouldLoadMore(at: settledScrollX) {
      Task { await loadMoreIfNeeded() }
    }
  }

  private var errorView: some View {
    VStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
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
    CardView {
      VStack(alignment: .leading, spacing: 10) {
        Picker("", selection: $metric) {
          ForEach(TrendMetric.allCases) { m in
            Text(m.localizedName).tag(m)
          }
        }
        .pickerStyle(.segmented)

        // 選択肢が1つしかないときのセグメントは選べるものが無く場所を取るだけなので出さない。
        HStack(spacing: 8) {
          if availableBuckets.count > 1 {
            Picker("", selection: $bucket) {
              ForEach(availableBuckets) { b in
                Text(b.localizedName).tag(b)
              }
            }
            .pickerStyle(.segmented)
          }

          if bucket != .day {
            Picker("", selection: $aggregation) {
              ForEach(StatAggregation.allCases) { a in
                Text(a.localizedName).tag(a)
              }
            }
            .pickerStyle(.segmented)
            .fixedSize()
          }
        }

        TrendChartView(
          series: displayTrendSeries,
          xDomain: trendDomain,
          metric: metric,
          bucket: bucket,
          visibleDays: visibleDays,
          visibleSeconds: visibleSeconds,
          goalLine: trendGoalLine,
          xAxisStride: xAxisStride,
          initialScrollX: settledScrollX,
          scrollTarget: settledScrollX,
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

  /// グラフの X 軸が覆う範囲。取得済みバッファの全体を明示的に指定する。
  ///
  /// 指定しないとドメインが実データの範囲から決まるため、直近の日に記録が無いと
  /// グラフがその日まで進めず、上の期間ラベルと軸の日付がずれる。
  private var trendDomain: ClosedRange<Date> {
    let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: bufferTo))
      ?? bufferTo
    let start = min(cal.startOfDay(for: bufferFrom), end)
    return start...end
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

    return CardView {
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
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
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
          NutrientBar(
            nutrient: .protein, value: avg.protein,
            target: nutritionGoalsManager.targetProtein)
          NutrientBar(
            nutrient: .fat, value: avg.fat,
            target: nutritionGoalsManager.targetFat)
          NutrientBar(
            nutrient: .carbs, value: avg.carbs,
            target: nutritionGoalsManager.targetNetCarbs + nutritionGoalsManager.targetFiber)
        }
      }
    }
  }

  // MARK: - ③ PFCバランス

  private var pfcBalanceCard: some View {
    let balance = StatisticsCalculator.pfcBalance(settledItems)
    // 色と名前は Nutrient を唯一の出典にする。ここで直書きすると、
    // 同じ栄養素がこの画面だけ別の色になる。
    let segments: [(nutrient: Nutrient, percent: Double)] = [
      (.protein, balance.protein), (.fat, balance.fat), (.carbs, balance.carbs),
    ]

    return CardView {
      VStack(spacing: 12) {
        GeometryReader { geo in
          // 区切りを隙間で表す。色だけで境目を示すと、色を区別しない設定で
          // どこまでが何の割合なのか分からなくなる。
          HStack(spacing: 2) {
            ForEach(segments, id: \.nutrient) { segment in
              RoundedRectangle(cornerRadius: 3)
                .fill(segment.nutrient.color)
                .frame(width: max(geo.size.width * segment.percent / 100 - 2, 0))
            }
          }
        }
        .frame(height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("PFC Balance", comment: "Statistics section"))
        .accessibilityValue(
          segments
            .map { "\($0.nutrient.localizedName) \(Int($0.percent.rounded()))%" }
            .joined(separator: ", "))

        HStack(spacing: 16) {
          ForEach(segments, id: \.nutrient) { segment in
            pfcLegend(segment.nutrient, segment.percent)
          }
        }
      }
    }
  }

  private func pfcLegend(_ nutrient: Nutrient, _ pct: Double) -> some View {
    HStack(spacing: 4) {
      Circle().fill(nutrient.color).frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(nutrient.localizedName).font(.caption).foregroundColor(.secondary)
      Text("\(pct, specifier: "%.0f")%").font(.caption.weight(.semibold)).monospacedDigit()
    }
    .accessibilityElement(children: .combine)
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

    return CardView {
      VStack(alignment: .leading, spacing: 16) {
        // 期間合計（ラベルと数値を1行に）
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(NSLocalizedString("Period Total", comment: "Statistics metric"))
              .font(.caption).foregroundColor(.secondary)
            Spacer()
            CalorieLabel(calories: total.calories, textStyle: .title3)
          }
          HStack(spacing: 6) {
            NutrientChip(nutrient: .protein, value: total.protein)
            NutrientChip(nutrient: .fat, value: total.fat)
            NutrientChip(nutrient: .carbs, value: total.carbs)
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
          .font(.caption2)
          .foregroundStyle(type.accentColor)
          .accessibilityHidden(true)
        Text(type.localizedName)
          .font(.caption.weight(.medium))
        Spacer()
        CalorieLabel(calories: values.calories, textStyle: .caption)
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
      // 棒が示すカロリーは同じ行に数値で出ているので、読み上げでは重ねない。
      .accessibilityHidden(true)
      HStack(spacing: 6) {
        NutrientChip(nutrient: .protein, value: values.protein)
        NutrientChip(nutrient: .fat, value: values.fat)
        NutrientChip(nutrient: .carbs, value: values.carbs)
      }
    }
    .accessibilityElement(children: .combine)
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
private struct TrendChartView: View {
  let series: [DailyNutrition]
  let xDomain: ClosedRange<Date>
  let metric: TrendMetric
  let bucket: StatBucket
  let visibleDays: Int
  let visibleSeconds: TimeInterval
  let goalLine: Double?
  let xAxisStride: Int
  let initialScrollX: Date
  /// 矢印操作など外部からの一方向ジャンプ先。ライブスクロールには関与しない。
  let scrollTarget: Date
  let onScroll: (Date) -> Void
  let onScrollSettled: (Date) -> Void

  @State private var scrollX: Date
  @State private var settleTask: Task<Void, Never>?
  /// タップで選んだ位置。軸からの目測では特定の日の値が読めない。
  @State private var selectedX: Date?

  init(
    series: [DailyNutrition], xDomain: ClosedRange<Date>, metric: TrendMetric,
    bucket: StatBucket, visibleDays: Int,
    visibleSeconds: TimeInterval, goalLine: Double?, xAxisStride: Int, initialScrollX: Date,
    scrollTarget: Date, onScroll: @escaping (Date) -> Void, onScrollSettled: @escaping (Date) -> Void
  ) {
    self.series = series
    self.xDomain = xDomain
    self.metric = metric
    self.bucket = bucket
    self.visibleDays = visibleDays
    self.visibleSeconds = visibleSeconds
    self.goalLine = goalLine
    self.xAxisStride = xAxisStride
    self.initialScrollX = initialScrollX
    self.scrollTarget = scrollTarget
    self.onScroll = onScroll
    self.onScrollSettled = onScrollSettled
    _scrollX = State(initialValue: initialScrollX)
  }

  // 長期間（月/年）は点を省き直線補間にして描画コストを抑える。日次表示のみ対象。
  private var simplified: Bool { visibleDays > 60 }

  // 棒グラフの1本が占める暦単位。
  private var barUnit: Calendar.Component {
    switch bucket {
    case .day: return .day
    case .week: return .weekOfYear
    case .month: return .month
    }
  }

  private var axisStrideComponent: Calendar.Component {
    switch bucket {
    case .day: return visibleDays > 60 ? .month : .day
    case .week: return .weekOfYear
    case .month: return .month
    }
  }

  private var axisStrideCount: Int {
    switch bucket {
    case .day: return xAxisStride
    case .week: return max(visibleDays / 7 / 6, 1)
    case .month: return 1
    }
  }

  private var axisLabelFormat: Date.FormatStyle {
    switch bucket {
    case .day, .week: return .dateTime.month(.abbreviated).day()
    case .month: return .dateTime.month(.abbreviated)
    }
  }

  /// 選んだ位置にいちばん近い点。棒や折れ線の間をタップしても値を出せるようにする。
  private var selectedPoint: (date: Date, value: Double)? {
    guard let selectedX else { return nil }
    let points = series.compactMap { day -> (date: Date, value: Double)? in
      guard let date = StatDate.date(day.date) else { return nil }
      return (date, metric.value(day.values))
    }
    return points.min {
      abs($0.date.timeIntervalSince(selectedX)) < abs($1.date.timeIntervalSince(selectedX))
    }
  }

  private func selectionCallout(_ point: (date: Date, value: Double)) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(point.date, format: axisLabelFormat)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text("\(metric.nutrient.format(point.value))\(metric.unit)")
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(metric.color)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
  }

  var body: some View {
    Chart {
      ForEach(series) { day in
        if let date = StatDate.date(day.date) {
          if bucket == .day {
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
          } else {
            BarMark(
              x: .value("Date", date, unit: barUnit),
              y: .value(metric.localizedName, metric.value(day.values))
            )
            .foregroundStyle(metric.color)
          }
        }
      }
      if let goalLine {
        RuleMark(y: .value("Goal", goalLine))
          .foregroundStyle(.secondary.opacity(0.6))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
      }

      if let selected = selectedPoint {
        RuleMark(x: .value("Date", selected.date, unit: barUnit))
          .foregroundStyle(.secondary.opacity(0.4))
          .lineStyle(StrokeStyle(lineWidth: 1))
          .annotation(
            position: .top, spacing: 2,
            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
          ) {
            selectionCallout(selected)
          }
      }
    }
    .chartXSelection(value: $selectedX)
    .chartScrollableAxes(.horizontal)
    .chartXScale(domain: xDomain)
    .chartXVisibleDomain(length: visibleSeconds)
    .chartScrollPosition(x: $scrollX)
    .chartXAxis {
      AxisMarks(values: .stride(by: axisStrideComponent, count: axisStrideCount)) { _ in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: axisLabelFormat)
      }
    }
    .frame(height: 170)
    .onChange(of: scrollX) { _, x in
      onScroll(x)  // 同期・軽量（境界近傍のみ追加取得を起動）
      // デバウンス: 停止後にのみカード集計を更新する
      settleTask?.cancel()
      settleTask = Task {
        try? await Task.sleep(for: .milliseconds(150))
        if !Task.isCancelled { onScrollSettled(x) }
      }
    }
    .onChange(of: scrollTarget) { _, target in
      // 矢印操作など外部からのジャンプ。日単位で差があるときのみ反映し、
      // onScrollSettled 経由の帰還ループを防ぐ。
      let cal = Calendar.current
      if !cal.isDate(target, inSameDayAs: scrollX) {
        withAnimation { scrollX = target }
      }
    }
  }
}
