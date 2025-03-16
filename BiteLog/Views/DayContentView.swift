import SwiftData
import SwiftUI

// 日付ごとのコンテンツを表示するビュー
struct DayContentView: View {
  let date: Date
  let selectedDate: Date
  let onAddTapped: (Date, MealType) -> Void
  let modelContext: ModelContext
  // 削除後の更新を強制するためのState
  @State private var refreshID = UUID()

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
                label: NSLocalizedString("Sugar", comment: "Nutrient label"),
                value: dailyTotals.sugar,
                unit: "g",
                format: "%.1f",
                icon: "s.circle.fill",
                color: .green
              )

              NutrientRow(
                label: NSLocalizedString("Dietary Fiber", comment: "Nutrient label"),
                value: dailyTotals.fiber,
                unit: "g",
                format: "%.1f",
                icon: "leaf.circle.fill",
                color: .brown
              )

              NutrientRow(
                label: NSLocalizedString("Carbs (Sugar + Fiber)", comment: "Nutrient label"),
                value: dailyTotals.carbs,
                unit: "g",
                format: "%.1f",
                icon: "c.circle.fill",
                color: .gray
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
            VStack(alignment: .leading, spacing: 8) {
              // セクションヘッダー
              HStack {
                Text(mealType.localizedName)
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
                    value: totals.sugar, unit: "g", name: "S", color: .green, icon: "s.circle.fill")
                  NutrientBadge(
                    value: totals.fiber, unit: "g", name: "Fiber", color: .brown,
                    icon: "leaf.circle.fill")
                }
                .padding(.vertical, 4)
                .padding(.horizontal)
              }

              Divider()

              // 食事アイテム
              let mealItems = filteredItems.filter { $0.mealType == mealType }
              if mealItems.isEmpty {
                // 前日のミールがある場合、前日のミールを追加するボタンを表示
                if hasPreviousDayItems(for: mealType) {
                  Button(action: {
                    // 前日のミールを今日に複製
                    copyPreviousDayMeals(for: mealType)
                  }) {
                    HStack {
                      Image(systemName: "arrow.counterclockwise")
                        .font(.body)
                        .foregroundColor(.blue)

                      Text(
                        String(
                          format: NSLocalizedString(
                            "Copy yesterday's %@", comment: "Copy previous day meal"),
                          mealType.localizedName
                        )
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

                EmptyMealView(mealType: mealType) {
                  onAddTapped(date, mealType)
                }
              } else {
                List {
                  ForEach(mealItems, id: \.id) { item in
                    ItemRowView(item: item)
                      .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                      .listRowBackground(Color.clear)

                  }
                  .onDelete(perform: { indexSet in
                    // 削除対象のアイテムを取得
                    let itemsToDelete = indexSet.map { mealItems[$0] }
                    // アイテムを削除
                    for item in itemsToDelete {
                      // FoodMasterの使用頻度をデクリメント
                      FoodMasterManager.decrementUsageCountForLogItemDeletion(
                        logItem: item, modelContext: modelContext)
                      modelContext.delete(item)
                    }

                    // 変更を保存
                    do {
                      try modelContext.save()
                      // 更新を強制するためにrefreshIDを更新
                      refreshID = UUID()
                    } catch {
                      print("Error saving after deletion: \(error)")
                    }
                  })
                  EmptyMealView(mealType: mealType) {
                    onAddTapped(date, mealType)
                  }
                  .listRowBackground(Color.clear)
                  .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                }
                .scrollDisabled(true)
                .listStyle(.plain)
                .frame(height: CGFloat(mealItems.count + 1) * 58)
                .id(refreshID)  // リストを強制的に再描画
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

  private var filteredItems: [LogItem] {
    let calendar = Calendar.current
    
    // 現在の日付の開始時刻と終了時刻を計算
    let startOfDay = calendar.startOfDay(for: date)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
    
    let descriptor = FetchDescriptor<LogItem>(
      predicate: #Predicate<LogItem> { logItem in
        logItem.timestamp >= startOfDay && logItem.timestamp < endOfDay
      },
      sortBy: [SortDescriptor(\.timestamp)]
    )
    
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  // 前日の特定の食事タイプのアイテムを取得するメソッド
  private func previousDayItems(for mealType: MealType) -> [LogItem] {
    let calendar = Calendar.current
    
    // 現在の日付から前日を計算
    let currentDate = date
    let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate)!
    
    // 前日の日付の開始時刻と終了時刻を計算
    let startOfPreviousDay = calendar.startOfDay(for: previousDay)
    let endOfPreviousDay = calendar.date(byAdding: .day, value: 1, to: startOfPreviousDay)!
    
    let allPreviousDayDescriptor = FetchDescriptor<LogItem>(
      predicate: #Predicate<LogItem> { logItem in
        logItem.timestamp >= startOfPreviousDay && logItem.timestamp < endOfPreviousDay
      },
      sortBy: [SortDescriptor(\.timestamp)]
    )
    
    guard let allItems = try? modelContext.fetch(allPreviousDayDescriptor) else {
      return []
    }
    
    let filteredItems = allItems.filter { item in
      return item.mealType.rawValue == mealType.rawValue
    }
    
    return filteredItems
  }

  // 前日の特定の食事タイプのアイテムが存在するかチェックするメソッド
  private func hasPreviousDayItems(for mealType: MealType) -> Bool {
    return !previousDayItems(for: mealType).isEmpty
  }

  private var dailyTotals:
    (calories: Double, protein: Double, fat: Double, sugar: Double, fiber: Double, carbs: Double)
  {
    filteredItems.reduce((0, 0, 0, 0, 0, 0)) { result, item in
      (
        result.0 + item.calories,
        result.1 + item.protein,
        result.2 + item.fat,
        result.3 + item.sugar,
        result.4 + item.dietaryFiber,
        result.5 + item.carbohydrates
      )
    }
  }

  // 各食事タイプごとのPFC合計を計算する関数
  private func mealTypeTotals(for mealType: MealType) -> (
    calories: Double, protein: Double, fat: Double, sugar: Double, fiber: Double, carbs: Double
  ) {
    let mealItems = filteredItems.filter { $0.mealType == mealType }
    return mealItems.reduce((0, 0, 0, 0, 0, 0)) { result, item in
      (
        result.0 + item.calories,
        result.1 + item.protein,
        result.2 + item.fat,
        result.3 + item.sugar,
        result.4 + item.dietaryFiber,
        result.5 + item.carbohydrates
      )
    }
  }

  // 前日のミールを今日に複製するメソッド
  private func copyPreviousDayMeals(for mealType: MealType) {
    let prevItems = previousDayItems(for: mealType)

    for prevItem in prevItems {
      // 新しいLogItemを作成して今日の日付で保存
      let newItem = LogItem(
        timestamp: date,
        mealType: mealType,
        numberOfServings: prevItem.numberOfServings,
        foodMaster: prevItem.foodMaster
      )

      modelContext.insert(newItem)

      // FoodMasterの使用頻度を更新
      if let foodMaster = prevItem.foodMaster {
        foodMaster.usageCount += 1
        foodMaster.lastUsedDate = Date()
        foodMaster.lastNumberOfServings = prevItem.numberOfServings
      }
    }

    // 変更を保存
    do {
      try modelContext.save()
      // 更新を強制するためにrefreshIDを更新
      refreshID = UUID()
    } catch {
      print("Error saving after copying meals: \(error)")
    }
  }
}
