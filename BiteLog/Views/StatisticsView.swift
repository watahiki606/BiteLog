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

/// 統計のタブ。
///
/// 以前はグラフの上に、期間・指標・集計単位・平均か合計か・重ねる体組成の切り替えが
/// 最大6つ並び、グラフより操作部品が目立っていた。下の4つの集計も切り替えで隠れていた。
/// 切り替えは期間と指標の2つに絞り、集計は縦に並べてスクロールすれば全部見えるようにする。
struct StatisticsView: View {
  @EnvironmentObject private var nutritionGoalsManager: NutritionGoalsManager
  @EnvironmentObject private var languageManager: LanguageManager
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var period: StatPeriod = .week
  @State private var metric: TrendMetric = .calories
  @State private var bodyMeasurements: [BodyMeasurementDTO] = []

  /// 同じ日に何度も乗った日は、朝いちばんを代表にする。記録の画面と同じ
  private let bodyPick: DailyPick = .first

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

  /// グラフの1点が表す期間。期間から決める。
  ///
  /// 選ばせていた頃は、年で日ごとを選ぶと365本の線が潰れ、週で月ごとを選ぶと1点しか
  /// 出ないなど、意味の無い組み合わせが作れた。期間ごとに読みやすい単位を1つに決める。
  private var bucket: StatBucket {
    switch period {
    case .week, .month: return .day
    case .year: return .week
    case .custom: return visibleDays <= 62 ? .day : .week
    }
  }

  /// トレンドグラフに描く系列。週ごとにまとめるときは1日あたりの平均にする。
  /// 合計にすると目標の線と比べられない。
  private var displayTrendSeries: [DailyNutrition] {
    guard let component = bucket.component else { return trendSeries }
    return StatisticsCalculator.bucketed(
      trendSeries, by: component, average: true, calendar: cal)
  }

  /// 目標の線。カロリーのときだけ引く。
  private var trendGoalLine: Double? {
    metric == .calories ? nutritionGoalsManager.targetCalories : nil
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

  private var settledAverage: NutritionValues {
    StatisticsCalculator.dailyAverage(settledItems, dayCount: visibleDays)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        PeriodSelector(selection: $period)

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

          // 上のカードの「1日平均」と同じ言葉だと、同じものが2回出ているように見える
          sectionTitle(NSLocalizedString("Nutrients per Day", comment: "Statistics section"))
          nutrientAverageCard

          sectionTitle(NSLocalizedString("PFC Balance", comment: "Statistics section"))
          pfcBalanceCard

          sectionTitle(NSLocalizedString("By Meal Type", comment: "Statistics section"))
          mealTypeCard

          if hasBodyData {
            sectionTitle(
              NSLocalizedString("Change over this period", comment: "Body composition section"))
            bodyChangeCard
          }
        }
      }
      .padding(.horizontal)
      .padding(.bottom, 24)
    }
    .background(Color(UIColor.systemGroupedBackground))
    .navigationTitle(NSLocalizedString("Statistics", comment: "Tab name"))
    .navigationBarTitleDisplayMode(.large)
    .task(id: reloadKey) { await reload() }
  }

  /// カードの上に置く見出し。記録の画面の食事の見出しと同じ太さにそろえる
  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.title3.weight(.bold))
      .padding(.top, 16)
      .padding(.leading, 4)
      .accessibilityAddTraits(.isHeader)
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
    // 「2026/10/30 – 2026/11/05」は長く、年はほとんどの場合わかっている。
    // 今年なら月日だけにする
    let sameYear = cal.isDate(settledRange.from, equalTo: Date(), toGranularity: .year)
      && cal.isDate(settledRange.to, equalTo: Date(), toGranularity: .year)
    let style: Date.FormatStyle =
      sameYear
      ? .dateTime.month(.defaultDigits).day().locale(languageManager.locale)
      : .dateTime.year().month(.defaultDigits).day().locale(languageManager.locale)
    let text = "\(settledRange.from.formatted(style)) – \(settledRange.to.formatted(style))"
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
        .font(.headline)
        .monospacedDigit()
        // 期間の表示は画面の位置を示す補助。最大まで大きくすると
        // 折り返して前後の矢印を画面の端へ押しやる。
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .multilineTextAlignment(.center)
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

  private var hasBodyData: Bool { BodyCorrelation.hasBodyData(bodyMeasurements) }

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

  // MARK: - 期間の推移

  /// 選んだ指標の1日平均を大きく出し、その下に推移のグラフを置く。
  private var trendCard: some View {
    let average = metric.value(settledAverage)
    let achieved = StatisticsCalculator.goalAchievedDays(
      settledItems, targetCalories: nutritionGoalsManager.targetCalories)

    return CardView {
      VStack(alignment: .leading, spacing: 16) {
        MetricSelector(selection: $metric)

        VStack(alignment: .leading, spacing: 4) {
          Text(NSLocalizedString("Daily Average", comment: "Statistics section"))
            .font(.subheadline)
            .foregroundStyle(.secondary)

          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(metric.nutrient.format(average))
              .font(.system(.largeTitle, design: .rounded, weight: .bold))
              .monospacedDigit()
              .foregroundStyle(
                metric == .calories && average > nutritionGoalsManager.targetCalories * 1.1
                  ? Color.red : Color.primary)
            Text(metric.unit)
              .font(.title3)
              .foregroundStyle(.secondary)
          }

          // 目標の線と達成日数はカロリーにしか無い
          if metric == .calories {
            Text(
              String(
                format: NSLocalizedString(
                  "Goal %@ kcal · On target %d of %d days", comment: "Statistics calorie summary"),
                NutritionFormatter.formatCalories(nutritionGoalsManager.targetCalories),
                achieved, visibleDays)
            )
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .combine)

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

  /// カードが見ている期間に入る測定だけ。
  ///
  /// バッファには可視期間の外まで入っている。そのまま使うと、期間を変えても
  /// 「この期間の変化」が動かない。
  private var settledBodyMeasurements: [BodyMeasurementDTO] {
    BodyMeasurementDTO.within(
      bodyMeasurements, from: StatDate.string(settledRange.from),
      to: StatDate.string(settledRange.to))
  }

  // MARK: - 体組成の期間変化

  /// 期間の始めから終わりまでの変化。
  ///
  /// いまいくつかは出さない。最新の値は期間を変えても動かないので、
  /// 「この期間の変化」と書いた場所に置くと期間に連動していないように見える。
  /// いまの値は記録の画面にある。
  private var bodyChangeCard: some View {
    let deltas = BodyCorrelation.deltas(settledBodyMeasurements, pick: bodyPick)
    return CardView {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(deltas) { delta in
          bodyChangeRow(delta)
          if delta.id != deltas.last?.id { Divider() }
        }
      }
    }
  }

  private func bodyChangeRow(_ delta: BodyCorrelation.Delta) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(delta.metric.localizedName)
        .font(.body.weight(.semibold))
      Spacer()
      if let change = delta.change {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(signedChange(change, digits: delta.metric.fractionDigits))
            .font(.system(.title3, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(bodyChangeColor(delta.metric, change))
          if !delta.metric.unit.isEmpty {
            Text(delta.metric.unit)
              .font(.footnote)
              .foregroundColor(.secondary)
          }
        }
      } else {
        // 期間内に測った日が1日以下。0 と書くと「変わらなかった」に読める
        Text("–")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// 良し悪しが決まる項目だけ色を付ける。
  /// 体重の増減は目標次第で良くも悪くもなるので、色を付けない。
  private func bodyChangeColor(_ metric: BodyMetric, _ change: Double) -> Color {
    guard change != 0, let increaseIsGood = metric.increaseIsGood else { return .primary }
    return (change > 0) == increaseIsGood ? .green : .orange
  }

  /// 増減の向きが一目で分かる形にする。マイナス記号は全角の −
  private func signedChange(_ value: Double, digits: Int) -> String {
    let scale = pow(10, Double(digits))
    let rounded = (value * scale).rounded() / scale
    let sign = rounded > 0 ? "+" : rounded < 0 ? "−" : "±"
    return sign + String(format: "%.\(digits)f", abs(rounded))
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
    let base: Int
    switch period {
    case .week: base = 1
    case .month: base = 5
    case .year: base = 1
    case .custom: base = max(visibleDays / 6, 1)
    }
    // 大きな文字では日付1つぶんの幅が広がり、目盛りが切れて読めない。
    // 本数を間引いて1つずつを読める幅にする。
    return dynamicTypeSize.isAccessibilitySize ? base * 3 : base
  }

  // MARK: - 栄養素の1日平均

  /// 主要3栄養素の1日平均を、目標に対するバーで並べる。カロリーは上の推移のカードに出す
  private var nutrientAverageCard: some View {
    let avg = settledAverage
    return CardView {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 12) {
          NutrientBar(
            nutrient: .protein, value: avg.protein, target: nutritionGoalsManager.targetProtein)
          NutrientBar(nutrient: .fat, value: avg.fat, target: nutritionGoalsManager.targetFat)
          NutrientBar(
            nutrient: .netCarbs, value: avg.netCarbs, target: nutritionGoalsManager.targetNetCarbs)
        }
      } else {
        HStack(alignment: .top, spacing: 16) {
          NutrientBar(
            nutrient: .protein, value: avg.protein, target: nutritionGoalsManager.targetProtein,
            isCompact: true)
          NutrientBar(
            nutrient: .fat, value: avg.fat, target: nutritionGoalsManager.targetFat,
            isCompact: true)
          NutrientBar(
            nutrient: .netCarbs, value: avg.netCarbs,
            target: nutritionGoalsManager.targetNetCarbs, isCompact: true)
        }
      }
    }
  }

  // MARK: - PFCバランス

  private var pfcBalanceCard: some View {
    let balance = StatisticsCalculator.pfcBalance(settledItems)
    // 色と名前は Nutrient を唯一の出典にする。ここで直書きすると、
    // 同じ栄養素がこの画面だけ別の色になる。
    let segments: [(nutrient: Nutrient, percent: Double)] = [
      (.protein, balance.protein), (.fat, balance.fat), (.carbs, balance.carbs),
    ]

    return CardView {
      VStack(spacing: 16) {
        GeometryReader { geo in
          // 区切りを隙間で表す。色だけで境目を示すと、色を区別しない設定で
          // どこまでが何の割合なのか分からなくなる。
          HStack(spacing: 3) {
            ForEach(segments, id: \.nutrient) { segment in
              Capsule()
                .fill(segment.nutrient.color)
                .frame(width: max(geo.size.width * segment.percent / 100 - 3, 0))
            }
          }
        }
        .frame(height: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("PFC Balance", comment: "Statistics section"))
        .accessibilityValue(
          segments
            .map { "\($0.nutrient.localizedName) \(Int($0.percent.rounded()))%" }
            .joined(separator: ", "))

        HStack(alignment: .top, spacing: 12) {
          ForEach(segments, id: \.nutrient) { segment in
            pfcLegend(segment.nutrient, segment.percent)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }

  private func pfcLegend(_ nutrient: Nutrient, _ pct: Double) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Image(systemName: nutrient.symbolName)
          .foregroundStyle(nutrient.color)
          .accessibilityHidden(true)
        Text(nutrient.localizedName)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .font(.caption)

      HStack(alignment: .firstTextBaseline, spacing: 1) {
        Text("\(Int(pct.rounded()))")
          .font(.system(.title2, design: .rounded, weight: .bold))
          .monospacedDigit()
        Text("%")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: - 食事タイプ別内訳

  private var mealTypeCard: some View {
    let total = StatisticsCalculator.periodTotal(settledItems)
    let totals = StatisticsCalculator.mealTypeTotals(settledItems)
    let rows: [(type: MealType, values: NutritionValues)] = MealType.allCases.compactMap { type in
      guard let v = totals[type] else { return nil }
      return (type, v)
    }
    let maxCal = rows.map { $0.values.calories }.max() ?? 0

    return CardView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .firstTextBaseline) {
          Text(NSLocalizedString("Period Total", comment: "Statistics metric"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer()
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(NutritionFormatter.formatCalories(total.calories))
              .font(.system(.title3, design: .rounded, weight: .bold))
              .monospacedDigit()
            Text(Nutrient.calories.unit)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

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
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Image(systemName: type.iconName)
          .foregroundStyle(type.accentColor)
          .accessibilityHidden(true)
        Text(type.localizedName)
          .font(.body.weight(.semibold))
        Spacer()
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(NutritionFormatter.formatCalories(values.calories))
            .font(.system(.body, design: .rounded, weight: .bold))
            .monospacedDigit()
          Text(Nutrient.calories.unit)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      GeometryReader { geo in
        Capsule()
          .fill(type.accentColor.opacity(0.15))
          .overlay(alignment: .leading) {
            Capsule()
              .fill(type.accentColor)
              .frame(width: maxCal > 0 ? geo.size.width * values.calories / maxCal : 0)
          }
      }
      .frame(height: 8)
      // 棒が示すカロリーは同じ行に数値で出ているので、読み上げでは重ねない。
      .accessibilityHidden(true)
      NutrientIconRow(values: values)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: - データ読み込み

  /// 期間切替時の全リセット＆初回取得。最新側が見えるようスクロール位置を合わせる。
  private func reload() async {
    guard AuthManager.shared.isSignedIn else {
      items = []
      bodyMeasurements = []
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
      // 体組成は日次に潰されたものではなく1回ずつ受け取る。
      // 同じ日に何度も乗るので、平均にすると乗った回数で日ごとの値が変わる。
      async let summary = APIClient.shared.fetchDailySummary(
        from: StatDate.string(from), to: StatDate.string(to))
      async let body = APIClient.shared.fetchBodyMeasurements(
        from: StatDate.string(from), to: StatDate.string(to))
      let (fetched, fetchedBody) = try await (summary, body)
      items = fetched
      bodyMeasurements = fetchedBody
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
      async let summary = APIClient.shared.fetchDailySummary(
        from: StatDate.string(newFrom), to: StatDate.string(oldFromMinus1))
      async let body = APIClient.shared.fetchBodyMeasurements(
        from: StatDate.string(newFrom), to: StatDate.string(oldFromMinus1))
      let (older, olderBody) = try await (summary, body)
      // 重複排除して前方に結合
      let existingIDs = Set(items.map(\.id))
      items = older.filter { !existingIDs.contains($0.id) } + items
      trendSeries = StatisticsCalculator.dailyTotals(items)
      let existingBodyIDs = Set(bodyMeasurements.map(\.id))
      bodyMeasurements = olderBody.filter { !existingBodyIDs.contains($0.id) } + bodyMeasurements
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
    series: [DailyNutrition],
    xDomain: ClosedRange<Date>, metric: TrendMetric,
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

  /// 「10/30」のように数字だけにする。「10月30日」は1週間を並べると幅が足りず「10月…」と切れる
  private var axisLabelFormat: Date.FormatStyle {
    switch bucket {
    case .day, .week: return .dateTime.month(.defaultDigits).day()
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
    // 半透明の材質だと下の折れ線の色を拾って濁る。カードの上に重ねる面と
    // 同じ階層の不透明な地を敷く。
    .background(
      Color(UIColor.tertiarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(.quaternary, lineWidth: 0.5)
    }
  }

  /// 棒が届く高さ。目標の線が枠の上端に貼り付かないよう、少し余裕を持たせる
  private var plotMax: Double {
    let seriesMax = series.map { metric.value($0.values) }.max() ?? 0
    return max(max(seriesMax, goalLine ?? 0) * 1.1, 1)
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

        // 吹き出しは点に付ける。縦線に付けると描画領域の外側に置かれて消える。
        PointMark(
          x: .value("Date", selected.date, unit: barUnit),
          y: .value(metric.localizedName, selected.value)
        )
        .foregroundStyle(metric.color)
        .symbolSize(90)
        .annotation(
          position: .top, spacing: 6,
          overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
        ) {
          selectionCallout(selected)
        }
      }
    }
    .chartYScale(domain: 0...plotMax)
    .chartYAxis {
      AxisMarks(position: .leading)
    }
    .chartXSelection(value: $selectedX)
    // 横スクロールできるグラフでは標準のタップ選択がスクロールに吸われて
    // 何も起きない。タップを明示的に選択へつなぐ。
    .chartGesture { proxy in
      SpatialTapGesture()
        .onEnded { value in proxy.selectXValue(at: value.location.x) }
    }
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
    .frame(height: 200)
    // 軸ラベルだけは文字サイズの追随に上限を置く。際限なく大きくすると
    // 目盛りが互いに重なり、グラフの幅の半分を数字が占めて線が読めなくなる。
    // カードの中の数値は従来どおり最大まで大きくなる。
    .dynamicTypeSize(...DynamicTypeSize.xLarge)
    .onChange(of: scrollX) { _, x in
      // 選んだ点が画面外へ流れたまま吹き出しだけ残らないようにする。
      selectedX = nil
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
