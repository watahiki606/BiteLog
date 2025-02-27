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
  @State private var numberOfServings: String = "1.0"
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
      ZStack {
        Color(UIColor.systemGroupedBackground)
          .ignoresSafeArea()

        VStack {
          // 検索バー
          HStack {
            Image(systemName: "magnifyingglass")
              .foregroundColor(.secondary)
              .padding(.leading, 8)

            TextField("過去の食事を検索", text: $searchText)
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
                CardView(title: "基本情報") {
                  VStack(spacing: 16) {
                    CustomTextField(
                      icon: "tag.fill",
                      placeholder: "ブランド名",
                      text: $brandName
                    )

                    CustomTextField(
                      icon: "cart.fill",
                      placeholder: "商品名",
                      text: $productName
                    )

                    CustomTextField(
                      icon: "scalemass.fill",
                      placeholder: "量 (例: 1個, 100g)",
                      text: $portion
                    )

                    CustomTextField(
                      icon: "number",
                      placeholder: "食事量 (例: 1.5)",
                      text: $numberOfServings
                    )

                    HStack {
                      Image(systemName: "fork.knife")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                      Text(mealType.rawValue)
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
                CardView(title: "栄養成分") {
                  VStack(spacing: 16) {
                    NutrientInputField(
                      icon: "flame.fill",
                      iconColor: .orange,
                      label: "カロリー",
                      value: $calories,
                      unit: "kcal"
                    )

                    NutrientInputField(
                      icon: "p.circle.fill",
                      iconColor: .blue,
                      label: "タンパク質",
                      value: $protein,
                      unit: "g"
                    )

                    NutrientInputField(
                      icon: "f.circle.fill",
                      iconColor: .yellow,
                      label: "脂質",
                      value: $fat,
                      unit: "g"
                    )

                    NutrientInputField(
                      icon: "c.circle.fill",
                      iconColor: .green,
                      label: "炭水化物",
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
        .navigationTitle("食事を追加")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("キャンセル") { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(action: {
              addItem()
              dismiss()
            }) {
              Text("保存")
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
    let newItem = Item(
      brandName: brandName,
      productName: productName,
      portion: portion,
      calories: Double(calories) ?? 0,
      protein: Double(protein) ?? 0,
      fat: Double(fat) ?? 0,
      carbohydrates: Double(carbohydrates) ?? 0,
      mealType: mealType,
      timestamp: date,
      numberOfServings: Double(numberOfServings) ?? 1.0
    )
    modelContext.insert(newItem)
  }

  private func addItemFromPast(_ item: Item) {
    let newItem = Item(
      brandName: item.brandName,
      productName: item.productName,
      portion: item.portion,
      calories: item.baseCalories,
      protein: item.baseProtein,
      fat: item.baseFat,
      carbohydrates: item.baseCarbohydrates,
      mealType: mealType,
      timestamp: date,
      numberOfServings: Double(numberOfServings) ?? 1.0
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

// カードビュー
struct CardView<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title)
        .font(.headline)
        .foregroundColor(.primary)

      content
    }
    .padding()
    .background(Color(UIColor.systemBackground))
    .cornerRadius(16)
    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
  }
}

// カスタムテキストフィールド
struct CustomTextField: View {
  let icon: String
  let placeholder: String
  @Binding var text: String

  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(.blue)
        .frame(width: 24)

      TextField(placeholder, text: $text)
        .padding(.vertical, 8)
    }
    .padding(.horizontal, 12)
    .background(Color(UIColor.secondarySystemBackground))
    .cornerRadius(10)
  }
}

// 栄養素入力フィールド
struct NutrientInputField: View {
  let icon: String
  let iconColor: Color
  let label: String
  @Binding var value: String
  let unit: String
  @FocusState private var isFocused: Bool

  var body: some View {
    Button {
      isFocused = true
    } label: {
      HStack {
        Image(systemName: icon)
          .foregroundColor(iconColor)
          .frame(width: 24)

        Text(label)
          .foregroundColor(.primary)

        Spacer()

        TextField("0", text: $value)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .frame(width: 80)
          .focused($isFocused)

        Text(unit)
          .foregroundColor(.secondary)
          .frame(width: 40, alignment: .leading)
      }
      .padding(.vertical, 12)
      .padding(.horizontal, 12)
      .background(Color(UIColor.secondarySystemBackground))
      .cornerRadius(10)
    }
    .buttonStyle(PlainButtonStyle())
  }
}

// 過去の食事アイテムカード
struct PastItemCard: View {
  let item: Item

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(item.brandName) \(item.productName)")
            .font(.headline)

          Text(item.portion)
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
    }
    .padding()
    .background(Color(UIColor.systemBackground))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
  }
}

// マクロ栄養素バッジ
struct MacroNutrientBadge: View {
  let label: String
  let value: Double
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.footnote.bold())
        .foregroundColor(color)

      Text("\(value, specifier: "%.1f")g")
        .font(.footnote)
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 8)
    .background(color.opacity(0.1))
    .cornerRadius(8)
  }
}

// ボタンスケールスタイル
struct ScaleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
  }
}
