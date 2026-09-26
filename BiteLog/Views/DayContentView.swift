import SwiftUI

struct DayContentView: View {
  let date: Date
  let selectedDate: Date
  let onAddTapped: (Date, MealType) -> Void
  var refreshTrigger: Int = 0

  @EnvironmentObject private var nutritionGoalsManager: NutritionGoalsManager

  @State private var dayLogItems: [LogItemDTO] = []
  @State private var isLoading = false
  /// 読み込めなかった状態。0件と区別する。同じ見た目で出すと、
  /// 記録が残っているのにもう一度記録し直す操作を誘発する。
  @State private var loadFailed = false
  @State private var failure: OperationFailure?
  @State private var editMode: EditMode = .inactive
  @State private var selectedItemIDs: Set<UUID> = []
  @State private var showsAllNutrients = false

  @State private var deleteAllTrigger = 0
  @State private var deletedCount = 0

  private var logDateString: String { LogItemDTO.formatLogDate(date) }
  private var taskID: String { "\(logDateString)-\(refreshTrigger)-\(deleteAllTrigger)" }

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
    .onReceive(NotificationCenter.default.publisher(for: .allDataDeleted)) { _ in
      dayLogItems = []
      deleteAllTrigger += 1
    }
  }

  private var logList: some View {
    List(selection: editMode == .active ? $selectedItemIDs : .constant(Set<UUID>())) {
      summarySection

      ForEach(loggedMealTypes, id: \.self) { mealType in
        mealSection(for: mealType)
      }

      unloggedMealsSection
    }
    .listStyle(.insetGrouped)
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
    } header: {
      Text(NSLocalizedString("Daily Total", comment: "Daily nutrition summary"))
    }
    .headerProminence(.increased)
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

      CalorieLabel(calories: totalCalories, textStyle: .subheadline)
        .foregroundStyle(.secondary)

      Button {
        onAddTapped(date, mealType)
      } label: {
        Image(systemName: "plus.circle.fill")
          .font(.title3)
          // アイコンだけだとタップ領域が小さいので 44pt 角を確保する。
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(mealType.accentColor)
      .accessibilityLabel(
        String(
          format: NSLocalizedString("Add %@", comment: "Add meal type"), mealType.localizedName))
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

      let now = Date()
      let dtos = filtered.map { prev in
        LogItemCreateDTO(
          id: UUID().uuidString,
          timestamp: ISO8601DateFormatter().string(from: now),
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

// MARK: - LogItemDTO extension

extension LogItemDTO {
  static func formatLogDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}
