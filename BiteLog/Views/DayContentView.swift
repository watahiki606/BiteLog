import SwiftUI

struct DayContentView: View {
  let date: Date
  let selectedDate: Date
  let onAddTapped: (Date, MealType) -> Void
  var refreshTrigger: Int = 0

  @EnvironmentObject private var nutritionGoalsManager: NutritionGoalsManager

  @State private var dayLogItems: [LogItemDTO] = []
  @State private var isLoading = false
  @State private var editMode: EditMode = .inactive
  @State private var selectedItemIDs: Set<UUID> = []
  @State private var showsAllNutrients = false

  @State private var deleteAllTrigger = 0
  @State private var deletedCount = 0

  private var logDateString: String { LogItemDTO.formatLogDate(date) }
  private var taskID: String { "\(logDateString)-\(refreshTrigger)-\(deleteAllTrigger)" }

  var body: some View {
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
    // 広告はスクロール内容に混ぜず画面下端に固定する。
    // 以前は負のパディングでスクロール内に押し込んでいて、余白が崩れやすかった。
    .safeAreaInset(edge: .bottom) {
      AdaptiveBannerView()
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
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
  /// 以前は未記録でも5つの食事が「昨日をコピー」「◯◯を追加」の2ボタン付きで
  /// 並んでいて、何も食べていない日ほど画面が縦に長くなっていた。
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
    } catch {
      print("DayContentView loadLogItems error: \(error)")
    }
  }

  private func copyPreviousDayMeals(for mealType: MealType) async {
    let calendar = Calendar.current
    let previousDay = calendar.date(byAdding: .day, value: -1, to: date)!
    let previousDayString = LogItemDTO.formatLogDate(previousDay)

    do {
      let previousItems = try await APIClient.shared.fetchLogItems(logDate: previousDayString)
      let filtered = previousItems.filter { $0.mealType == mealType }
      guard !filtered.isEmpty else { return }

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
      let result = try await APIClient.shared.batchCreateLogItems(dtos)
      print("Copied \(result.created) meals from previous day")
      await loadLogItems()
    } catch {
      print("copyPreviousDayMeals error: \(error)")
    }
  }

  private func deleteItems(_ items: [LogItemDTO]) async {
    for item in items {
      do {
        try await APIClient.shared.deleteLogItem(id: item.id)
        dayLogItems.removeAll { $0.id == item.id }
        deletedCount += 1
      } catch {
        print("deleteItems error: \(error)")
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
