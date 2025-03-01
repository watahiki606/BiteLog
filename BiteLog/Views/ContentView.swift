import SwiftData
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @EnvironmentObject private var languageManager: LanguageManager

  @State private var selectedDate = Date()
  @State private var showingAddItemFor: (date: Date, mealType: MealType)?
  @State private var showingImportCSV = false
  @State private var showingSettings = false
  @State private var showingDatePicker = false

  var body: some View {
    NavigationStack {
      DayContentView(
        date: selectedDate,
        selectedDate: selectedDate,
        onAddTapped: { date, mealType in
          showingAddItemFor = (date, mealType)
        },
        modelContext: modelContext
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          HStack {
            Button(action: {
              selectedDate = selectedDate.addingTimeInterval(-86400)
            }) {
              Image(systemName: "chevron.left")
            }

            Button(action: {
              showingDatePicker = true
            }) {
              Text(dateFormatter.string(from: selectedDate))
                .font(.headline)
            }

            Button(action: {
              selectedDate = selectedDate.addingTimeInterval(86400)
            }) {
              Image(systemName: "chevron.right")
            }
          }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
          Menu {
            Button(action: { showingImportCSV = true }) {
              Label("CSVインポート", systemImage: "square.and.arrow.down")
            }
            Button(action: { showingSettings = true }) {
              Label("Settings", systemImage: "gearshape")
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
      .sheet(isPresented: $showingDatePicker) {
        DatePickerSheet(selectedDate: $selectedDate, isPresented: $showingDatePicker)
      }
      .sheet(isPresented: $showingImportCSV) {
        ImportCSVView()
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
    }
  }

  private var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }
}

// 日付ごとのコンテンツを表示するビュー
struct DayContentView: View {
  let date: Date
  let selectedDate: Date
  let onAddTapped: (Date, MealType) -> Void
  let modelContext: ModelContext

  var body: some View {
    VStack {
      // スクロール全体
      ScrollView {
        // 上部にスペースを追加して、ナビゲーションバーとの重なりを防ぐ
        Color.clear.frame(height: 1)
          .padding(.top, 8)

        VStack(spacing: 16) {
          // 日別集計
          VStack(spacing: 0) {
            Text(NSLocalizedString("Daily Total", comment: "Daily nutrition summary"))
              .font(.headline)
              .padding(.bottom, 8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal)
              .padding(.top, 12)

            Divider()

            VStack(spacing: 12) {
              NutrientRow(
                label: NSLocalizedString("Calories", comment: "Nutrient label"),
                value: dailyTotals.calories,
                unit: "kcal",
                format: "%.1f",
                icon: "flame.fill",
                color: .orange
              )

              NutrientRow(
                label: NSLocalizedString("Protein", comment: "Nutrient label"),
                value: dailyTotals.protein,
                unit: "g",
                format: "%.1f",
                icon: "p.circle.fill",
                color: .blue
              )

              NutrientRow(
                label: NSLocalizedString("Fat", comment: "Nutrient label"),
                value: dailyTotals.fat,
                unit: "g",
                format: "%.1f",
                icon: "f.circle.fill",
                color: .yellow
              )

              NutrientRow(
                label: NSLocalizedString("Carbs", comment: "Nutrient label"),
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
                  Label(
                    NSLocalizedString("Add", comment: "Add button"), systemImage: "plus.circle.fill"
                  )
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
                    value: totals.calories, unit: "kcal",
                    name: NSLocalizedString("Calories", comment: "Nutrient short name"),
                    color: .orange,
                    icon: "flame.fill")
                  NutrientBadge(
                    value: totals.protein, unit: "g",
                    name: "P", color: .blue, icon: "p.circle.fill"
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
                List {
                  ForEach(mealItems) { item in
                    ItemRowView(item: item)
                      .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                      .listRowBackground(Color.clear)
                      .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                          withAnimation {
                            modelContext.delete(item)
                          }
                        } label: {
                          Label("削除", systemImage: "trash")
                        }
                      }
                  }
                  .onDelete(perform: { indexSet in
                    for index in indexSet {
                      modelContext.delete(mealItems[index])
                    }
                  })
                }
                .scrollDisabled(true)
                .listStyle(.plain)
                .frame(height: CGFloat(mealItems.count) * 110)
                .background(Color.clear)
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

  private var filteredItems: [Item] {
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

  private var dailyTotals: (calories: Double, protein: Double, fat: Double, carbs: Double) {
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
  private func mealTypeTotals(for mealType: MealType) -> (
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
}

// 新しいアイテム行ビュー
struct ItemRowView: View {
  let item: Item
  @State private var showingEditSheet = false

  var body: some View {
    Button {
      showingEditSheet = true
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("\(item.brandName) \(item.productName)")
              .font(.headline)
              .lineLimit(1)

            Text("\(item.portion) × \(item.numberOfServings, specifier: "%.1f")")
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
    }
    .buttonStyle(PlainButtonStyle())
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
        .foregroundColor(color.opacity(0.8))
        .font(.system(size: 14, weight: .medium))
        .frame(width: 22)

      Text(label)
        .font(.system(size: 15))
        .foregroundColor(.primary.opacity(0.9))

      Spacer()

      Text("\(value, specifier: format)")
        .font(.system(size: 15, weight: .medium))
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
      HStack(spacing: 3) {
        Text(name)
          .font(.system(size: 12, weight: .medium))
      }
      .foregroundColor(color.opacity(0.8))

      Text("\(value, specifier: value >= 100 ? "%.0f" : "%.1f")\(unit)")
        .font(.system(size: 13, weight: .medium))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 5)
    .background(color.opacity(0.06))
    .cornerRadius(4)
  }
}

// 空の食事セクション
struct EmptyMealView: View {
  let mealType: MealType
  let onAddTap: () -> Void

  var body: some View {
    Button(action: onAddTap) {
      HStack {
        Image(systemName: "plus")
          .font(.body)
          .foregroundColor(.accentColor)

        Text(
          String(
            format: NSLocalizedString("Add %@", comment: "Add meal type"), mealType.localizedName)
        )
        .font(.subheadline)
        .foregroundColor(.primary.opacity(0.8))
      }
      .frame(maxWidth: .infinity)
      .padding()
      .background(Color(UIColor.systemBackground))
      .cornerRadius(6)
    }
    .buttonStyle(PlainButtonStyle())
    .padding(.horizontal)
  }
}
struct MacroView: View {
  let label: String
  let value: Double
  let color: Color

  var body: some View {
    HStack(spacing: 3) {
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(color.opacity(0.7))

      Text("\(value, specifier: "%.1f")g")
        .font(.system(size: 13))
        .foregroundColor(.primary.opacity(0.8))
    }
    .padding(.vertical, 3)
    .padding(.horizontal, 6)
    .background(color.opacity(0.04))
    .cornerRadius(3)
  }
}

// 日付選択シート
struct DatePickerSheet: View {
  @Binding var selectedDate: Date
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      VStack {
        DatePicker(
          NSLocalizedString("Select Date", comment: "Date picker title"),
          selection: $selectedDate,
          displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .padding()
      }
      .navigationTitle(NSLocalizedString("Select Date", comment: "Date picker title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Done", comment: "Button title")) {
            isPresented = false
          }
        }
      }
    }
    .presentationDetents([.medium])
  }
}
