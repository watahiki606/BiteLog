import SwiftUI

/// 選んでいる日を含む1週間を並べ、日ごとの摂取カロリーを目標に対するリングで示す。
///
/// 前後の矢印で1日ずつ動かすだけだと、今週どの日を記録したかは1日ずつ開かないと
/// 分からない。7日を並べてリングを付ければ、日付を選ぶ操作と週の振り返りが1つで済む。
///
/// 週は横にページをめくって移る。
struct WeekStripView: View {
  let selectedDate: Date
  /// "yyyy-MM-dd" をキーにした、その日の摂取カロリー。
  let caloriesByDate: [String: Double]
  let targetCalories: Double
  let onSelect: (Date) -> Void

  /// 画面に出ているページ。指に合わせて途中でも変わるので、選んでいる日とは分けて持つ。
  @State private var visiblePage: Int?

  private var calendar: Calendar { .current }
  private var today: Date { calendar.startOfDay(for: Date()) }
  private var selectedPage: Int { Self.page(containing: selectedDate, calendar: calendar) }
  private var currentPage: Int { Self.page(containing: today, calendar: calendar) }

  var body: some View {
    let pages = Self.pages(selected: selectedDate, today: today, calendar: calendar)

    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        LazyHStack(spacing: 0) {
          ForEach(pages, id: \.self) { page in
            WeekRowView(
              days: Self.days(onPage: page, calendar: calendar),
              selectedDate: selectedDate,
              caloriesByDate: caloriesByDate,
              targetCalories: targetCalories,
              onSelect: onSelect
            )
            .containerRelativeFrame(.horizontal)
            // 読み上げは今の週の7日だけをたどる。週の移動は下の操作で行う
            .accessibilityHidden(page != selectedPage)
            .id(page)
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.paging)
      // scrollPosition(id:) は使わない。指で動かしている間に値が変わると、それが
      // スクロールの指示として返ってきて、指を離したときに位置が飛び、1回で2週進む
      .onScrollGeometryChange(for: Int.self) { geometry in
        Int((geometry.contentOffset.x / max(geometry.containerSize.width, 1)).rounded())
      } action: { _, offset in
        visiblePage = pages.lowerBound + offset
      }
      // 指が離れて止まるまで日を変えない。途中で変えると下の記録が読み直されて動きが乱れる。
      // 動いていたものが止まったときだけ見る。作られた直後の位置を指で選んだ週と取り違えない
      .onScrollPhaseChange { oldPhase, newPhase in
        if oldPhase != .idle && newPhase == .idle { selectVisiblePage() }
      }
      // 暦や今日へ戻る操作で別の週を選んだら、そのページを出す
      .onChange(of: selectedPage) { _, page in
        proxy.scrollTo(page)
      }
      .onAppear {
        proxy.scrollTo(selectedPage)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: Text(NSLocalizedString("Previous week", comment: "Week strip"))) {
      moveToPage(selectedPage - 1)
    }
    .accessibilityAction(named: Text(NSLocalizedString("Next week", comment: "Week strip"))) {
      moveToPage(selectedPage + 1)
    }
  }

  private func selectVisiblePage() {
    guard let visiblePage, visiblePage != selectedPage else { return }
    moveToPage(visiblePage)
  }

  private func moveToPage(_ page: Int) {
    guard page <= currentPage else { return }
    onSelect(Self.date(movingFrom: selectedDate, toPage: page, today: today, calendar: calendar))
  }

  // MARK: - ページの計算

  /// ページ番号を数え始める日。今週を基準にすると、週が変わったときに番号の指す週がずれる。
  private static let pageOrigin = Date(timeIntervalSinceReferenceDate: 0)

  private static func firstDay(ofWeekContaining date: Date, calendar: Calendar) -> Date {
    calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
  }

  /// `date` を含む週のページ番号。
  ///
  /// 週の先頭の日付をそのまま識別子にすると、並べる週の配列を描画のたびに作ることになる。
  /// 番号なら範囲だけで済み、画面に出す週の日付だけを計算すればよい。
  static func page(containing date: Date, calendar: Calendar = .current) -> Int {
    let origin = firstDay(ofWeekContaining: pageOrigin, calendar: calendar)
    let week = firstDay(ofWeekContaining: date, calendar: calendar)
    return calendar.dateComponents([.weekOfYear], from: origin, to: week).weekOfYear ?? 0
  }

  /// めくれるページの範囲。暦からはいくらでも過去を選べるので、選んだ週までは必ず含める。
  /// 今週より先には記録が無いので、最後は今週で止める。
  static func pages(
    selected: Date, today: Date, calendar: Calendar = .current
  ) -> ClosedRange<Int> {
    let selectedPage = page(containing: selected, calendar: calendar)
    let currentPage = page(containing: today, calendar: calendar)
    return min(0, selectedPage)...currentPage
  }

  /// `page` の週の7日。
  static func days(onPage page: Int, calendar: Calendar = .current) -> [Date] {
    let origin = firstDay(ofWeekContaining: pageOrigin, calendar: calendar)
    guard let week = calendar.date(byAdding: .weekOfYear, value: page, to: origin) else {
      return []
    }
    return days(containing: week, calendar: calendar)
  }

  /// 同じ曜日のまま `page` の週へ移した日。今日より先には進めない。
  static func date(
    movingFrom selected: Date, toPage page: Int, today: Date, calendar: Calendar = .current
  ) -> Date {
    let weeks = page - self.page(containing: selected, calendar: calendar)
    guard let moved = calendar.date(byAdding: .weekOfYear, value: weeks, to: selected) else {
      return selected
    }
    return min(moved, today)
  }

  /// `date` を含む週の7日。週の始まりは端末の暦の設定に従う。
  static func days(containing date: Date, calendar: Calendar = .current) -> [Date] {
    guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
  }
}

/// 1週間ぶんのリングの列。
struct WeekRowView: View {
  let days: [Date]
  let selectedDate: Date
  let caloriesByDate: [String: Double]
  let targetCalories: Double
  let onSelect: (Date) -> Void

  @Environment(\.locale) private var locale

  private var calendar: Calendar { .current }
  private var today: Date { calendar.startOfDay(for: Date()) }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(days, id: \.self) { day in
        dayCell(day)
          .frame(maxWidth: .infinity)
      }
    }
    .padding(.vertical, 4)
  }

  private func dayCell(_ day: Date) -> some View {
    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
    let isToday = calendar.isDate(day, inSameDayAs: today)
    let isFuture = day > today
    let calories = caloriesByDate[LogItemDTO.formatLogDate(day)] ?? 0

    return Button {
      onSelect(day)
    } label: {
      VStack(spacing: 4) {
        DayRing(
          weekday: weekdaySymbol(for: day), calories: calories, targetCalories: targetCalories,
          isSelected: isSelected)

        Text(day.formatted(.dateTime.day().locale(locale)))
          .font(.caption.weight(isToday ? .bold : .regular))
          .monospacedDigit()
          .foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isFuture)
    .opacity(isFuture ? 0.35 : 1)
    .accessibilityLabel(day.formatted(.dateTime.month().day().weekday(.wide).locale(locale)))
    .accessibilityValue(Nutrient.calories.accessibilityLabel(for: calories))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func weekdaySymbol(for day: Date) -> String {
    var cal = calendar
    cal.locale = locale
    let index = cal.component(.weekday, from: day) - 1
    return cal.veryShortStandaloneWeekdaySymbols[index]
  }
}

/// 曜日を囲むリング。目標に対する摂取カロリーを円弧で示す。
private struct DayRing: View {
  let weekday: String
  let calories: Double
  let targetCalories: Double
  let isSelected: Bool

  @Environment(\.colorSchemeContrast) private var contrast
  @ScaledMetric(relativeTo: .subheadline) private var scaledDiameter: CGFloat = 40

  /// 7つ並べるので、文字を大きくしても画面の幅に収まるところで止める。
  private var diameter: CGFloat { min(scaledDiameter, 46) }
  private let lineWidth: CGFloat = 4

  private var ratio: Double { targetCalories > 0 ? calories / targetCalories : 0 }
  private var ringColor: Color { ratio > 1 ? .red : Nutrient.calories.color }

  var body: some View {
    ZStack {
      // 円弧と色が重なると進み具合が読めなくなるので、すき間を空けて内側を塗る
      if isSelected {
        Circle()
          .fill(.tint)
          .padding(lineWidth / 2 + 2)
      }

      Circle()
        .stroke(Color.secondary.opacity(contrast == .increased ? 0.4 : 0.2), lineWidth: lineWidth)

      Circle()
        .trim(from: 0, to: min(ratio, 1))
        .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))

      Text(weekday)
        .font(.subheadline.weight(isSelected ? .bold : .medium))
        // 地の色はダークモードで明るくなるので、白に固定せず画面の背景色を抜き色にする
        .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .padding(lineWidth + 2)
    }
    .frame(width: diameter, height: diameter)
    .animation(.easeOut(duration: 0.15), value: isSelected)
  }
}
