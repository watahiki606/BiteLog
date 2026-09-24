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
      ZStack {
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()

        ScrollView {
          VStack(spacing: 24) {
            CardView(title: NSLocalizedString("Food Item", comment: "Form section title")) {
              VStack(spacing: 16) {
                if let fm = foodMaster {
                  HStack {
                    VStack(alignment: .leading, spacing: 4) {
                      Text("\(fm.brandName) \(fm.productName)")
                        .font(.headline).lineLimit(2)
                    }
                    Spacer()
                  }
                  .padding(.vertical, 8).padding(.horizontal, 12)
                  .background(Color(UIColor.secondarySystemBackground))
                  .cornerRadius(10)
                } else if item.isMasterDeleted {
                  HStack {
                    VStack(alignment: .leading, spacing: 4) {
                      HStack {
                        Text("\(item.brandName) \(item.productName)")
                          .font(.headline).lineLimit(2)
                          .foregroundColor(.secondary).strikethrough()
                        Text(NSLocalizedString("(Deleted)", comment: "Deleted Food indicator"))
                          .font(.caption).foregroundColor(.red)
                          .padding(.horizontal, 4).padding(.vertical, 2)
                          .background(Color.red.opacity(0.1)).cornerRadius(4)
                      }
                    }
                    Spacer()
                  }
                  .padding(.vertical, 8).padding(.horizontal, 12)
                  .background(Color(UIColor.secondarySystemBackground))
                  .cornerRadius(10)
                } else {
                  Button(action: { showingFoodSearch = true }) {
                    HStack {
                      Image(systemName: "magnifyingglass")
                      Text(NSLocalizedString("Search for food", comment: "Search for food"))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
                  }
                }

                HStack {
                  Text(NSLocalizedString("Servings:", comment: "Servings label")).font(.body)
                  TextField("1.0", text: $numberOfServings)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .padding(8).background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8).frame(width: 80)
                  if let fm = foodMaster {
                    Text(fm.portionUnit).font(.body).foregroundColor(.secondary)
                  }
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)

                Text(NSLocalizedString("Adjust the serving size to calculate the intake", comment: "Servings explanation"))
                  .font(.caption).foregroundColor(.secondary).padding(.bottom, 4)
              }
            }

            if foodMaster != nil || item.isMasterDeleted {
              CardView(title: NSLocalizedString("Nutrition", comment: "Form section title")) {
                VStack(spacing: 16) {
                  Text(String(
                    format: NSLocalizedString("Values shown as: per %@ %@ → total", comment: "Nutrition explanation"),
                    NutritionFormatter.formatNutrition(portionSize),
                    foodMaster?.portionUnit ?? item.portionUnit))
                  .font(.caption).foregroundColor(.secondary).padding(.bottom, 4)

                  EditNutrientRow(
                    nutrient: .calories, perPortion: perPortionCalories, total: totalCalories)
                  EditNutrientRow(
                    nutrient: .protein, perPortion: perPortionProtein, total: totalProtein)
                  EditNutrientRow(
                    nutrient: .fat, perPortion: perPortionFat, total: totalFat)
                  EditNutrientRow(
                    nutrient: .netCarbs, perPortion: perPortionNetCarbs, total: totalNetCarbs)
                  EditNutrientRow(
                    nutrient: .fiber, perPortion: perPortionDietaryFiber, total: totalDietaryFiber)
                  EditNutrientRow(
                    nutrient: .carbs,
                    perPortion: perPortionNetCarbs + perPortionDietaryFiber,
                    total: totalCarbs)
                }
              }
            }
          }
          .padding()
        }
      }
      .navigationTitle(NSLocalizedString("Edit Meal", comment: "Navigation title"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(action: saveLogItem) {
            Text(NSLocalizedString("Save", comment: "Button title")).bold()
          }
          .disabled((foodMaster == nil && !item.isMasterDeleted) || numberOfServings.isEmpty || Double(numberOfServings) == 0)
        }
      }
      .sheet(isPresented: $showingFoodSearch) {
        FoodSearchView(onSelect: { selected in
          foodMaster = selected
          numberOfServings = NutritionFormatter.formatNutrition(selected.lastNumberOfServings)
        })
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
      do {
        let updated = try await APIClient.shared.updateLogItem(id: item.id, dto)
        onSaved?(updated)
        dismiss()
      } catch {
        print("EditItemView saveLogItem error: \(error)")
        dismiss()
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
  private let pageSize = 50

  var body: some View {
    NavigationStack {
      VStack {
        HStack {
          Image(systemName: "magnifyingglass").foregroundColor(.secondary).padding(.leading, 8)
          TextField(NSLocalizedString("Search food items", comment: "Search placeholder"), text: $searchText)
            .padding(10).background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
          if !searchText.isEmpty {
            Button(action: { searchText = "" }) {
              Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).padding(.trailing, 8)
            }
          }
        }
        .padding(.horizontal).padding(.top, 8)

        if searchText.isEmpty {
          VStack(spacing: 16) {
            Image(systemName: "magnifyingglass").font(.system(size: 48)).foregroundColor(.secondary)
            Text(NSLocalizedString("Search for food", comment: "Search for food")).font(.headline).foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List {
            ForEach(searchResults, id: \.id) { item in
              Button { onSelect(item); dismiss() } label: { FoodMasterRow(foodMaster: item) }
                .onAppear {
                  if item.id == searchResults.last?.id && hasMoreData { Task { await loadMoreItems() } }
                }
            }
            if searchResults.isEmpty {
              VStack(spacing: 16) {
                Image(systemName: "exclamationmark.magnifyingglass").font(.system(size: 48)).foregroundColor(.secondary)
                Text(NSLocalizedString("No search results found", comment: "No search results message")).font(.headline).foregroundColor(.secondary)
              }
              .frame(maxWidth: .infinity).padding(.vertical, 40).listRowBackground(Color.clear)
            }
          }
        }
      }
      .navigationTitle(NSLocalizedString("Select food", comment: "Navigation title"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
        }
      }
      .onChange(of: searchText) { _, _ in
        searchResults = []; currentOffset = 0; hasMoreData = true
        Task { await loadMoreItems() }
      }
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
    } catch {
      print("FoodSearchView loadMoreItems error: \(error)")
    }
  }
}
