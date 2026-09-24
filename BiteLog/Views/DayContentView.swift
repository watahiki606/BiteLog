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

  @State private var deleteAllTrigger = 0

  private var logDateString: String { LogItemDTO.formatLogDate(date) }
  private var taskID: String { "\(logDateString)-\(refreshTrigger)-\(deleteAllTrigger)" }

  var body: some View {
    contentView
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          if !filteredItems.isEmpty {
            EditButton()
              .environment(\.editMode, $editMode)
          }
        }
        ToolbarItem(placement: .navigationBarLeading) {
          if editMode == .active && !selectedItemIDs.isEmpty {
            Button(action: deleteSelectedItems) {
              Label(
                String(
                  format: NSLocalizedString("Delete %d items", comment: "Delete multiple items"),
                  selectedItemIDs.count),
                systemImage: "trash"
              )
              .foregroundColor(.red)
            }
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

  @ViewBuilder
  private var contentView: some View {
    VStack(spacing: 0) {
      scrollContent
    }
    .background(Color(UIColor.systemGroupedBackground))
  }

  @ViewBuilder
  private var scrollContent: some View {
    ScrollView {
      VStack(spacing: 16) {
        Color.clear.frame(height: 1).padding(.top, 8)

        AdaptiveBannerView()
          .frame(height: 50)
          .padding(.horizontal)
          .padding(.bottom, -30)
          .padding(.top, -30)

        dailySummaryCard

        ForEach(MealType.allCases, id: \.self) { mealType in
          mealSection(for: mealType)
        }
      }
      .padding(.vertical)
    }
    .refreshable {
      await loadLogItems()
    }
    .overlay {
      if isLoading && dayLogItems.isEmpty {
        ProgressView()
      }
    }
  }

  @ViewBuilder
  private var dailySummaryCard: some View {
    VStack(spacing: 0) {
      Text(NSLocalizedString("Daily Total", comment: "Daily nutrition summary"))
        .font(.headline)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 12)

      Divider()

      HStack(spacing: 16) {
        CalorieRingView(
          calories: dailyTotals.calories,
          targetCalories: nutritionGoalsManager.targetCalories
        )
        VStack(spacing: 8) {
          NutrientBar(
            nutrient: .protein,
            value: dailyTotals.protein,
            target: nutritionGoalsManager.targetProtein
          )
          NutrientBar(
            nutrient: .fat,
            value: dailyTotals.fat,
            target: nutritionGoalsManager.targetFat
          )
          NutrientBar(
            nutrient: .netCarbs,
            value: dailyTotals.netCarbs,
            target: nutritionGoalsManager.targetNetCarbs
          )
          NutrientBar(
            nutrient: .fiber,
            value: dailyTotals.fiber,
            target: nutritionGoalsManager.targetFiber
          )
        }
      }
      .padding()

      Divider().padding(.horizontal)

      LabeledContent {
        Text("\(Nutrient.carbs.format(dailyTotals.carbs))\(Nutrient.carbs.unit)")
          .monospacedDigit()
      } label: {
        // 上に糖質を別途出しているので、ここは内訳が分かる長い名前を使う。
        Text(NSLocalizedString("Carbs (Sugar + Fiber)", comment: "Nutrient label"))
      }
      .font(.subheadline)
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
    .background(
      Color(UIColor.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .padding(.horizontal)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private func mealSection(for mealType: MealType) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: mealType.iconName)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(mealType.accentColor)
          .accessibilityHidden(true)
        Text(mealType.localizedName)
          .font(.headline)
        Spacer()
        Button(action: { onAddTapped(date, mealType) }) {
          Label(NSLocalizedString("Add", comment: "Add button"), systemImage: "plus.circle.fill")
            .font(.subheadline)
            .foregroundStyle(mealType.accentColor)
        }
      }
      .padding(.horizontal)

      let totals = mealTypeTotals(for: mealType)
      if filteredItems.contains(where: { $0.mealType == mealType }) {
        HStack(spacing: 6) {
          CalorieLabel(calories: totals.calories, textStyle: .caption)
          NutrientChipRow(
            values: NutritionValues(
              calories: totals.calories, netCarbs: totals.netCarbs,
              dietaryFiber: totals.fiber, fat: totals.fat, protein: totals.protein))
          Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
      }

      Divider()

      let mealItems = filteredItems.filter { $0.mealType == mealType }
      if mealItems.isEmpty {
        Button(action: { Task { await copyPreviousDayMeals(for: mealType) } }) {
          HStack {
            Image(systemName: "arrow.counterclockwise").font(.body).foregroundStyle(.tint)
            Text(
              String(
                format: NSLocalizedString("Copy yesterday's %@", comment: "Copy previous day meal"),
                mealType.localizedName)
            )
            .font(.subheadline)
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(
            Color(UIColor.tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 8)
          )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)

        EmptyMealView(mealType: mealType) { onAddTapped(date, mealType) }
      } else {
        mealItemsList(mealItems: mealItems)
        Divider().padding(.horizontal)
        EmptyMealView(mealType: mealType) { onAddTapped(date, mealType) }
      }
    }
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(UIColor.secondarySystemGroupedBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).fill(mealType.accentColor.opacity(0.03)))
    )
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(mealType.accentColor.opacity(0.15), lineWidth: 0.5))
    .padding(.horizontal)
  }

  @ViewBuilder
  private func mealItemsList(mealItems: [LogItemDTO]) -> some View {
    let firstID = mealItems.first?.id
    let lastID = mealItems.last?.id
    List(selection: editMode == .active ? $selectedItemIDs : .constant(Set<UUID>())) {
      ForEach(mealItems, id: \.id) { item in
        let isFirst = item.id == firstID
        let isLast = item.id == lastID
        ItemRowView(item: item, onUpdate: { updated in
          if let idx = dayLogItems.firstIndex(where: { $0.id == updated.id }) {
            dayLogItems[idx] = updated
          }
        })
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(isLast ? .hidden : .visible, edges: .bottom)
        .listRowSeparator(isFirst ? .hidden : .visible, edges: .top)
        .listRowSeparatorTint(Color.primary.opacity(0.15))
        .tag(item.id)
      }
      .onDelete(perform: editMode == .active ? nil : { indexSet in
        let itemsToDelete = indexSet.map { mealItems[$0] }
        Task { await deleteItems(itemsToDelete) }
      })
    }
    .scrollDisabled(true)
    .listStyle(.plain)
    .frame(height: CGFloat(mealItems.count) * 66)
    .environment(\.editMode, $editMode)
  }

  private var filteredItems: [LogItemDTO] { dayLogItems }

  private var dailyTotals: (calories: Double, protein: Double, fat: Double, netCarbs: Double, fiber: Double, carbs: Double) {
    filteredItems.reduce((0, 0, 0, 0, 0, 0)) { r, item in
      (r.0 + item.calories, r.1 + item.protein, r.2 + item.fat,
       r.3 + item.netCarbs, r.4 + item.dietaryFiber, r.5 + item.carbohydrates)
    }
  }

  private func mealTypeTotals(for mealType: MealType) -> (calories: Double, protein: Double, fat: Double, netCarbs: Double, fiber: Double, carbs: Double) {
    filteredItems.filter { $0.mealType == mealType }.reduce((0, 0, 0, 0, 0, 0)) { r, item in
      (r.0 + item.calories, r.1 + item.protein, r.2 + item.fat,
       r.3 + item.netCarbs, r.4 + item.dietaryFiber, r.5 + item.carbohydrates)
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
