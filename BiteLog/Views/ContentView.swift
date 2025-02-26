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
      .navigationTitle("Log")
      .sheet(isPresented: $showingImportCSV) {
        ImportCSVView()
      }
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
      // スクロール全体
      ScrollView {
        VStack(spacing: 16) {
          // 日別集計
          VStack(spacing: 0) {
            Text("1日の合計")
              .font(.headline)
              .padding(.bottom, 8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal)
              .padding(.top, 12)

            Divider()

            VStack(spacing: 12) {
              NutrientRow(
                label: "カロリー",
                value: dailyTotals.calories,
                unit: "kcal",
                format: "%.0f",
                icon: "flame.fill",
                color: .orange
              )

              NutrientRow(
                label: "タンパク質",
                value: dailyTotals.protein,
                unit: "g",
                format: "%.1f",
                icon: "p.circle.fill",
                color: .blue
              )

              NutrientRow(
                label: "脂質",
                value: dailyTotals.fat,
                unit: "g",
                format: "%.1f",
                icon: "f.circle.fill",
                color: .yellow
              )

              NutrientRow(
                label: "炭水化物",
                value: dailyTotals.carbs,
                unit: "g",
                format: "%.1f",
                icon: "c.circle.fill",
                color: .green
              )
            }
            .padding(.vertical, 8)
          }
          .background(Color(UIColor.systemBackground))
          .cornerRadius(12)
          .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
          .padding(.horizontal)
          .padding(.vertical, 8)

          // 食事リスト
          ForEach(MealType.allCases, id: \.self) { mealType in
            VStack(spacing: 8) {
              // セクションヘッダー
              HStack {
                Text(mealType.rawValue)
                  .font(.headline)
                  .foregroundColor(.primary)

                Spacer()

                Button(action: {
                  onAddTapped(date, mealType)
                }) {
                  Label("追加", systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
              }
              .padding(.horizontal)

              // 食事タイプごとのPFC合計を表示
              let totals = mealTypeTotals(for: mealType)
              if filteredItems.contains(where: { $0.mealType == mealType }) {
                HStack(spacing: 12) {
                  NutrientBadge(
                    value: totals.calories, unit: "kcal", name: "カロリー", color: .orange,
                    icon: "flame.fill")
                  NutrientBadge(
                    value: totals.protein, unit: "g", name: "P", color: .blue, icon: "p.circle.fill"
                  )
                  NutrientBadge(
                    value: totals.fat, unit: "g", name: "F", color: .yellow, icon: "f.circle.fill")
                  NutrientBadge(
                    value: totals.carbs, unit: "g", name: "C", color: .green, icon: "c.circle.fill")
                }
                .padding(.vertical, 8)
                .padding(.horizontal)
              }

              // 食事アイテム
              let mealItems = filteredItems.filter { $0.mealType == mealType }
              if mealItems.isEmpty {
                EmptyMealView(mealType: mealType) {
                  onAddTapped(date, mealType)
                }
              } else {
                ForEach(mealItems) { item in
                  ItemCardView(item: item, modelContext: modelContext)
                    .padding(.horizontal)
                }
              }
            }
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
            .padding(.horizontal)
          }
        }
        .padding(.vertical)
      }
      .background(Color(UIColor.systemGroupedBackground))
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

// 栄養素行のコンポーネント
struct NutrientRow: View {
  let label: String
  let value: Double
  let unit: String
  let format: String
  let icon: String
  let color: Color

  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(color)
        .font(.system(size: 16, weight: .semibold))
        .frame(width: 24)

      Text(label)
        .font(.system(size: 16))

      Spacer()

      Text("\(value, specifier: format)")
        .font(.system(size: 16, weight: .semibold))
        + Text(" \(unit)")
        .font(.system(size: 14))
        .foregroundColor(.secondary)
    }
    .padding(.horizontal)
  }
}

// 栄養素バッジコンポーネント
struct NutrientBadge: View {
  let value: Double
  let unit: String
  let name: String
  let color: Color
  let icon: String

  var body: some View {
    VStack(spacing: 2) {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .font(.system(size: 10))
        Text(name)
          .font(.system(size: 12, weight: .medium))
      }
      .foregroundColor(color)

      Text("\(value, specifier: value >= 100 ? "%.0f" : "%.1f")\(unit)")
        .font(.system(size: 14, weight: .semibold))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
    .background(color.opacity(0.1))
    .cornerRadius(8)
  }
}

// 空の食事セクション
struct EmptyMealView: View {
  let mealType: MealType
  let onAddTap: () -> Void

  var body: some View {
    Button(action: onAddTap) {
      HStack {
        Image(systemName: "plus.circle")
          .font(.title2)
          .foregroundColor(.blue)

        Text("\(mealType.rawValue)を追加")
          .font(.subheadline)
      }
      .frame(maxWidth: .infinity)
      .padding()
      .background(Color(UIColor.systemBackground))
      .cornerRadius(10)
    }
    .buttonStyle(PlainButtonStyle())
    .padding(.horizontal)
  }
}

// アイテムカードビュー
struct ItemCardView: View {
  let item: Item
  let modelContext: ModelContext
  @State private var showingEditSheet = false
  @State private var offset: CGFloat = 0
  @State private var isSwiping = false

  var body: some View {
    ZStack {
      // 削除ボタン背景
      HStack {
        Spacer()
        Button(action: {
          withAnimation {
            modelContext.delete(item)
          }
        }) {
          Image(systemName: "trash.fill")
            .foregroundColor(.white)
            .frame(width: 60, height: 60)
            .background(Color.red)
            .cornerRadius(10)
        }
      }

      // メインカード
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("\(item.brandName) \(item.productName)")
              .font(.headline)
              .lineLimit(1)

            Text("\(item.portion)")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }

          Spacer()

          Text("\(item.calories, specifier: "%.0f")")
            .font(.system(size: 18, weight: .bold))
            + Text(" kcal")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        }

        HStack(spacing: 12) {
          MacroView(label: "P", value: item.protein, color: .blue)
          MacroView(label: "F", value: item.fat, color: .yellow)
          MacroView(label: "C", value: item.carbohydrates, color: .green)
        }
      }
      .padding()
      .background(Color(UIColor.systemBackground))
      .cornerRadius(10)
      .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
      .offset(x: offset)
      .contentShape(Rectangle())  // タップ可能な領域を明確に定義
      .onTapGesture {
        if offset != 0 {
          // スワイプオープン状態ならカードを閉じる
          withAnimation(.spring()) {
            offset = 0
          }
        } else {
          // カードが閉じた状態なら編集画面を表示
          showingEditSheet = true
        }
      }
      .gesture(
        DragGesture()
          .onChanged { gesture in
            if gesture.translation.width < 0 {  // 左スワイプのみ検出
              offset = max(gesture.translation.width, -60)
            }
          }
          .onEnded { gesture in
            withAnimation(.spring()) {
              if gesture.translation.width < -40 {
                // スワイプが十分なら削除ボタンを表示
                offset = -60
              } else {
                // 不十分なスワイプならリセット
                offset = 0
              }
            }
          }
      )
    }
    .sheet(isPresented: $showingEditSheet) {
      EditItemView(item: item)
    }
  }
}

struct MacroView: View {
  let label: String
  let value: Double
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(color)

      Text("\(value, specifier: "%.1f")g")
        .font(.system(size: 14))
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 8)
    .background(color.opacity(0.1))
    .cornerRadius(6)
  }
}
