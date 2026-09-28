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

  @ViewBuilder
  var body: some View {
    if #available(iOS 26.0, *) {
      // 下へスクロールしている間はタブバーを畳み、内容に画面を明け渡す。
      tabView.tabBarMinimizeBehavior(.onScrollDown)
    } else {
      tabView
    }
  }

  private var tabView: some View {
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
  /// TabView は同じタブの再選択を通知しないので、Binding の set 側で拾う。
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
