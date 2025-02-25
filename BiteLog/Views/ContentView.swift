import SwiftData
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Item.timestamp) private var allItems: [Item]

  @State private var selectedDate = Date()
  @State private var showingAddItemFor: (date: Date, mealType: MealType)?
  @State private var showingImportCSV = false
  @State private var dragOffset = CGFloat.zero

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        HStack(spacing: 0) {
          // 前日のビュー
          DayContentView(
            date: Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!,
            selectedDate: selectedDate,
            onAddTapped: { date, mealType in
              showingAddItemFor = (date, mealType)
            },
            modelContext: modelContext
          )
          .frame(width: geometry.size.width)

          // 現在の日付のビュー
          DayContentView(
            date: selectedDate,
            selectedDate: selectedDate,
            onAddTapped: { date, mealType in
              showingAddItemFor = (date, mealType)
            },
            modelContext: modelContext
          )
          .frame(width: geometry.size.width)

          // 翌日のビュー
          DayContentView(
            date: Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!,
            selectedDate: selectedDate,
            onAddTapped: { date, mealType in
              showingAddItemFor = (date, mealType)
            },
            modelContext: modelContext
          )
          .frame(width: geometry.size.width)
        }
        .offset(x: -geometry.size.width + dragOffset)
        .animation(.interactiveSpring(), value: dragOffset)
        .gesture(
          DragGesture()
            .onChanged { gesture in
              dragOffset = gesture.translation.width
            }
            .onEnded { gesture in
              let threshold = geometry.size.width / 3
              if gesture.translation.width > threshold {
                // 右にスワイプ（前日）
                withAnimation(.interactiveSpring()) {
                  selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                  dragOffset = 0
                }
              } else if gesture.translation.width < -threshold {
                // 左にスワイプ（翌日）
                withAnimation(.interactiveSpring()) {
                  selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                  dragOffset = 0
                }
              } else {
                // 元の位置に戻す
                withAnimation(.interactiveSpring()) {
                  dragOffset = 0
                }
              }
            }
        )
      }
      .navigationTitle("食事記録")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          DatePicker(
            "",
            selection: $selectedDate,
            displayedComponents: [.date]
          )
          .labelsHidden()
        }

        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button(action: { showingImportCSV = true }) {
              Label("CSVインポート", systemImage: "square.and.arrow.down")
            }
            // 将来的な機能拡張のためのメニュー項目をここに追加可能
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
      .sheet(
        isPresented: Binding(
          get: { showingAddItemFor != nil },
          set: { if !$0 { showingAddItemFor = nil } }
        )
      ) {
        if let itemInfo = showingAddItemFor {
          AddItemView(
            preselectedMealType: itemInfo.mealType,
            selectedDate: itemInfo.date
          )
          .presentationDetents([.medium, .large])
        }
      }
    }
  }
}

// 日付ごとのコンテンツを表示するビュー
struct DayContentView: View {
  let date: Date
  let selectedDate: Date
  let onAddTapped: (Date, MealType) -> Void
  let modelContext: ModelContext

  var filteredItems: [Item] {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

    let descriptor = FetchDescriptor<Item>(
      predicate: #Predicate<Item> { item in
        item.timestamp >= startOfDay && item.timestamp < endOfDay
      },
      sortBy: [SortDescriptor(\.timestamp)]
    )
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  var dailyTotals: (calories: Double, protein: Double, fat: Double, carbs: Double) {
    filteredItems.reduce((0, 0, 0, 0)) { result, item in
      (
        result.0 + item.calories,
        result.1 + item.protein,
        result.2 + item.fat,
        result.3 + item.carbohydrates
      )
    }
  }

  // 各食事タイプごとのPFC合計を計算する関数
  func mealTypeTotals(for mealType: MealType) -> (
    calories: Double, protein: Double, fat: Double, carbs: Double
  ) {
    let mealItems = filteredItems.filter { $0.mealType == mealType }
    return mealItems.reduce((0, 0, 0, 0)) { result, item in
      (
        result.0 + item.calories,
        result.1 + item.protein,
        result.2 + item.fat,
        result.3 + item.carbohydrates
      )
    }
  }

  var body: some View {
    VStack {
      // 日付表示
      DatePicker(
        "",
        selection: .constant(date),
        displayedComponents: [.date]
      )
      .labelsHidden()
      .datePickerStyle(.compact)
      .disabled(true)

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

      // リスト部分
      List {
        ForEach(MealType.allCases, id: \.self) { mealType in
          Section {
            // 食事タイプごとのPFC合計を表示
            let totals = mealTypeTotals(for: mealType)
            if filteredItems.contains(where: { $0.mealType == mealType }) {
              VStack(alignment: .leading, spacing: 4) {
                Text("カロリー: \(totals.calories, specifier: "%.0f") kcal")
                  .font(.caption)
                Text(
                  "P:\(totals.protein, specifier: "%.1f")g F:\(totals.fat, specifier: "%.1f")g C:\(totals.carbs, specifier: "%.1f")g"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.gray.opacity(0.05))
              .cornerRadius(6)
            }

            ForEach(filteredItems.filter { $0.mealType == mealType }) { item in
              ItemRow(item: item)
                .swipeActions(allowsFullSwipe: true) {
                  Button(role: .destructive) {
                    modelContext.delete(item)
                  } label: {
                    Label("削除", systemImage: "trash")
                  }
                }
            }

            Button(action: {
              onAddTapped(date, mealType)
            }) {
              Label("食事を追加", systemImage: "plus.circle")
            }
          } header: {
            Text(mealType.rawValue)
          }
        }
      }
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
    .sheet(isPresented: $showingEditSheet) {
      EditItemView(item: item)
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: Item.self, inMemory: true)
}
