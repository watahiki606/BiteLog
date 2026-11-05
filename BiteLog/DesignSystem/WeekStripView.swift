import SwiftUI

/// 選んでいる日を含む1週間を並べ、日ごとの摂取カロリーを目標に対するリングで示す。
///
/// 前後の矢印で1日ずつ動かすだけだと、今週どの日を記録したかは1日ずつ開かないと
/// 分からない。7日を並べてリングを付ければ、日付を選ぶ操作と週の振り返りが1つで済む。
struct WeekStripView: View {
  let selectedDate: Date
  /// "yyyy-MM-dd" をキーにした、その日の摂取カロリー。
  let caloriesByDate: [String: Double]
  let targetCalories: Double
  let onSelect: (Date) -> Void

  @Environment(\.locale) private var locale

  private var calendar: Calendar { .current }
  private var days: [Date] { Self.days(containing: selectedDate, calendar: calendar) }
  private var today: Date { calendar.startOfDay(for: Date()) }

  /// 次の週へ進めるか。今日より先の週には記録が無い。
  private var canGoForward: Bool {
    guard let last = days.last else { return false }
    return last < today
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(days, id: \.self) { day in
        dayCell(day)
          .frame(maxWidth: .infinity)
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    // 縦のスクロールを奪わないよう、横に大きく動いたときだけ週を移す
    .simultaneousGesture(
      DragGesture(minimumDistance: 24).onEnded { value in
        let dx = value.translation.width
        guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 2 else { return }
        shiftWeek(by: dx < 0 ? 1 : -1)
      }
    )
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: Text(NSLocalizedString("Previous week", comment: "Week strip"))) {
      shiftWeek(by: -1)
    }
    .accessibilityAction(named: Text(NSLocalizedString("Next week", comment: "Week strip"))) {
      shiftWeek(by: 1)
    }
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

  /// 同じ曜日のまま週を移す。今日より先には進めない。
  private func shiftWeek(by weeks: Int) {
    if weeks > 0 && !canGoForward { return }
    guard let shifted = calendar.date(byAdding: .weekOfYear, value: weeks, to: selectedDate)
    else { return }
    onSelect(min(shifted, today))
  }

  /// `date` を含む週の7日。週の始まりは端末の暦の設定に従う。
  static func days(containing date: Date, calendar: Calendar = .current) -> [Date] {
    guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
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
      if isSelected {
        Circle().fill(Color.accentColor.opacity(contrast == .increased ? 0.3 : 0.18))
      }

      Circle()
        .stroke(Color.secondary.opacity(contrast == .increased ? 0.4 : 0.2), lineWidth: lineWidth)

      Circle()
        .trim(from: 0, to: min(ratio, 1))
        .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))

      Text(weekday)
        .font(.subheadline.weight(isSelected ? .bold : .medium))
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .padding(lineWidth + 2)
    }
    .frame(width: diameter, height: diameter)
  }
}
