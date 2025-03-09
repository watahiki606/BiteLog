import SwiftData
import SwiftUI

struct AddItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var foodMasters: [FoodMaster]
  @Binding var selectedTab: Int

  let mealType: MealType
  var selectedDate: Date

  @State private var searchText = ""
  @State private var numberOfServings: String = "1.0"
  @State private var date: Date
  @State private var searchResults: [FoodMaster] = []
  @State private var currentOffset = 0
  @State private var hasMoreData = true
  private let pageSize = 100

  init(preselectedMealType: MealType, selectedDate: Date, selectedTab: Binding<Int>) {
    self.mealType = preselectedMealType
    self.selectedDate = selectedDate
    _date = State(initialValue: selectedDate)
    _selectedTab = selectedTab
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
              NSLocalizedString("Search food items", comment: "Search placeholder"),
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

          if foodMasters.isEmpty {
            // マスターデータが0件の場合に表示するビュー
            EmptyFoodMasterPromptView(selectedTab: $selectedTab, dismiss: dismiss)
          } else {
            // 検索結果一覧（検索ワードが空でも全てのアイテムを表示）
            ScrollView {
              LazyVStack(spacing: 12) {
                ForEach(searchResults, id: \.id) { item in
                  Button {
                    addItemFromPast(item)
                    dismiss()
                  } label: {
                    PastItemCard(
                      item: item,
                      onSelect: { foodMaster, servings in
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

                if searchResults.isEmpty && !foodMasters.isEmpty && currentOffset > 0 {
                  VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.magnifyingglass")
                      .font(.system(size: 48))
                      .foregroundColor(.secondary)

                    Text(
                      NSLocalizedString(
                        "No search results found", comment: "No search results message")
                    )
                    .font(.headline)
                    .foregroundColor(.secondary)

                    Text(
                      NSLocalizedString(
                        "Register new food items in the food tab",
                        comment: "No search results message")
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .lineLimit(nil)
                    
                    // 検索結果がない場合にもマスターデータ登録画面タブへのボタンを表示
                    Button {
                      dismiss()
                      selectedTab = 1  // フード管理タブに切り替え
                    } label: {
                      Text(NSLocalizedString("Go to Food Management", comment: "Go to food management button"))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.top, 10)
                  }
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 40)
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
        }
        .onChange(of: searchText) { _, _ in
          searchResults = []
          currentOffset = 0
          hasMoreData = true
          loadMoreItems()
        }
        .onAppear {
          // 初回表示時にデータを読み込む
          if searchResults.isEmpty && currentOffset == 0 {
            loadMoreItems()
          }
        }
      }
    }
  }

  private func addItemFromPast(_ foodMasterItem: FoodMaster) {
    let newLogItem = LogItem(
      timestamp: date,
      mealType: mealType,
      numberOfServings: Double(numberOfServings) ?? 1.0,
      foodMaster: foodMasterItem
    )
    modelContext.insert(newLogItem)
  }

  private func loadMoreItems() {
    var descriptor: FetchDescriptor<FoodMaster>
    
    if searchText.isEmpty {
      // 検索ワードが空の場合は全てのアイテムを取得
      // 使用頻度の高い順にソート、同じ使用頻度の場合は最後に使用された日時の新しい順
      descriptor = FetchDescriptor<FoodMaster>(
        sortBy: [
          SortDescriptor(\FoodMaster.usageCount, order: .reverse),
          SortDescriptor(\FoodMaster.lastUsedDate, order: .reverse),
          SortDescriptor(\FoodMaster.productName, order: .forward)
        ]
      )
    } else {
      // 検索ワードがある場合は検索条件に合うアイテムを取得
      descriptor = FetchDescriptor<FoodMaster>(
        predicate: #Predicate<FoodMaster> { food in
          food.brandName.localizedStandardContains(searchText)
            || food.productName.localizedStandardContains(searchText)
        },
        sortBy: [
          SortDescriptor(\FoodMaster.usageCount, order: .reverse),
          SortDescriptor(\FoodMaster.lastUsedDate, order: .reverse),
          SortDescriptor(\FoodMaster.productName, order: .forward)
        ]
      )
    }
    
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

// マスターデータが0件の場合に表示するビュー
struct EmptyFoodMasterPromptView: View {
  @Binding var selectedTab: Int
  var dismiss: DismissAction
  
  var body: some View {
    VStack(spacing: 10) {
      Spacer()
      
      Image(systemName: "fork.knife")
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      
      Text(NSLocalizedString("No Food Items Registered", comment: "No food items"))
        .font(.title2)
        .fontWeight(.bold)
      
      Text(NSLocalizedString("You need to register food items before you can add meals.", comment: "Register food prompt"))
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)
        .padding(.horizontal, 40)
        .lineLimit(nil)
      
      Button {
        dismiss()
        selectedTab = 1  // フード管理タブに切り替え
      } label: {
        Text(NSLocalizedString("Go to Food Management", comment: "Go to food management button"))
          .fontWeight(.semibold)
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(10)
      }
      .padding(.top, 10)
      
      Spacer()
    }
    .padding()
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
