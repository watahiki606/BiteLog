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

  @State private var showingAddItem = false
  @State private var selectedDate = Date()
  @State private var showingImportCSV = false

  @State private var cachedTotals:
    (date: Date, totals: (calories: Double, protein: Double, fat: Double, carbs: Double))?

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
        DatePicker("日付", selection: $selectedDate, displayedComponents: .date)
          .datePickerStyle(.compact)
          .padding()

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
              }
              .onDelete { indexSet in
                deleteItems(for: mealType, at: indexSet)
              }

              Button(action: {
                showingAddItem = true
              }) {
                Label("食事を追加", systemImage: "plus.circle")
              }
            }
          }
        }
      }
      .navigationTitle("食事記録")
      .sheet(isPresented: $showingAddItem) {
        AddItemView(preselectedMealType: .breakfast)
      }
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
}

struct ItemRow: View {
  let item: Item

  var body: some View {
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
}

#Preview {
  ContentView()
    .modelContainer(for: Item.self, inMemory: true)
}
