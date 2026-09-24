import SwiftUI

/// タブの識別子。数値インデックスだと「1 はどの画面か」が呼び出し側から読めないため型で持つ。
enum AppTab: Hashable {
  case log
  case food
  case statistics
}

struct ContentView: View {
  @EnvironmentObject private var languageManager: LanguageManager

  @State private var selectedDate = Date()
  @State private var showingAddItemFor: (date: Date, mealType: MealType)?
  @State private var showingSettings = false
  @State private var showingDatePicker = false
  @State private var selectedTab: AppTab = .log
  @State private var logRefreshTrigger = 0
  @State private var dragOffset: CGFloat = 0

  var body: some View {
    TabView(selection: tabSelection) {
      Tab(NSLocalizedString("Log", comment: "Log"), systemImage: "book", value: AppTab.log) {
        logTab
      }

      Tab(
        NSLocalizedString("Food", comment: "Food"), systemImage: "list.bullet.clipboard",
        value: AppTab.food
      ) {
        NavigationStack {
          FoodMasterManagementView()
        }
      }

      Tab(
        NSLocalizedString("Statistics", comment: "Tab name"), systemImage: "chart.xyaxis.line",
        value: AppTab.statistics
      ) {
        NavigationStack {
          StatisticsView()
        }
      }
    }
  }

  /// 選択中のログタブをもう一度タップしたら今日に戻す。
  /// タブバー自作をやめた代わりに、この挙動だけ Binding の set 側で拾う。
  private var tabSelection: Binding<AppTab> {
    Binding(
      get: { selectedTab },
      set: { newValue in
        if newValue == .log && selectedTab == .log {
          selectedDate = Calendar.current.startOfDay(for: Date())
          logRefreshTrigger += 1
        }
        selectedTab = newValue
      }
    )
  }

  // MARK: - ログタブ

  private var logTab: some View {
    NavigationStack {
      DayContentView(
        date: selectedDate,
        selectedDate: selectedDate,
        onAddTapped: { date, mealType in
          showingAddItemFor = (date, mealType)
        },
        refreshTrigger: logRefreshTrigger
      )
      .navigationTitle(DateLabel.title(for: selectedDate, locale: languageManager.locale))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          DateNavigationBar(
            selectedDate: $selectedDate,
            locale: languageManager.locale,
            onPickDate: { showingDatePicker = true }
          )
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showingSettings = true
          } label: {
            Label(
              NSLocalizedString("Settings", comment: "Settings"), systemImage: "gearshape")
          }
        }
      }
      .offset(x: dragOffset)
      .gesture(
        DateSwipeGesture(
          dragOffset: $dragOffset,
          onDateChange: { goForward in
            selectedDate = selectedDate.addingTimeInterval(goForward ? 86400 : -86400)
          }
        )
      )
      .sheet(
        isPresented: Binding(
          get: { showingAddItemFor != nil },
          set: { if !$0 { showingAddItemFor = nil } }
        ),
        onDismiss: { logRefreshTrigger += 1 }
      ) {
        if let itemInfo = showingAddItemFor {
          AddItemView(
            preselectedMealType: itemInfo.mealType,
            selectedDate: itemInfo.date,
            selectedTab: $selectedTab
          )
          .presentationDetents([.medium, .large])
        }
      }
      .sheet(isPresented: $showingDatePicker) {
        DatePickerSheet(selectedDate: $selectedDate, isPresented: $showingDatePicker)
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
    }
  }
}

/// ツールバー中央の日付ナビゲーション。
///
/// 前後の矢印は以前 Image そのままでタップ領域が 44pt に満たなかった。
/// 日付は「今日」「昨日」と曜日付きの表記にして、いつを見ているかを一目で分かるようにする。
struct DateNavigationBar: View {
  @Binding var selectedDate: Date
  let locale: Locale
  let onPickDate: () -> Void

  private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

  var body: some View {
    HStack(spacing: 0) {
      Button {
        shift(by: -1)
      } label: {
        Image(systemName: "chevron.left")
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(NSLocalizedString("Previous day", comment: "Date navigation"))

      Button(action: onPickDate) {
        Text(DateLabel.title(for: selectedDate, locale: locale))
          .font(.headline)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(NSLocalizedString("Select Date", comment: "Date picker title"))
      .accessibilityValue(DateLabel.title(for: selectedDate, locale: locale))

      Button {
        shift(by: 1)
      } label: {
        Image(systemName: "chevron.right")
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(NSLocalizedString("Next day", comment: "Date navigation"))
      .disabled(isToday)
    }
  }

  private func shift(by days: Int) {
    guard let shifted = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else {
      return
    }
    selectedDate = shifted
  }
}

/// 日付をユーザーが位置を把握できる形にする。
enum DateLabel {
  /// 今日・昨日は相対表記、それ以外は曜日付き。
  /// 「2026年9月24日」だけでは何曜日の記録かが分からず、食事記録では位置を見失いやすい。
  static func title(for date: Date, locale: Locale) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
      return NSLocalizedString("Today", comment: "Relative date")
    }
    if calendar.isDateInYesterday(date) {
      return NSLocalizedString("Yesterday", comment: "Relative date")
    }

    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate(
      calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMMdEEE" : "yMMMdEEE")
    return formatter.string(from: date)
  }
}

/// ログ1件の行。
struct ItemRowView: View {
  let item: LogItemDTO
  var onUpdate: ((LogItemDTO) -> Void)?
  @State private var showingEditSheet = false

  var body: some View {
    FoodRow(
      title: FoodRow.displayName(brand: item.brandName, product: item.productName),
      subtitle: FoodRow.amountText(item.numberOfServings, unit: item.portionUnit),
      values: item.nutritionValues,
      isDeleted: item.isMasterDeleted
    )
    .contentShape(Rectangle())
    .onTapGesture { showingEditSheet = true }
    .accessibilityAddTraits(.isButton)
    .sheet(isPresented: $showingEditSheet) {
      EditItemView(item: item, onSaved: onUpdate)
    }
  }
}

#Preview {
  ContentView()
}

// 空の食事セクション
struct EmptyMealView: View {
  let mealType: MealType
  let onAddTap: () -> Void

  var body: some View {
    Button(action: onAddTap) {
      HStack {
        Image(systemName: "plus")
          .font(.body)
          .foregroundColor(.accentColor)

        Text(
          String(
            format: NSLocalizedString("Add %@", comment: "Add meal type"), mealType.localizedName)
        )
        .font(.subheadline)
        .foregroundColor(.primary.opacity(0.8))
      }
      .frame(maxWidth: .infinity)
      .padding()
      .background(Color(UIColor.systemBackground))
      .cornerRadius(6)
    }
    .buttonStyle(PlainButtonStyle())
    .padding(.horizontal)
  }
}
// 日付選択シート
struct DatePickerSheet: View {
  @Binding var selectedDate: Date
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      VStack {
        DatePicker(
          NSLocalizedString("Select Date", comment: "Date picker title"),
          selection: $selectedDate,
          displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .padding()
      }
      .navigationTitle(NSLocalizedString("Select Date", comment: "Date picker title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Done", comment: "Button title")) {
            isPresented = false
          }
        }
      }
    }
    .presentationDetents([.medium])
  }
}

// MARK: - Date Swipe Gesture

class HorizontalPanGestureRecognizer: UIPanGestureRecognizer {
  private var isDirectionDetermined = false

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    guard let touch = touches.first, let rootView = self.view else { return }
    let location = touch.location(in: rootView)
    if isLocationInTableView(location, in: rootView) {
      state = .failed
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesMoved(touches, with: event)
    guard !isDirectionDetermined else { return }
    let t = translation(in: view)
    if abs(t.x) > 8 || abs(t.y) > 8 {
      isDirectionDetermined = true
      if abs(t.y) >= abs(t.x) { state = .failed }
    }
  }

  override func reset() {
    super.reset()
    isDirectionDetermined = false
  }

  private func isLocationInTableView(_ location: CGPoint, in rootView: UIView) -> Bool {
    var hitView: UIView? = rootView.hitTest(location, with: nil)
    while let v = hitView {
      if v is UICollectionView { return true }
      hitView = v.superview
    }
    return false
  }
}

struct DateSwipeGesture: UIGestureRecognizerRepresentable {
  @Binding var dragOffset: CGFloat
  var onDateChange: (Bool) -> Void

  func makeUIGestureRecognizer(context: Context) -> HorizontalPanGestureRecognizer {
    let recognizer = HorizontalPanGestureRecognizer()
    recognizer.delegate = context.coordinator
    return recognizer
  }

  func handleUIGestureRecognizerAction(_ recognizer: HorizontalPanGestureRecognizer, context: Context) {
    let translation = recognizer.translation(in: recognizer.view)
    let velocity = recognizer.velocity(in: recognizer.view)

    switch recognizer.state {
    case .changed:
      dragOffset = translation.x
    case .ended:
      let h = translation.x
      let screenWidth = UIScreen.main.bounds.width
      if abs(h) > 50 || abs(velocity.x) > 500 {
        let goForward = h < 0
        let exitOffset: CGFloat = goForward ? -screenWidth : screenWidth
        withAnimation(.easeInOut(duration: 0.2)) { dragOffset = exitOffset }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          onDateChange(goForward)
          dragOffset = -exitOffset
          withAnimation(.easeInOut(duration: 0.2)) { dragOffset = 0 }
        }
      } else {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
      }
    case .cancelled, .failed:
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
    default:
      break
    }
  }

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

  class Coordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
      !isFromTableView(other)
    }

    private func isFromTableView(_ recognizer: UIGestureRecognizer) -> Bool {
      var view: UIView? = recognizer.view
      while let v = view {
        if v is UICollectionView { return true }
        view = v.superview
      }
      return false
    }
  }
}
