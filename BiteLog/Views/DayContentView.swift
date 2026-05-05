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
          MacroBarView(
            label: NSLocalizedString("Protein", comment: "Nutrient label"),
            value: dailyTotals.protein,
            maxValue: nutritionGoalsManager.targetProtein,
            color: .blue, icon: "p.circle.fill"
          )
          MacroBarView(
            label: NSLocalizedString("Fat", comment: "Nutrient label"),
            value: dailyTotals.fat,
            maxValue: nutritionGoalsManager.targetFat,
            color: .yellow, icon: "f.circle.fill"
          )
          MacroBarView(
            label: NSLocalizedString("Sugar", comment: "Nutrient label"),
            value: dailyTotals.netCarbs,
            maxValue: nutritionGoalsManager.targetNetCarbs,
            color: .green, icon: "s.circle.fill"
          )
          MacroBarView(
            label: NSLocalizedString("Dietary Fiber", comment: "Nutrient label"),
            value: dailyTotals.fiber,
            maxValue: nutritionGoalsManager.targetFiber,
            color: .brown, icon: "leaf.circle.fill"
          )
        }
      }
      .padding()

      Divider().padding(.horizontal)

      NutrientRow(
        label: NSLocalizedString("Carbs (Sugar + Fiber)", comment: "Nutrient label"),
        value: dailyTotals.carbs, unit: "g", format: "%.3f",
        icon: "c.circle.fill", color: .gray
      )
      .padding(.vertical, 8)
    }
    .background(Color(UIColor.systemBackground))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    .padding(.horizontal)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private func mealSection(for mealType: MealType) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: mealType.iconName)
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(mealType.accentColor)
        Text(mealType.localizedName)
          .font(.headline)
        Spacer()
        Button(action: { onAddTapped(date, mealType) }) {
          Label(NSLocalizedString("Add", comment: "Add button"), systemImage: "plus.circle.fill")
            .font(.subheadline)
            .foregroundColor(mealType.accentColor)
        }
      }
      .padding(.horizontal)

      let totals = mealTypeTotals(for: mealType)
      if filteredItems.contains(where: { $0.mealType == mealType }) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            NutrientBadge(value: totals.calories, unit: "kcal", name: "Cal", color: .orange, icon: "flame.fill")
            NutrientBadge(value: totals.protein, unit: "g", name: "P", color: .blue, icon: "p.circle.fill")
            NutrientBadge(value: totals.fat, unit: "g", name: "F", color: .yellow, icon: "f.circle.fill")
            NutrientBadge(value: totals.netCarbs, unit: "g", name: "S", color: .green, icon: "s.circle.fill")
            NutrientBadge(value: totals.fiber, unit: "g", name: "Fb", color: .brown, icon: "leaf.circle.fill")
          }
          .padding(.horizontal)
        }
        .padding(.vertical, 4)
      }

      Divider()

      let mealItems = filteredItems.filter { $0.mealType == mealType }
      if mealItems.isEmpty {
        Button(action: { Task { await copyPreviousDayMeals(for: mealType) } }) {
          HStack {
            Image(systemName: "arrow.counterclockwise").font(.body).foregroundColor(.blue)
            Text(
              String(
                format: NSLocalizedString("Copy yesterday's %@", comment: "Copy previous day meal"),
                mealType.localizedName)
            )
            .font(.subheadline)
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color(UIColor.systemBackground))
          .cornerRadius(6)
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
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(mealType.accentColor.opacity(0.1), lineWidth: 0.5))
    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
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
