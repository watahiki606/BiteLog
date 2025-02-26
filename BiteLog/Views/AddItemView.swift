import SwiftData
import SwiftUI

struct AddItemView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var items: [Item]

  let preselectedMealType: MealType
  let mealType: MealType
  var selectedDate: Date

  @State private var searchText = ""
  @State private var brandName = ""
  @State private var productName = ""
  @State private var portion: String = ""
  @State private var calories: String = ""
  @State private var protein: String = ""
  @State private var fat: String = ""
  @State private var carbohydrates: String = ""
  @State private var showingPastItems = false
  @State private var date: Date
  @State private var searchResults: [Item] = []
  @State private var currentOffset = 0
  @State private var hasMoreData = true
  private let pageSize = 100

  init(preselectedMealType: MealType, selectedDate: Date) {
    self.preselectedMealType = preselectedMealType
    self.mealType = preselectedMealType
    self.selectedDate = selectedDate
    _date = State(initialValue: selectedDate)
  }

  var body: some View {
    NavigationStack {
      VStack {
        // 検索バー
        SearchBar(text: $searchText, placeholder: "過去の食事を検索")
          .padding()

        if searchText.isEmpty {
          // 新規入力フォーム
          Form {
            Section("基本情報") {
              TextField("ブランド名", text: $brandName)
              TextField("商品名", text: $productName)
              TextField("量 (例: 1個, 100g)", text: $portion)
              Text(mealType.rawValue)
            }

            Section("栄養成分") {
              HStack {
                TextField("カロリー", text: $calories)
                  .keyboardType(.decimalPad)
                Text("kcal")
              }
              HStack {
                TextField("タンパク質", text: $protein)
                  .keyboardType(.decimalPad)
                Text("g")
              }
              HStack {
                TextField("脂質", text: $fat)
                  .keyboardType(.decimalPad)
                Text("g")
              }
              HStack {
                TextField("炭水化物", text: $carbohydrates)
                  .keyboardType(.decimalPad)
                Text("g")
              }
            }

          }

        } else {
          // 検索結果一覧
          List {
            ForEach(searchResults) { item in
              Button {
                addItemFromPast(item)
                dismiss()
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text("\(item.brandName) \(item.productName)")
                      .font(.headline)
                    Spacer()
                    Text("\(item.calories, specifier: "%.0f") kcal")
                      .font(.subheadline)
                  }
                  Text("\(item.portion)")
                    .font(.subheadline)
                  Text(
                    "P:\(item.protein, specifier: "%.1f")g F:\(item.fat, specifier: "%.1f")g C:\(item.carbohydrates, specifier: "%.1f")g"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
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
          }
        }
      }
      .navigationTitle("食事を追加")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            addItem()
            dismiss()
          }
          .disabled(brandName.isEmpty || productName.isEmpty || portion.isEmpty || calories.isEmpty)
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

  private func addItem() {
    let newItem = Item(
      brandName: brandName,
      productName: productName,
      portion: portion,
      calories: Double(calories) ?? 0,
      protein: Double(protein) ?? 0,
      fat: Double(fat) ?? 0,
      carbohydrates: Double(carbohydrates) ?? 0,
      mealType: mealType,
      timestamp: date
    )
    modelContext.insert(newItem)
  }

  private func addItemFromPast(_ item: Item) {
    let newItem = Item(
      brandName: item.brandName,
      productName: item.productName,
      portion: item.portion,
      calories: item.calories,
      protein: item.protein,
      fat: item.fat,
      carbohydrates: item.carbohydrates,
      mealType: mealType,
      timestamp: date
    )
    modelContext.insert(newItem)
  }

  private func selectPastItem(_ item: Item) {
    brandName = item.brandName
    productName = item.productName
    portion = item.portion
    calories = String(item.calories)
    protein = String(item.protein)
    fat = String(item.fat)
    carbohydrates = String(item.carbohydrates)
  }

  private func loadMoreItems() {
    guard !searchText.isEmpty else {
      searchResults = []
      currentOffset = 0
      hasMoreData = true
      return
    }

    var descriptor = FetchDescriptor<Item>(
      predicate: #Predicate<Item> { item in
        item.brandName.localizedStandardContains(searchText)
          || item.productName.localizedStandardContains(searchText)
      },
      sortBy: [SortDescriptor(\Item.timestamp, order: .reverse)]
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

// 検索バーのカスタムビュー
struct SearchBar: View {
  @Binding var text: String
  var placeholder: String

  var body: some View {
    HStack {
      Image(systemName: "magnifyingglass")
        .foregroundColor(.gray)

      TextField(placeholder, text: $text)
        .textFieldStyle(RoundedBorderTextFieldStyle())

      if !text.isEmpty {
        Button(action: {
          text = ""
        }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.gray)
        }
      }
    }
  }
}
