import SwiftData
import SwiftUI

struct AddItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext

  let mealType: MealType
  var selectedDate: Date

  @State private var searchText = ""
  @State private var numberOfServings: String = "1.0"
  @State private var date: Date
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

          if searchText.isEmpty {
            // 検索を促すメッセージ
            VStack(spacing: 16) {
              Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
              
              Text(NSLocalizedString("Search for food", comment: "Search for food"))
                .font(.headline)
                .foregroundColor(.secondary)
              
              Text(NSLocalizedString("Register food in the food tab", comment: "Register food in the food tab"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
