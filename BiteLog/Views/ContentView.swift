import SwiftData
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext

  var filteredItems: [Item] {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: selectedDate)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

    let descriptor = FetchDescriptor<Item>(
      predicate: #Predicate<Item> { item in
        item.timestamp >= startOfDay && item.timestamp < endOfDay
      },
      sortBy: [SortDescriptor(\.timestamp)]
    )
    return (try? modelContext.fetch(descriptor) as [Item]) ?? []
  }

  @Query(sort: \Item.timestamp) private var allItems: [Item]

  @State private var showingAddItemFor: MealType?
  @State private var selectedDate = Date()
  @State private var showingImportCSV = false

  @State private var cachedTotals:
    (date: Date, totals: (calories: Double, protein: Double, fat: Double, carbs: Double))?

  @State private var dragOffset = CGFloat.zero

  var dailyTotals: (calories: Double, protein: Double, fat: Double, carbs: Double) {
    if let cached = cachedTotals, Calendar.current.isDate(cached.date, inSameDayAs: selectedDate) {
      return cached.totals
    }

    let totals = filteredItems.reduce((0, 0, 0, 0)) { result, item in
      (
        result.0 + item.calories,
        result.1 + item.protein,
        result.2 + item.fat,
        result.3 + item.carbohydrates
      )
    }

    cachedTotals = (selectedDate, totals)
    return totals
  }

  var body: some View {
    NavigationStack {
      VStack {
        HStack {
          Button(action: { moveDate(by: -1) }) {
            Image(systemName: "chevron.left")
          }
          .padding()

          DatePicker(
            "",
            selection: $selectedDate,
            displayedComponents: [.date]
          )
          .labelsHidden()
          .datePickerStyle(.compact)

          Button(action: { moveDate(by: 1) }) {
            Image(systemName: "chevron.right")
          }
          .padding()
        }

        // 日別集計
        VStack(spacing: 8) {
          Text("1日の合計")
            .font(.headline)
          Text("カロリー: \(dailyTotals.calories, specifier: "%.0f") kcal")
          Text("タンパク質: \(dailyTotals.protein, specifier: "%.1f")g")
          Text("脂質: \(dailyTotals.fat, specifier: "%.1f")g")
          Text("炭水化物: \(dailyTotals.carbs, specifier: "%.1f")g")
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)

        List {
          ForEach(MealType.allCases, id: \.self) { mealType in
            Section(mealType.rawValue) {
              ForEach(filteredItems.filter { $0.mealType == mealType }) { item in
                ItemRow(item: item)
                  .swipeActions(allowsFullSwipe: true) {
                    Button(role: .destructive) {
                      if let index = filteredItems.filter({ $0.mealType == mealType }).firstIndex(
                        of: item)
                      {
                        deleteItems(for: mealType, at: IndexSet([index]))
                      }
                    } label: {
                      Label("削除", systemImage: "trash")
                    }
                  }
              }

              Button(action: {
                showingAddItemFor = mealType
              }) {
                Label("食事を追加", systemImage: "plus.circle")
              }
              .sheet(
                isPresented: Binding(
                  get: { showingAddItemFor == mealType },
                  set: { if !$0 { showingAddItemFor = nil } }
                )
              ) {
                AddItemView(preselectedMealType: mealType, selectedDate: selectedDate)
              }
            }
          }
        }
        .scrollDisabled(abs(dragOffset) > 0)
      }
      .offset(x: dragOffset)
      .animation(.interactiveSpring(), value: dragOffset)
      .simultaneousGesture(
        DragGesture()
          .onChanged { gesture in
            if abs(gesture.translation.width) > abs(gesture.translation.height) {
              dragOffset = gesture.translation.width
            }
          }
          .onEnded { gesture in
            if abs(gesture.translation.width) > abs(gesture.translation.height) {
              dragOffset = 0
              if gesture.translation.width > 100 {
                moveDate(by: -1)
              } else if gesture.translation.width < -100 {
                moveDate(by: 1)
              }
            }
          }
      )
      .navigationTitle("食事記録")
      .sheet(isPresented: $showingImportCSV) {
        ImportCSVView()
      }
      .toolbar {
        Button(action: {
          showingImportCSV = true
        }) {
          Label("CSVインポート", systemImage: "square.and.arrow.down")
        }
      }
    }
  }

  private func deleteItems(for mealType: MealType, at offsets: IndexSet) {
    let itemsToDelete = filteredItems.filter { $0.mealType == mealType }
    offsets.forEach { index in
      modelContext.delete(itemsToDelete[index])
    }
  }

  private func moveDate(by days: Int) {
    if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
      selectedDate = newDate
    }
  }
}

struct ItemRow: View {
  let item: Item
  @State private var showingEditSheet = false

  var body: some View {
    Button {
      showingEditSheet = true
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(item.brandName) \(item.productName)")
          .font(.headline)
        Text("\(item.portion) (\(item.calories, specifier: "%.0f") kcal)")
          .font(.subheadline)
        Text(
          "P:\(item.protein, specifier: "%.1f")g F:\(item.fat, specifier: "%.1f")g C:\(item.carbohydrates, specifier: "%.1f")g"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .sheet(isPresented: $showingEditSheet) {
      EditItemView(item: item)
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: Item.self, inMemory: true)
}
