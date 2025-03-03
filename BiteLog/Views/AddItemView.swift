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
  @State private var numberOfServings: String = "1.0"
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

                    // 数量と単位の入力
                    HStack {
                      CustomTextField(
                        icon: "number",
                        placeholder: NSLocalizedString("Servings (e.g. 1.5)", comment: "Servings field"),
                        text: $numberOfServings
                      )
                      
                      CustomTextField(
                        icon: "text.badge.checkmark",
                        placeholder: NSLocalizedString("Unit", comment: "Portion unit field"),
                        text: $portionUnit
                      )
                    }

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
                    PastItemCard(item: item, onSelect: { foodMaster, servings in
                      let newLogItem = LogItem(
                        timestamp: date,
                        mealType: mealType,
                        numberOfServings: servings,
                        foodMaster: foodMaster
                      )
                      modelContext.insert(newLogItem)
                      dismiss()
                    })
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
              saveItem()
              dismiss()
            }) {
              Text(NSLocalizedString("Save", comment: "Button title"))
                .bold()
            }
            .disabled(
              brandName.isEmpty || productName.isEmpty || numberOfServings.isEmpty || calories.isEmpty)
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

  private func saveItem() {
    // 入力値を数値に変換
    let caloriesValue = Double(calories) ?? 0
    let carbohydratesValue = Double(carbohydrates) ?? 0
    let fatValue = Double(fat) ?? 0
    let proteinValue = Double(protein) ?? 0
    let servingsValue = Double(numberOfServings) ?? 1.0

    // FoodMasterの検索または作成
    var foodMasterItem: FoodMaster?

    if let existingFoodMaster = foodMaster {
      // 既存のFoodMasterを使用
      foodMasterItem = existingFoodMaster
    } else {
      // 新しいFoodMasterを作成
      foodMasterItem = FoodMaster(
        brandName: brandName,
        productName: productName,
        calories: caloriesValue,
        carbohydrates: carbohydratesValue,
        fat: fatValue,
        protein: proteinValue,
        portionUnit: portionUnit,
        portion: 1.0  // 1単位あたりに正規化
      )
      modelContext.insert(foodMasterItem!)
    }

    // LogItemの作成
    let newLogItem = LogItem(
      timestamp: date,
      mealType: mealType,
      numberOfServings: servingsValue,
      foodMaster: foodMasterItem
    )
    modelContext.insert(newLogItem)
    dismiss()
  }

  private func addItemFromPast(_ foodMasterItem: FoodMaster) {
    let newLogItem = LogItem(
      timestamp: date,
      mealType: mealType,
      numberOfServings: Double(numberOfServings) ?? 1.0,
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
  @State private var numberOfServings: String = "1.0"
  var onSelect: (FoodMaster, Double) -> Void

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

      HStack {
        Text("Servings:")
          .font(.subheadline)
          .foregroundColor(.secondary)
        
        TextField("1.0", text: $numberOfServings)
          .keyboardType(.decimalPad)
          .frame(width: 60)
          .multilineTextAlignment(.trailing)
          .padding(4)
          .background(Color(UIColor.secondarySystemBackground))
          .cornerRadius(4)
        
        Text(item.portionUnit)
          .font(.subheadline)
          .foregroundColor(.secondary)
          
        Spacer()
        
        Button(action: {
          onSelect(item, Double(numberOfServings) ?? 1.0)
        }) {
          Text("Add")
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .cornerRadius(8)
        }
      }
    }
    .padding()
    .background(Color(UIColor.systemBackground))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
  }
}
