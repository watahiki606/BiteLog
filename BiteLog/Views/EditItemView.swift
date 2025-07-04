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
    if let foodMaster = foodMaster {
      return String(format: "%.2f", foodMaster.calories)
    } else if item.isMasterDeleted, let backupCalories = item.backupCalories {
      return String(format: "%.2f", backupCalories)
    }
    return "0.00"
  }
  
  private var protein: String {
    if let foodMaster = foodMaster {
      return String(format: "%.2f", foodMaster.protein)
    } else if item.isMasterDeleted, let backupProtein = item.backupProtein {
      return String(format: "%.2f", backupProtein)
    }
    return "0.00"
  }
  
  private var fat: String {
    if let foodMaster = foodMaster {
      return String(format: "%.2f", foodMaster.fat)
    } else if item.isMasterDeleted, let backupFat = item.backupFat {
      return String(format: "%.2f", backupFat)
    }
    return "0.00"
  }
  
  private var sugar: String {
    if let foodMaster = foodMaster {
      return String(format: "%.2f", foodMaster.sugar)
    } else if item.isMasterDeleted, let backupSugar = item.backupSugar {
      return String(format: "%.2f", backupSugar)
    }
    return "0.00"
  }
  
  private var dietaryFiber: String {
    if let foodMaster = foodMaster {
      return String(format: "%.2f", foodMaster.dietaryFiber)
    } else if item.isMasterDeleted, let backupDietaryFiber = item.backupDietaryFiber {
      return String(format: "%.2f", backupDietaryFiber)
    }
    return "0.00"
  }
  
  private var servingsValue: Double {
    return Double(numberOfServings) ?? 1.0
  }
  
  private var totalCalories: Double {
    if let foodMaster = foodMaster {
      return foodMaster.calories * servingsValue
    } else if item.isMasterDeleted, let backupCalories = item.backupCalories {
      return backupCalories * servingsValue
    }
    return 0
  }
  
  private var totalProtein: Double {
    if let foodMaster = foodMaster {
      return foodMaster.protein * servingsValue
    } else if item.isMasterDeleted, let backupProtein = item.backupProtein {
      return backupProtein * servingsValue
    }
    return 0
  }
  
  private var totalFat: Double {
    if let foodMaster = foodMaster {
      return foodMaster.fat * servingsValue
    } else if item.isMasterDeleted, let backupFat = item.backupFat {
      return backupFat * servingsValue
    }
    return 0
  }
  
  private var totalSugar: Double {
    if let foodMaster = foodMaster {
      return foodMaster.sugar * servingsValue
    } else if item.isMasterDeleted, let backupSugar = item.backupSugar {
      return backupSugar * servingsValue
    }
    return 0
  }
  
  private var totalDietaryFiber: Double {
    if let foodMaster = foodMaster {
      return foodMaster.dietaryFiber * servingsValue
    } else if item.isMasterDeleted, let backupDietaryFiber = item.backupDietaryFiber {
      return backupDietaryFiber * servingsValue
    }
    return 0
  }
  
  private var totalCarbs: Double {
    return totalSugar + totalDietaryFiber
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
                    }
                    
                    Spacer()
                  }
                  .padding(.vertical, 8)
                  .padding(.horizontal, 12)
                  .background(Color(UIColor.secondarySystemBackground))
                  .cornerRadius(10)
                } else if item.isMasterDeleted {
                  // 削除されたFoodMasterの情報を表示
                  HStack {
                    VStack(alignment: .leading, spacing: 4) {
                      HStack {
                        Text("\(item.backupBrandName ?? "") \(item.backupProductName ?? "")")
                          .font(.headline)
                          .lineLimit(2)
                          .foregroundColor(.secondary)
                          .strikethrough()
                        
                        Text(NSLocalizedString("(Deleted)", comment: "Deleted Food indicator"))
                          .font(.caption)
                          .foregroundColor(.red)
                          .padding(.horizontal, 4)
                          .padding(.vertical, 2)
                          .background(Color.red.opacity(0.1))
                          .cornerRadius(4)
                      }
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
            if foodMaster != nil || item.isMasterDeleted {
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
                    label: NSLocalizedString("Sugar", comment: "Nutrient label"),
                    value: sugar,
                    totalValue: totalSugar,
                    unit: "g"
                  )
                  
                  EditNutrientRow(
                    icon: "leaf.circle.fill",
                    iconColor: .brown,
                    label: NSLocalizedString("Dietary Fiber", comment: "Nutrient label"),
                    value: dietaryFiber,
                    totalValue: totalDietaryFiber,
                    unit: "g"
                  )
                  
                  // 炭水化物の合計を表示
                  HStack {
                    Image(systemName: "c.circle.fill")
                      .foregroundColor(.gray)
                      .frame(width: 24)
                    
                    Text(NSLocalizedString("Carbs (Sugar + Fiber)", comment: "Nutrient label"))
                      .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(String(format: "%.2f", Double(sugar)! + Double(dietaryFiber)!))
                      .multilineTextAlignment(.trailing)
                      .foregroundColor(.secondary)
                    
                    Text("g")
                      .foregroundColor(.secondary)
                      .frame(width: 20, alignment: .leading)
                    
                    Text("→")
                      .foregroundColor(.secondary)
                      .padding(.horizontal, 4)
                    
                    Text(String(format: "%.2f", totalCarbs))
                      .foregroundColor(.secondary)
                    
                    Text("g")
                      .foregroundColor(.secondary)
                  }
                  .padding(.vertical, 12)
                  .padding(.horizontal, 12)
                  .background(Color(UIColor.secondarySystemBackground))
                  .cornerRadius(10)
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
            .disabled((foodMaster == nil && !item.isMasterDeleted) || numberOfServings.isEmpty || Double(numberOfServings) == 0)
          }
        }
        .sheet(isPresented: $showingFoodSearch) {
          FoodSearchView(onSelect: { selectedFoodMaster in
            foodMaster = selectedFoodMaster
            // 最後に使用したサービング数を初期値として設定
            numberOfServings = String(format: "%.1f", selectedFoodMaster.lastNumberOfServings)
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
      // 最後に使用したサービング数を更新
      selectedFoodMaster.lastNumberOfServings = servingsValue
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
          
          TextField(NSLocalizedString("Search food items", comment: "Search placeholder"), text: $searchText)
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
            
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          // 検索結果一覧
          List {
            ForEach(searchResults, id: \.id) { item in
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
