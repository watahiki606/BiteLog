import SwiftUI

/// タブの識別子。数値インデックスだと「1 はどの画面か」が呼び出し側から読めないため型で持つ。
enum AppTab: String, Hashable {
  case log
  case food
  case statistics
  case profile

  /// 起動したときに開くタブ。
  ///
  /// 開発用のビルドでは `-BiteLogStartTab profile` を付けて起動すると、そのタブから始まる。
  /// 実機の画面を手で操作せずに撮って確かめるためで、公開する版では常に記録から始める。
  static var initial: AppTab {
    #if DEBUG
      if let raw = UserDefaults.standard.string(forKey: "BiteLogStartTab"),
        let tab = AppTab(rawValue: raw)
      {
        return tab
      }
    #endif
    return .log
  }
}

struct ContentView: View {
  @EnvironmentObject private var languageManager: LanguageManager

  @State private var selectedDate = Date()
  @State private var showingAddItemFor: (date: Date, mealType: MealType)?
  @State private var showingDatePicker = false
  @State private var selectedTab: AppTab = .initial
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

      Tab(
        NSLocalizedString("Profile", comment: "Tab name"), systemImage: "person.crop.circle",
        value: AppTab.profile
      ) {
        ProfileView()
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
        // プロフィールで体組成計を登録したり目標を変えたりして戻ってきたら、記録を読み直す。
        // 読み直さないと、次に日付を動かすまで体組成のカードや目標が古いまま
        if newValue == .log && selectedTab == .profile {
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
        refreshTrigger: logRefreshTrigger,
        onSelectDate: { selectedDate = $0 }
      )
      // 大きなタイトルで今見ている日を示し、スクロールしたら小さく畳む。
      // 日付の移動は記録の先頭にある週の帯で行う
      .navigationTitle(DateLabel.title(for: selectedDate, locale: languageManager.locale))
      .navigationBarTitleDisplayMode(.large)
      .dateSubtitle(DateLabel.subtitle(for: selectedDate, locale: languageManager.locale))
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          // 週の帯では離れた日へ行きにくいので、暦から選ぶ入口を残す
          Button {
            showingDatePicker = true
          } label: {
            Label(
              NSLocalizedString("Select Date", comment: "Date picker title"),
              systemImage: "calendar")
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
    }
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

  /// タイトルが「今日」「昨日」のときだけ、何月何日の何曜日かを添える。
  /// それ以外はタイトルに日付と曜日が入っているので重ねない。
  static func subtitle(for date: Date, locale: Locale) -> String? {
    let calendar = Calendar.current
    guard calendar.isDateInToday(date) || calendar.isDateInYesterday(date) else { return nil }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
    return formatter.string(from: date)
  }
}

extension View {
  /// ナビゲーションの副題。iOS 26 より前には副題の置き場所が無いので何もしない。
  @ViewBuilder
  fileprivate func dateSubtitle(_ subtitle: String?) -> some View {
    if #available(iOS 26.0, *), let subtitle {
      navigationSubtitle(subtitle)
    } else {
      self
    }
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
      isDeleted: item.isMasterDeleted,
      trailingText: FoodRow.timeText(item.timestamp)
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
