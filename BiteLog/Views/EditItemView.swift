import SwiftData
import SwiftUI

struct EditItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Bindable var item: LogItem

  @State private var searchText = ""
  @State private var numberOfServings: String = "1"
  @State private var foodMaster: FoodMaster?
  @State private var showingFoodSearch = false
  @State private var searchResults: [FoodMaster] = []
  @State private var currentOffset = 0
  @State private var hasMoreData = true
  private let pageSize = 100
  
  // 栄養素の値を計算プロパティとして定義
  private var calories: String {
    return String(format: "%.2f", foodMaster?.calories ?? 0)
  }
  
  private var protein: String {
    return String(format: "%.2f", foodMaster?.protein ?? 0)
  }
  
  private var fat: String {
    return String(format: "%.2f", foodMaster?.fat ?? 0)
  }
  
  private var carbohydrates: String {
    return String(format: "%.2f", foodMaster?.carbohydrates ?? 0)
  }
  
  private var servingsValue: Double {
    return Double(numberOfServings) ?? 1.0
  }
  
  private var totalCalories: Double {
    return (foodMaster?.calories ?? 0) * servingsValue
  }
  
  private var totalProtein: Double {
    return (foodMaster?.protein ?? 0) * servingsValue
  }
  
  private var totalFat: Double {
    return (foodMaster?.fat ?? 0) * servingsValue
  }
  
  private var totalCarbs: Double {
    return (foodMaster?.carbohydrates ?? 0) * servingsValue
  }

  init(item: LogItem) {
    self.item = item
    _numberOfServings = State(initialValue: String(format: "%.1f", item.numberOfServings))
    _foodMaster = State(initialValue: item.foodMaster)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color(UIColor.systemGroupedBackground)
          .ignoresSafeArea()

        ScrollView {
          VStack(spacing: 24) {
            // 食品情報カード
            CardView(title: NSLocalizedString("Food Item", comment: "Form section title")) {
              VStack(spacing: 16) {
                // 食品情報表示
                if let foodMaster = foodMaster {
                  HStack {
                    VStack(alignment: .leading, spacing: 4) {
                      Text("\(foodMaster.brandName) \(foodMaster.productName)")
                        .font(.headline)
                        .lineLimit(2)
                      
                      Text("\(foodMaster.portionUnit)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                  }
                  .padding(.vertical, 8)
                  .padding(.horizontal, 12)
                  .background(Color(UIColor.secondarySystemBackground))
                  .cornerRadius(10)
                } else {
                  Button(action: {
                    showingFoodSearch = true
                  }) {
                    HStack {
                      Image(systemName: "magnifyingglass")
                        .foregroundColor(.blue)
                      Text(NSLocalizedString("Search for food", comment: "Search for food"))
                        .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                  }
                }
                
                // サービング数入力
                HStack {
                  Text(NSLocalizedString("Servings:", comment: "Servings label"))
                    .font(.body)
                  
                  TextField("1.0", text: $numberOfServings)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                    .frame(width: 80)
                  
                  if let foodMaster = foodMaster {
                    Text(foodMaster.portionUnit)
                      .font(.body)
                      .foregroundColor(.secondary)
                  }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                
                Text(NSLocalizedString("Adjust the serving size to calculate the intake", comment: "Servings explanation"))
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .padding(.bottom, 4)
              }
            }

            // 栄養素カード
            if foodMaster != nil {
              CardView(title: NSLocalizedString("Nutrition", comment: "Form section title")) {
                VStack(spacing: 16) {
                  Text(NSLocalizedString("Values shown as: per serving → total based on servings", comment: "Nutrition explanation"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                  
                  // 栄養素表示を共通化
                  EditNutrientRow(
                    icon: "flame.fill",
                    iconColor: .orange,
                    label: NSLocalizedString("Calories", comment: "Nutrient label"),
                    value: calories,
                    totalValue: totalCalories,
                    unit: "kcal"
                  )
                  
                  EditNutrientRow(
                    icon: "p.circle.fill",
                    iconColor: .blue,
                    label: NSLocalizedString("Protein", comment: "Nutrient label"),
                    value: protein,
                    totalValue: totalProtein,
                    unit: "g"
                  )
                  
                  EditNutrientRow(
                    icon: "f.circle.fill",
                    iconColor: .yellow,
                    label: NSLocalizedString("Fat", comment: "Nutrient label"),
                    value: fat,
                    totalValue: totalFat,
                    unit: "g"
                  )
                  
                  EditNutrientRow(
                    icon: "c.circle.fill",
                    iconColor: .green,
                    label: NSLocalizedString("Carbs", comment: "Nutrient label"),
                    value: carbohydrates,
                    totalValue: totalCarbs,
                    unit: "g"
                  )
                }
              }
            }
          }
          .padding()
        }
        .navigationTitle(NSLocalizedString("Edit Meal", comment: "Navigation title"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(action: {
              saveLogItem()
              dismiss()
            }) {
              Text(NSLocalizedString("Save", comment: "Button title"))
                .bold()
            }
            .disabled(foodMaster == nil || numberOfServings.isEmpty || Double(numberOfServings) == 0)
          }
        }
        .sheet(isPresented: $showingFoodSearch) {
          FoodSearchView(onSelect: { selectedFoodMaster in
            foodMaster = selectedFoodMaster
          })
        }
      }
    }
  }

  private func saveLogItem() {
    // サービング数のみ更新
    item.numberOfServings = servingsValue
    
    // FoodMasterの更新
    if let selectedFoodMaster = foodMaster {
      item.foodMaster = selectedFoodMaster
    }
  }
}

// 食品検索ビュー
struct FoodSearchView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  
  var onSelect: (FoodMaster) -> Void
  
  @State private var searchText = ""
  @State private var searchResults: [FoodMaster] = []
  @State private var currentOffset = 0
  @State private var hasMoreData = true
  private let pageSize = 100
  
  var body: some View {
    NavigationStack {
      VStack {
        // 検索バー
        HStack {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.secondary)
            .padding(.leading, 8)
          
          TextField("食品を検索", text: $searchText)
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
          // 検索を促すメッセージ
          VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 48))
              .foregroundColor(.secondary)
            
            Text(NSLocalizedString("Search for food", comment: "Search for food"))
              .font(.headline)
              .foregroundColor(.secondary)
            
            Text(NSLocalizedString("Register food in the food tab", comment: "Search for food"))
              .font(.subheadline)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          // 検索結果一覧
          List {
            ForEach(searchResults) { item in
              Button {
                onSelect(item)
                dismiss()
              } label: {
                FoodMasterRow(foodMaster: item)
              }
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
            
            if searchResults.isEmpty && !searchText.isEmpty {
              VStack(spacing: 16) {
                Image(systemName: "exclamationmark.magnifyingglass")
                  .font(.system(size: 48))
                  .foregroundColor(.secondary)
                
                Text(NSLocalizedString("No search results found", comment: "No search results message"))
                  .font(.headline)
                  .foregroundColor(.secondary)
                
                Text(NSLocalizedString("Register new food items in the food tab", comment: "No search results message"))
                  .font(.subheadline)
                  .foregroundColor(.secondary)
                  .multilineTextAlignment(.center)
                  .padding(.horizontal)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 40)
              .listRowBackground(Color.clear)
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
        searchResults = []
        currentOffset = 0
        hasMoreData = true
        loadMoreItems()
      }
    }
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

// 栄養素表示用の共通コンポーネント
struct EditNutrientRow: View {
  let icon: String
  let iconColor: Color
  let label: String
  let value: String
  let totalValue: Double
  let unit: String
  
  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(iconColor)
        .frame(width: 24)
      
      Text(label)
        .foregroundColor(.primary)
      
      Spacer()
      
      Text(value.isEmpty ? "0" : value)
        .multilineTextAlignment(.trailing)
      
      Text(unit)
        .foregroundColor(.secondary)
        .frame(width: unit == "kcal" ? 40 : 20, alignment: .leading)
      
      Text("→")
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
      
      Text(String(format: "%.2f", totalValue))
        .foregroundColor(.primary)
      
      Text(unit)
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 12)
    .background(Color(UIColor.secondarySystemBackground))
    .cornerRadius(10)
  }
}
