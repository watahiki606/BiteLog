import SwiftUI

struct DayContentView: View {
  let date: Date
  let selectedDate: Date
  let onAddTapped: (Date, MealType) -> Void
  var refreshTrigger: Int = 0
  var onSelectDate: (Date) -> Void = { _ in }

  @EnvironmentObject private var nutritionGoalsManager: NutritionGoalsManager
  @StateObject private var bodyComposition = BodyCompositionModel()

  @State private var dayLogItems: [LogItemDTO] = []
  @State private var isLoading = false
  /// 読み込めなかった状態。0件と区別する。同じ見た目で出すと、
  /// 記録が残っているのにもう一度記録し直す操作を誘発する。
  @State private var loadFailed = false
  @State private var failure: OperationFailure?
  @State private var editMode: EditMode = .inactive
  @State private var selectedItemIDs: Set<UUID> = []
  @State private var showsAllNutrients = false
  /// 週の帯に出す、日ごとの摂取カロリー。
  @State private var weekCalories: [String: Double] = [:]

  @State private var deleteAllTrigger = 0
  @State private var deletedCount = 0

  private var logDateString: String { LogItemDTO.formatLogDate(date) }
  private var taskID: String { "\(logDateString)-\(refreshTrigger)-\(deleteAllTrigger)" }
  private var weekDays: [Date] { WeekStripView.days(containing: date) }
  /// 同じ週の中で日を移っても読み直さない。週が変わったときと記録が変わったときだけ読む
  private var weekTaskID: String {
    "\(weekDays.first.map(LogItemDTO.formatLogDate) ?? "")-\(refreshTrigger)-\(deleteAllTrigger)"
  }

  var body: some View {
    Group {
      // 読み込めず手元に何も無いときだけ画面を差し替える。
      // 既に出せている内容があるなら残し、失敗はアラートで伝える。
      if loadFailed && dayLogItems.isEmpty {
        LoadFailureView { await loadLogItems() }
      } else {
        logList
      }
    }
    // スクロールしなくても届くよう、追加の入口を画面の左下に固定する。
    // 食事の種類は時刻から仮に選び、追加画面の上部で切り替えてもらう
    .overlay(alignment: .bottomLeading) {
      AddMealButton {
        onAddTapped(date, MealType.suggested())
      }
      .padding(.leading, 20)
      .padding(.bottom, 16)
    }
    // 広告はスクロール内容に混ぜず画面下端に固定する。
    // 高さは AdaptiveBannerView が幅に合わせて決めるので、ここで固定しない。
    // 固定すると画面幅によっては広告の下端が切れる。
    .safeAreaInset(edge: .bottom, spacing: 0) {
      AdaptiveBannerView()
        .frame(maxWidth: .infinity)
        // 地を画面の下端まで伸ばす。広告の高さぶんしか塗らないと、
        // 浮いたタブバーの裏で記録の行が見切れたまま残る。
        .background {
          Rectangle()
            .fill(.bar)
            .ignoresSafeArea(edges: .bottom)
        }
    }
    .operationFailureAlert($failure)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if !dayLogItems.isEmpty {
          EditButton()
            .environment(\.editMode, $editMode)
        }
      }
      ToolbarItem(placement: .topBarLeading) {
        if editMode == .active && !selectedItemIDs.isEmpty {
          Button(role: .destructive, action: deleteSelectedItems) {
            Label(
              String(
                format: NSLocalizedString("Delete %d items", comment: "Delete multiple items"),
                selectedItemIDs.count),
              systemImage: "trash"
            )
          }
          .tint(.red)
        }
      }
    }
    .onChange(of: editMode) { _, newValue in
      if newValue == .inactive { selectedItemIDs.removeAll() }
    }
    .task(id: taskID) {
      await loadLogItems()
    }
    .task(id: weekTaskID) {
      await loadWeekCalories()
    }
    // 記録の読み込みとは別に走らせる。体組成が取れなくても記録の表示は待たせない
    .task(id: taskID) {
      await bodyComposition.load(date: date)
    }
    .onDisappear {
      // 画面を離れたら探すのをやめる。つないだまま残すと Bluetooth を掴み続ける
      bodyComposition.stop()
    }
    .onReceive(NotificationCenter.default.publisher(for: .allDataDeleted)) { _ in
      dayLogItems = []
      deleteAllTrigger += 1
    }
  }

  private var logList: some View {
    List(selection: editMode == .active ? $selectedItemIDs : .constant(Set<UUID>())) {
      weekSection

      summarySection

      bodyCompositionSection

      ForEach(loggedMealTypes, id: \.self) { mealType in
        mealSection(for: mealType)
      }

      unloggedMealsSection
    }
    .listStyle(.insetGrouped)
    // 最後の行が左下の追加ボタンに隠れないよう、下に余白を足す
    .contentMargins(.bottom, 88, for: .scrollContent)
    .environment(\.editMode, $editMode)
    .refreshable {
      await loadLogItems()
    }
    .sensoryFeedback(.impact, trigger: deletedCount)
    .overlay {
      if isLoading && dayLogItems.isEmpty {
        ProgressView()
      }
    }
  }

  // MARK: - 週の帯

  private var weekSection: some View {
    Section {
      WeekStripView(
        selectedDate: date,
        caloriesByDate: weekCaloriesIncludingToday,
        targetCalories: nutritionGoalsManager.targetCalories,
        onSelect: onSelectDate
      )
      .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
      .listRowBackground(Color.clear)
    }
  }

  /// 表示中の日は、手元の記録から出した合計で上書きする。
  /// 週の集計は読み込んだ時点のものなので、この画面で消した記録が反映されない。
  private var weekCaloriesIncludingToday: [String: Double] {
    var merged = weekCalories
    if !dayLogItems.isEmpty || !isLoading {
      merged[logDateString] = dailyTotals.calories
    }
    return merged
  }

  // MARK: - 1日の合計

  private var summarySection: some View {
    Section {
      DailyTotalsView(
        totals: NutritionValues(
          calories: dailyTotals.calories, netCarbs: dailyTotals.netCarbs,
          dietaryFiber: dailyTotals.fiber, fat: dailyTotals.fat, protein: dailyTotals.protein),
        goals: NutritionGoalsTargets(
          calories: nutritionGoalsManager.targetCalories,
          protein: nutritionGoalsManager.targetProtein,
          fat: nutritionGoalsManager.targetFat,
          netCarbs: nutritionGoalsManager.targetNetCarbs,
          fiber: nutritionGoalsManager.targetFiber),
        showsAllNutrients: $showsAllNutrients
      )
      // カードの地と角丸は DailyTotalsView が持つ。リストの行の地を敷くと二重になる
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
    }
  }

  // MARK: - 体組成

  /// 体組成を持っておらず、体組成計も登録していない人には何も出さない。
  ///
  /// 乗った回数だけ行を並べる。同じ日に何度も乗るので1つにまとめない。
  /// 行になっていれば、開いて9項目を見るのも、1件だけ消すのも同じ形で扱える。
  @ViewBuilder
  private var bodyCompositionSection: some View {
    if bodyComposition.isVisible {
      Section {
        let dayMeasurements = bodyComposition.summary?.measurements ?? []
        ForEach(Array(dayMeasurements.enumerated()), id: \.element.id) { index, measurement in
          NavigationLink {
            BodyMeasurementDetailView(
              measurement: measurement,
              previousDayLast: bodyComposition.summary?.previousDayLast,
              onDelete: { await bodyComposition.delete(measurement) }
            )
          } label: {
            // 項目名は先頭の行だけ。同じ日に何度も乗ると同じ語が何度も並ぶ
            BodyMeasurementRow(measurement: measurement, showsLabels: index == 0)
          }
          // 食品マスタの削除と同じ操作。完全スワイプで消えると取り消せない
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
              Task { await bodyComposition.delete(measurement) }
            } label: {
              Label(
                NSLocalizedString("Delete", comment: "Delete button"), systemImage: "trash")
            }
          }
        }

        if let last = bodyComposition.summary?.lastMeasured {
          BodyLastMeasuredRow(last: last)
        }

        if bodyComposition.showsAction {
          BodyCompositionActionView(
            hasMeasurementToday: !(bodyComposition.summary?.measurements.isEmpty ?? true),
            activity: bodyComposition.activity,
            canMeasure: bodyComposition.canMeasure,
            failure: bodyComposition.manualFailure,
            onMeasure: { bodyComposition.measureByHand() },
            onStop: { bodyComposition.stop() }
          )
        }
      } header: {
        Text(NSLocalizedString("Body Composition", comment: "Body composition section"))
          .sectionHeaderAlignedToCard()
      }
      .headerProminence(.increased)
    }
  }

  // MARK: - 食事セクション

  /// 記録がある食事タイプ。未記録のものは末尾にまとめるのでここには出さない。
  private var loggedMealTypes: [MealType] {
    MealType.allCases.filter { type in dayLogItems.contains { $0.mealType == type } }
  }

  private var unloggedMealTypes: [MealType] {
    MealType.allCases.filter { type in !dayLogItems.contains { $0.mealType == type } }
  }

  private func items(for mealType: MealType) -> [LogItemDTO] {
    dayLogItems.filter { $0.mealType == mealType }
  }

  private func mealSection(for mealType: MealType) -> some View {
    let mealItems = items(for: mealType)

    return Section {
      ForEach(mealItems, id: \.id) { item in
        ItemRowView(item: item, onUpdate: { updated in
          if let index = dayLogItems.firstIndex(where: { $0.id == updated.id }) {
            dayLogItems[index] = updated
          }
        })
        .tag(item.id)
      }
      .onDelete { indexSet in
        let itemsToDelete = indexSet.map { mealItems[$0] }
        Task { await deleteItems(itemsToDelete) }
      }
    } header: {
      mealHeader(for: mealType, totalCalories: totals(for: mealItems).calories)
        .sectionHeaderAlignedToCard()
    }
    .headerProminence(.increased)
  }

  private func mealHeader(for mealType: MealType, totalCalories: Double) -> some View {
    HStack(spacing: 6) {
      Image(systemName: mealType.iconName)
        .foregroundStyle(mealType.accentColor)
        .accessibilityHidden(true)

      Text(mealType.localizedName)

      Spacer(minLength: 8)

      // 追加は左下のボタンにまとめた。見出しごとに置くと入口が散らばる
      CalorieLabel(calories: totalCalories, textStyle: .subheadline)
        .foregroundStyle(.secondary)
    }
    .textCase(nil)
  }

  /// 未記録の食事をまとめた1セクション。
  ///
  /// 食事ごとに空のセクションを立てると、何も食べていない日ほど画面が縦に長くなる。
  @ViewBuilder
  private var unloggedMealsSection: some View {
    let types = unloggedMealTypes
    if !types.isEmpty {
      Section {
        ForEach(types, id: \.self) { mealType in
          HStack(spacing: 0) {
            Button {
              onAddTapped(date, mealType)
            } label: {
              Label(
                String(
                  format: NSLocalizedString("Add %@", comment: "Add meal type"),
                  mealType.localizedName),
                systemImage: mealType.iconName
              )
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            Menu {
              Button {
                Task { await copyPreviousDayMeals(for: mealType) }
              } label: {
                Label(
                  String(
                    format: NSLocalizedString(
                      "Copy yesterday's %@", comment: "Copy previous day meal"),
                    mealType.localizedName),
                  systemImage: "arrow.counterclockwise")
              }
            } label: {
              Image(systemName: "ellipsis")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(
              String(
                format: NSLocalizedString("More options for %@", comment: "Meal options menu"),
                mealType.localizedName))
          }
          .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 8))
        }
      } header: {
        Text(NSLocalizedString("Not logged yet", comment: "Section for meals without records"))
          .sectionHeaderAlignedToCard()
      }
    }
  }

  // MARK: - 集計

  private typealias Totals = (
    calories: Double, protein: Double, fat: Double, netCarbs: Double, fiber: Double, carbs: Double
  )

  private var dailyTotals: Totals { totals(for: dayLogItems) }

  private func totals(for items: [LogItemDTO]) -> Totals {
    items.reduce((0, 0, 0, 0, 0, 0)) { result, item in
      (
        result.0 + item.calories, result.1 + item.protein, result.2 + item.fat,
        result.3 + item.netCarbs, result.4 + item.dietaryFiber, result.5 + item.carbohydrates
      )
    }
  }

  // MARK: - API操作

  private func loadLogItems() async {
    isLoading = true
    defer { isLoading = false }
    do {
      dayLogItems = try await APIClient.shared.fetchLogItems(logDate: logDateString)
      loadFailed = false
    } catch {
      // 握りつぶすと、その日が「何も食べていない日」に見えて二重記録を招く。
      if dayLogItems.isEmpty {
        loadFailed = true
      } else {
        failure = .refreshing(error)
      }
    }
  }

  /// 週の帯のリングは補助の表示なので、読めなくても画面を差し替えたり
  /// アラートを出したりはしない。リングが空のまま、記録の表示はそのまま使える。
  private func loadWeekCalories() async {
    guard let first = weekDays.first, let last = weekDays.last else { return }
    do {
      let summary = try await APIClient.shared.fetchDailySummary(
        from: LogItemDTO.formatLogDate(first), to: LogItemDTO.formatLogDate(last))
      weekCalories = Dictionary(
        summary.map { ($0.logDate, $0.calories) }, uniquingKeysWith: +)
    } catch {
      weekCalories = [:]
    }
  }

  private func copyPreviousDayMeals(for mealType: MealType) async {
    let calendar = Calendar.current
    let previousDay = calendar.date(byAdding: .day, value: -1, to: date)!
    let previousDayString = LogItemDTO.formatLogDate(previousDay)

    do {
      let previousItems = try await APIClient.shared.fetchLogItems(logDate: previousDayString)
      let filtered = previousItems.filter { $0.mealType == mealType }
      // 前日に記録が無いと何も起きない。押しても無反応だと壊れたように見えるので伝える。
      guard !filtered.isEmpty else {
        failure = OperationFailure(
          title: NSLocalizedString("Nothing to copy", comment: "Copy previous day empty title"),
          message: String(
            format: NSLocalizedString(
              "There is no %@ logged for yesterday.", comment: "Copy previous day empty message"),
            mealType.localizedName))
        return
      }

      let dtos = filtered.map { prev in
        LogItemCreateDTO(
          id: UUID().uuidString,
          timestamp: ISO8601DateFormatter().string(from: LogItemDTO.timestamp(for: date)),
          logDate: logDateString,
          mealType: mealType.rawValue,
          numberOfServings: prev.numberOfServings,
          foodMasterId: prev.foodMaster?.id.uuidString,
          nutritionSnapshot: prev.nutritionSnapshot
        )
      }
      _ = try await APIClient.shared.batchCreateLogItems(dtos)
      await loadLogItems()
    } catch {
      failure = .saving(error)
    }
  }

  private func deleteItems(_ items: [LogItemDTO]) async {
    for item in items {
      do {
        try await APIClient.shared.deleteLogItem(id: item.id)
        dayLogItems.removeAll { $0.id == item.id }
        deletedCount += 1
      } catch {
        // 消えたように見えて消えていない状態を残さない。
        // 行は手元に残したまま、削除できなかったことを伝える。
        failure = .deleting(error)
        return
      }
    }
  }

  private func deleteSelectedItems() {
    let toDelete = dayLogItems.filter { selectedItemIDs.contains($0.id) }
    selectedItemIDs.removeAll()
    editMode = .inactive
    Task { await deleteItems(toDelete) }
  }
}

// MARK: - 追加ボタン

/// 画面の左下に浮かべる、食事を追加する丸いボタン。
private struct AddMealButton: View {
  let action: () -> Void

  @ScaledMetric(relativeTo: .title2) private var scaledSize: CGFloat = 60

  /// 大きな文字でも記録を覆いすぎないところで止める。
  private var size: CGFloat { min(scaledSize, 76) }

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.title2.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(.tint))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(NSLocalizedString("Add Meal", comment: "Navigation title"))
  }
}

// MARK: - 見出しの位置

extension View {
  /// セクションの見出しを、下のカードの左端にそろえる。
  ///
  /// 既定では見出しがカードの中身と同じ位置まで内側に寄り、見出しなのに
  /// カードより奥に引っ込んで見える。外側にそろえて、どのカードの見出しかを示す。
  fileprivate func sectionHeaderAlignedToCard() -> some View {
    listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
  }
}

// MARK: - LogItemDTO extension

extension LogItemDTO {
  static func formatLogDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  /// 記録の時刻。対象の日に、いま記録している時刻を合わせる。
  ///
  /// 画面が持っている日付をそのまま使うと、時刻が画面の状態の副産物になる。
  /// ログのタブをもう一度タップすると `startOfDay` で 00:00 に固定され、
  /// 日付を前後に動かすとアプリ起動時の時刻を引きずる。
  /// 実際、2026年の記録の47%が00時台に集まっていた。
  ///
  /// 日内の並び順は timestamp の昇順なので、同着だと順序が決まらない。
  static func timestamp(for day: Date, now: Date = Date()) -> Date {
    let calendar = Calendar.current
    let time = calendar.dateComponents([.hour, .minute, .second], from: now)
    return calendar.date(
      bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0,
      of: day) ?? day
  }
}
