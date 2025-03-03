import SwiftData
import SwiftUI

struct AddItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext

  let mealType: MealType
  var selectedDate: Date

  @State private var searchText = ""
  @State private var brandName = ""
  @State private var productName = ""
  @State private var calories: String = ""
  @State private var carbohydrates: String = ""
  @State private var fat: String = ""
  @State private var protein: String = ""
  @State private var portionUnit: String = ""
  @State private var portion: String = ""
  @State private var numberOfServings: Double = 1.0
  @State private var date: Date
  @State private var foodMaster: FoodMaster?
  @State private var searchResults: [FoodMaster] = []
  @State private var currentOffset = 0
  @State private var hasMoreData = true
  private let pageSize = 100

  init(preselectedMealType: MealType, selectedDate: Date) {
    self.mealType = preselectedMealType
    self.selectedDate = selectedDate
    _date = State(initialValue: selectedDate)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color(UIColor.systemGroupedBackground)
          .ignoresSafeArea()

        VStack {
          // 検索バー
          HStack {
            Image(systemName: "magnifyingglass")
              .foregroundColor(.secondary)
              .padding(.leading, 8)

            TextField(
              NSLocalizedString("Search past meals", comment: "Search placeholder"),
              text: $searchText
            )
            .padding(10)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)

            if !searchText.isEmpty {
              Button(action: {
                searchText = ""
              }) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundColor(.secondary)
                  .padding(.trailing, 8)
              }
            }
          }
          .padding(.horizontal)
          .padding(.top, 8)

          if searchText.isEmpty {
            // 新規入力フォーム
            ScrollView {
              VStack(spacing: 24) {
                // 基本情報カード
                CardView(title: NSLocalizedString("Basic Info", comment: "Form section title")) {
                  VStack(spacing: 16) {
                    CustomTextField(
                      icon: "tag.fill",
                      placeholder: NSLocalizedString("Brand", comment: "Brand name field"),
                      text: $brandName
                    )

                    CustomTextField(
                      icon: "cart.fill",
                      placeholder: NSLocalizedString("Product", comment: "Product name field"),
                      text: $productName
                    )

                    // Portion入力を数量と単位に分ける
                    HStack {
                      CustomTextField(
                        icon: "number",
                        placeholder: NSLocalizedString("Amount", comment: "Portion amount field"),
                        text: $portion
                      )
                      .frame(width: 120)

                      CustomTextField(
                        icon: "text.badge.checkmark",
                        placeholder: NSLocalizedString("Unit", comment: "Portion unit field"),
                        text: $portionUnit
                      )
                    }

                    Stepper(
                      "Servings: \(numberOfServings, specifier: "%.1f")",
                      value: $numberOfServings,
                      in: 0.1...10,
                      step: 0.1
                    )

                    HStack {
                      Image(systemName: "fork.knife")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                      Text(mealType.localizedName)
                        .font(.body)
                        .foregroundColor(.primary)
                      Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                  }
                }

                // 栄養素カード
                CardView(title: NSLocalizedString("Nutrition", comment: "Form section title")) {
                  VStack(spacing: 16) {
                    NutrientInputField(
                      icon: "flame.fill",
                      iconColor: .orange,
                      label: NSLocalizedString("Calories", comment: "Nutrient label"),
                      value: $calories,
                      unit: "kcal"
                    )

                    NutrientInputField(
                      icon: "p.circle.fill",
                      iconColor: .blue,
                      label: NSLocalizedString("Protein", comment: "Nutrient label"),
                      value: $protein,
                      unit: "g"
                    )

                    NutrientInputField(
                      icon: "f.circle.fill",
                      iconColor: .yellow,
                      label: NSLocalizedString("Fat", comment: "Nutrient label"),
                      value: $fat,
                      unit: "g"
                    )

                    NutrientInputField(
                      icon: "c.circle.fill",
                      iconColor: .green,
                      label: NSLocalizedString("Carbs", comment: "Nutrient label"),
                      value: $carbohydrates,
                      unit: "g"
                    )

                  }
                }
              }
              .padding()
            }
          } else {
            // 検索結果一覧
            ScrollView {
              LazyVStack(spacing: 12) {
                ForEach(searchResults) { item in
                  Button {
                    addItemFromPast(item)
                    dismiss()
                  } label: {
                    PastItemCard(item: item)
                  }
                  .buttonStyle(ScaleButtonStyle())
                  .onAppear {
                    if searchResults.index(searchResults.endIndex, offsetBy: -2)
                      == searchResults.firstIndex(of: item)
                    {
                      if hasMoreData {
                        loadMoreItems()
                      }
                    }
                  }
                }
              }
              .padding()
            }
          }
        }
        .navigationTitle(NSLocalizedString("Add Meal", comment: "Navigation title"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(action: {
              addItem()
              dismiss()
            }) {
              Text(NSLocalizedString("Save", comment: "Button title"))
                .bold()
            }
            .disabled(
              brandName.isEmpty || productName.isEmpty || portion.isEmpty || calories.isEmpty)
          }
        }
        .onChange(of: searchText) { _, _ in
          searchResults = []
          currentOffset = 0
          hasMoreData = true
          loadMoreItems()
        }
      }
    }
  }

  private func addItem() {
    // FoodMaster を作成または取得
    var foodMasterItem: FoodMaster?
    let caloriesValue = Double(calories) ?? 0
    let carbohydratesValue = Double(carbohydrates) ?? 0
    let fatValue = Double(fat) ?? 0
    let proteinValue = Double(protein) ?? 0
    let portionValue = Double(portion) ?? 0

    // 1単位あたりの栄養価を計算
    let caloriesPerUnit = portionValue > 0 ? caloriesValue / portionValue : caloriesValue
    let carbsPerUnit = portionValue > 0 ? carbohydratesValue / portionValue : carbohydratesValue
    let fatPerUnit = portionValue > 0 ? fatValue / portionValue : fatValue
    let proteinPerUnit = portionValue > 0 ? proteinValue / portionValue : proteinValue

    // 基本情報のみで検索
    let basicPredicate = #Predicate<FoodMaster> { food in
      food.brandName == brandName &&
      food.productName == productName &&
      food.portionUnit == portionUnit
    }

    let fetchDescriptor = FetchDescriptor<FoodMaster>(
      predicate: basicPredicate
    )

    // 基本情報で検索した結果から栄養価が一致するものを探す
    if let existingFoodMasters = try? modelContext.fetch(fetchDescriptor) {
      var matchedFoodMaster: FoodMaster? = nil
      
      // 取得した結果から栄養価が一致するものを探す
      for candidate in existingFoodMasters {
        if abs(candidate.calories - caloriesPerUnit) < 0.1 &&
           abs(candidate.carbohydrates - carbsPerUnit) < 0.1 &&
           abs(candidate.fat - fatPerUnit) < 0.1 &&
           abs(candidate.protein - proteinPerUnit) < 0.1 {
          matchedFoodMaster = candidate
          break
        }
      }
      
      if let firstFoodMaster = matchedFoodMaster {
        foodMasterItem = firstFoodMaster
      } else {
        foodMasterItem = FoodMaster(
          brandName: brandName,
          productName: productName,
          calories: caloriesPerUnit,
          carbohydrates: carbsPerUnit,
          fat: fatPerUnit,
          protein: proteinPerUnit,
          portionUnit: portionUnit,
          portion: 1.0  // 1単位あたりに正規化
        )
        modelContext.insert(foodMasterItem!)
      }
    } else {
      foodMasterItem = FoodMaster(
        brandName: brandName,
        productName: productName,
        calories: caloriesPerUnit,
        carbohydrates: carbsPerUnit,
        fat: fatPerUnit,
        protein: proteinPerUnit,
        portionUnit: portionUnit,
        portion: 1.0  // 1単位あたりに正規化
      )
      modelContext.insert(foodMasterItem!)
    }

    let newLogItem = LogItem(
      timestamp: date,
      mealType: mealType,
      numberOfServings: portionValue,  // 入力された数量を使用
      foodMaster: foodMasterItem
    )
    modelContext.insert(newLogItem)
  }

  private func addItemFromPast(_ foodMasterItem: FoodMaster) {
    let newLogItem = LogItem(
      timestamp: date,
      mealType: mealType,
      numberOfServings: numberOfServings,
      foodMaster: foodMasterItem
    )
    modelContext.insert(newLogItem)
    dismiss()
  }

  private func loadMoreItems() {
    guard !searchText.isEmpty else {
      searchResults = []
      currentOffset = 0
      hasMoreData = true
      return
    }

    var descriptor = FetchDescriptor<FoodMaster>(
      predicate: #Predicate<FoodMaster> { food in
        food.brandName.localizedStandardContains(searchText)
          || food.productName.localizedStandardContains(searchText)
      },
      sortBy: [SortDescriptor(\FoodMaster.productName, order: .forward)]
    )
    descriptor.fetchOffset = currentOffset
    descriptor.fetchLimit = pageSize

    if let newItems = try? modelContext.fetch(descriptor) {
      if currentOffset == 0 {
        searchResults = newItems
      } else {
        searchResults.append(contentsOf: newItems)
      }
      currentOffset += newItems.count
      hasMoreData = newItems.count == pageSize
    }
  }
}

// 過去の食事アイテムカード
struct PastItemCard: View {
  let item: FoodMaster

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(item.brandName) \(item.productName)")
            .font(.headline)

          Text("\(item.portionUnit)")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        Spacer()

        Text("\(item.calories, specifier: "%.0f")")
          .font(.title3.bold())
          + Text(" kcal")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      HStack(spacing: 8) {
        MacroNutrientBadge(label: "P", value: item.protein, color: .blue)
        MacroNutrientBadge(label: "F", value: item.fat, color: .yellow)
        MacroNutrientBadge(label: "C", value: item.carbohydrates, color: .green)
      }

      Text("\(item.portion) \(item.portionUnit)")
    }
    .padding()
    .background(Color(UIColor.systemBackground))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
  }
}
