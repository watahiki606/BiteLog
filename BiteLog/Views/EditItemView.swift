import SwiftUI

struct EditItemView: View {
  @Environment(\.dismiss) var dismiss

  @State var item: LogItemDTO
  var onSaved: ((LogItemDTO) -> Void)?

  @State private var numberOfServings: String
  @State private var foodMaster: FoodMasterDTO?
  @State private var showingFoodSearch = false
  @State private var searchResults: [FoodMasterDTO] = []
  @State private var currentOffset = 0
  @State private var hasMoreData = true
  @State private var isSaving = false
  @State private var failure: OperationFailure?
  private let pageSize = 100

  private var perPortionCalories: Double { foodMaster?.calories ?? item.nutritionSnapshot?.calories ?? 0 }
  private var perPortionProtein: Double { foodMaster?.protein ?? item.nutritionSnapshot?.protein ?? 0 }
  private var perPortionFat: Double { foodMaster?.fat ?? item.nutritionSnapshot?.fat ?? 0 }
  private var perPortionNetCarbs: Double { foodMaster?.netCarbs ?? item.nutritionSnapshot?.netCarbs ?? 0 }
  private var perPortionDietaryFiber: Double { foodMaster?.dietaryFiber ?? item.nutritionSnapshot?.dietaryFiber ?? 0 }
  private var portionSize: Double { foodMaster?.portionSize ?? item.nutritionSnapshot?.portionSize ?? 1.0 }

  private var servingsValue: Double { Double(numberOfServings) ?? 1.0 }

  private var totalNutrition: NutritionValues {
    if let fm = foodMaster {
      return NutritionSnapshot.from(fm).scaled(by: servingsValue)
    } else if let snapshot = item.nutritionSnapshot {
      return snapshot.scaled(by: servingsValue)
    }
    return .zero
  }

  private var totalCalories: Double { totalNutrition.calories }
  private var totalProtein: Double { totalNutrition.protein }
  private var totalFat: Double { totalNutrition.fat }
  private var totalNetCarbs: Double { totalNutrition.netCarbs }
  private var totalDietaryFiber: Double { totalNutrition.dietaryFiber }
  private var totalCarbs: Double { totalNutrition.carbs }

  init(item: LogItemDTO, onSaved: ((LogItemDTO) -> Void)? = nil) {
    _item = State(initialValue: item)
    _numberOfServings = State(initialValue: NutritionFormatter.formatNutrition(item.numberOfServings))
    _foodMaster = State(initialValue: item.foodMaster)
    self.onSaved = onSaved
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          foodRow

          LabeledContent {
            HStack(spacing: 6) {
              TextField("1.0", text: $numberOfServings)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
              Text(foodMaster?.portionUnit ?? item.portionUnit)
                .foregroundStyle(.secondary)
            }
          } label: {
            Text(NSLocalizedString("Servings", comment: "Servings label"))
          }
        } header: {
          Text(NSLocalizedString("Food Item", comment: "Form section title"))
        } footer: {
          Text(
            NSLocalizedString(
              "Adjust the serving size to calculate the intake", comment: "Servings explanation"))
        }

        if foodMaster != nil || item.isMasterDeleted {
          Section {
            EditNutrientRow(
              nutrient: .calories, perPortion: perPortionCalories, total: totalCalories)
            EditNutrientRow(
              nutrient: .protein, perPortion: perPortionProtein, total: totalProtein)
            EditNutrientRow(nutrient: .fat, perPortion: perPortionFat, total: totalFat)
            EditNutrientRow(
              nutrient: .netCarbs, perPortion: perPortionNetCarbs, total: totalNetCarbs)
            EditNutrientRow(
              nutrient: .fiber, perPortion: perPortionDietaryFiber, total: totalDietaryFiber)
            EditNutrientRow(
              nutrient: .carbs,
              perPortion: perPortionNetCarbs + perPortionDietaryFiber,
              total: totalCarbs)
          } header: {
            Text(NSLocalizedString("Nutrition", comment: "Form section title"))
          } footer: {
            Text(
              String(
                format: NSLocalizedString(
                  "Values shown as: per %@ %@ → total", comment: "Nutrition explanation"),
                NutritionFormatter.formatNutrition(portionSize),
                foodMaster?.portionUnit ?? item.portionUnit))
          }
        }
      }
      .navigationTitle(NSLocalizedString("Edit Meal", comment: "Navigation title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Save", comment: "Button title"), action: saveLogItem)
            .disabled(
              isSaving || (foodMaster == nil && !item.isMasterDeleted)
                || numberOfServings.isEmpty || Double(numberOfServings) == 0)
        }
      }
      .operationFailureAlert($failure)
      .sheet(isPresented: $showingFoodSearch) {
        FoodSearchView(onSelect: { selected in
          foodMaster = selected
          numberOfServings = NutritionFormatter.formatNutrition(selected.lastNumberOfServings)
        })
      }
    }
  }

  @ViewBuilder
  private var foodRow: some View {
    if let foodMaster {
      Text(FoodRow.displayName(brand: foodMaster.brandName, product: foodMaster.productName))
        .font(.headline)
        .lineLimit(2)
    } else if item.isMasterDeleted {
      HStack(spacing: 4) {
        Text(FoodRow.displayName(brand: item.brandName, product: item.productName))
          .font(.headline)
          .lineLimit(2)
          .foregroundStyle(.secondary)
          .strikethrough()

        Text(NSLocalizedString("(Deleted)", comment: "Deleted Food indicator"))
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize()
      }
    } else {
      Button {
        showingFoodSearch = true
      } label: {
        Label(
          NSLocalizedString("Search for food", comment: "Search for food"),
          systemImage: "magnifyingglass")
      }
    }
  }

  private func saveLogItem() {
    let dto = LogItemUpdateDTO(
      numberOfServings: servingsValue,
      mealType: nil,
      timestamp: nil
    )
    Task {
      isSaving = true
      defer { isSaving = false }
      do {
        let updated = try await APIClient.shared.updateLogItem(id: item.id, dto)
        onSaved?(updated)
        dismiss()
      } catch {
        // 失敗しても閉じると、保存できていないのに保存したつもりになる。
        // 入力を残したまま伝え、もう一度試せるようにする。
        failure = .saving(error)
      }
    }
  }
}

/// 「1食あたり → 合計」を1行で示す。栄養素の名前・色・単位は `Nutrient` から引く。
struct EditNutrientRow: View {
  let nutrient: Nutrient
  let perPortion: Double
  let total: Double

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: nutrient.symbolName)
        .foregroundStyle(nutrient.color)
        .accessibilityHidden(true)

      Text(nutrient.localizedName)

      Spacer(minLength: 8)

      Text("\(nutrient.format(perPortion))\(nutrient.unit)")
        .monospacedDigit()
        .foregroundStyle(.secondary)

      Image(systemName: "arrow.right")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      Text("\(nutrient.format(total))\(nutrient.unit)")
        .monospacedDigit()
        .fontWeight(.medium)
    }
    .font(.subheadline)
    .padding(12)
    .background(
      Color(UIColor.tertiarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 10)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(nutrient.accessibilityLabel(for: total))
  }
}

// 食品検索ビュー
struct FoodSearchView: View {
  @Environment(\.dismiss) var dismiss
  var onSelect: (FoodMasterDTO) -> Void

  @State private var searchText = ""
  @State private var searchResults: [FoodMasterDTO] = []
  @State private var currentOffset = 0
  @State private var hasMoreData = true
  /// 検索できなかった状態。0件と区別しないと、登録済みの食品を
  /// 「無い」と思って作り直すことになる。
  @State private var loadFailed = false
  private let pageSize = 50

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(NSLocalizedString("Select food", comment: "Navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
          text: $searchText,
          prompt: Text(NSLocalizedString("Search food items", comment: "Search placeholder"))
        )
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
          }
        }
        .onChange(of: searchText) { _, _ in
          searchResults = []
          currentOffset = 0
          hasMoreData = true
          loadFailed = false
          Task { await loadMoreItems() }
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    if searchText.isEmpty {
      ContentUnavailableView {
        Label(
          NSLocalizedString("Search for food", comment: "Search for food"),
          systemImage: "magnifyingglass")
      }
    } else if loadFailed && searchResults.isEmpty {
      LoadFailureView { await loadMoreItems() }
    } else if searchResults.isEmpty {
      ContentUnavailableView.search(text: searchText)
    } else {
      List {
        ForEach(searchResults, id: \.id) { item in
          Button {
            onSelect(item)
            dismiss()
          } label: {
            FoodMasterRow(foodMaster: item)
          }
          .buttonStyle(.plain)
          .onAppear {
            if item.id == searchResults.last?.id && hasMoreData {
              Task { await loadMoreItems() }
            }
          }
        }
      }
      .listStyle(.insetGrouped)
    }
  }

  private func loadMoreItems() async {
    guard !searchText.isEmpty else {
      searchResults = []; currentOffset = 0; hasMoreData = true; return
    }
    do {
      let resp = try await APIClient.shared.fetchFoodMasters(query: searchText, limit: pageSize, offset: currentOffset)
      if currentOffset == 0 { searchResults = resp.items } else { searchResults.append(contentsOf: resp.items) }
      currentOffset += resp.items.count
      hasMoreData = resp.hasMore
      loadFailed = false
    } catch {
      loadFailed = true
    }
  }
}
