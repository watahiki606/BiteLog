import SwiftData
import SwiftUI

struct AddItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Binding var selectedTab: Int

  let mealType: MealType
  var selectedDate: Date

  @State private var searchText = ""
  @State private var numberOfServings: String = "1.0"
  @State private var date: Date
  @State private var searchResults: [FoodMaster] = []
  @State private var isDataLoaded = false
  @State private var isInitialLoading = true  // 初回ロード用のフラグ
  
  // ページネーション用
  @State private var currentPage = 0
  @State private var isLoading = false
  @State private var hasMoreData = true
  private let pageSize = 20  // ページサイズを小さくする
  
  // キーボードを閉じるためのFocusState
  @FocusState private var searchFieldIsFocused: Bool
  
  // 検索テキストが変更されたときのタイマー
  @State private var searchDebounceTimer: Timer?

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
            .focused($searchFieldIsFocused)  // FocusStateを設定
            .onTapGesture {
              searchFieldIsFocused = true  // 明示的にフォーカスを設定
            }
            .onChange(of: searchText) { oldValue, newValue in
              // 検索テキストが変更されたら、タイマーをリセットして新しいタイマーを設定
              searchDebounceTimer?.invalidate()
              searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                // タイマーが発火したら検索を実行
                resetAndSearch()
              }
            }

            if !searchText.isEmpty {
              Button(action: {
                searchText = ""
                resetAndSearch()
              }) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundColor(.secondary)
                  .padding(.trailing, 8)
              }
            }
            
            // 検索中の場合のみCancelボタンを表示
            if searchFieldIsFocused {
              Button(NSLocalizedString("Cancel", comment: "Cancel search")) {
                searchText = ""
                searchFieldIsFocused = false  // キーボードを閉じる
                resetAndSearch()
              }
              .transition(.move(edge: .trailing).combined(with: .opacity))
            }
          }
          .padding(.horizontal)
          .padding(.top, 8)

          if isInitialLoading {
            // 初回データロード中の表示
            ProgressView()
              .padding()
          } else if searchResults.isEmpty && !isDataLoaded {
            // マスターデータが0件の場合に表示するビュー
            EmptyFoodMasterPromptView(selectedTab: $selectedTab, dismiss: dismiss)
          } else {
            // 検索結果一覧
            List {
              ForEach(searchResults, id: \.id) { item in
                Button {
                  let newLogItem = LogItem(
                    timestamp: date,
                    mealType: mealType,
                    numberOfServings: item.lastNumberOfServings,
                    foodMaster: item
                  )
                  modelContext.insert(newLogItem)
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
                  // リストの最後のアイテムが表示されたら次のページを読み込む
                  if item == searchResults.last && hasMoreData && !isLoading {
                    loadMoreContent()
                  }
                }
              }
              
              // ローディングインジケーター
              if hasMoreData {
                Section {
                  HStack {
                    Spacer()
                    if isLoading {
                      ProgressView()
                    }
                    Spacer()
                  }
                  .padding(.vertical, 8)
                  .id("loadingIndicator")  // IDを固定して不要な再描画を防止
                }
              }
            }
            .listStyle(.insetGrouped)
            
            // 検索結果がない場合のメッセージ
            if searchResults.isEmpty && isDataLoaded {
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
        }
        .navigationTitle(NSLocalizedString("Add Meal", comment: "Navigation title"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
          }
        }
        .onAppear {
          // 画面が表示されたときにデータをロード
          if !isDataLoaded {
            loadFoodMasters()
          }
        }
      }
    }
  }

  private func resetAndSearch() {
    // 検索条件が変更されたら、ページをリセットして最初から検索
    currentPage = 0
    hasMoreData = true
    loadFoodMasters()
  }

  private func loadFoodMasters() {
    guard !isLoading else { return }
    isLoading = true

    // FetchDescriptorを使用してデータをロード
    let sortDescriptors = [
      SortDescriptor(\FoodMaster.usageCount, order: .reverse),
      SortDescriptor(\FoodMaster.lastUsedDate, order: .reverse),
      SortDescriptor(\FoodMaster.productName, order: .forward),
    ]

    var descriptor = FetchDescriptor<FoodMaster>(sortBy: sortDescriptors)

    // 検索条件がある場合は絞り込み
    if !searchText.isEmpty {
      descriptor.predicate = #Predicate<FoodMaster> { foodMaster in
        foodMaster.brandName.localizedStandardContains(searchText)
          || foodMaster.productName.localizedStandardContains(searchText)
      }
    }

    // ページネーション設定
    descriptor.fetchLimit = pageSize
    descriptor.fetchOffset = currentPage * pageSize

    Task {
      do {
        // バックグラウンドスレッドでデータをフェッチ
        let newItems = try modelContext.fetch(descriptor)

        // メインスレッドでUIを更新
        await MainActor.run {
          // 新しいアイテムを追加
          if currentPage == 0 {
            // 最初のページの場合は置き換え
            withAnimation(.easeInOut(duration: 0.3)) {
              searchResults = newItems
            }
          } else {
            // 追加ページの場合は追加
            searchResults.append(contentsOf: newItems)
          }

          // 次のページがあるかどうかを判定
          hasMoreData = newItems.count == pageSize

          isDataLoaded = true
          isInitialLoading = false
          isLoading = false
        }
      } catch {
        await MainActor.run {
          isLoading = false
          isDataLoaded = true
          isInitialLoading = false
        }
      }
    }
  }

  private func loadMoreContent() {
    guard !isLoading && hasMoreData else { return }

    currentPage += 1
    loadFoodMasters()
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
  @State private var numberOfServings: String
  var onSelect: (FoodMaster, Double) -> Void
  
  // 現在のサービング数を計算するための計算プロパティ
  private var currentServings: Double {
    return Double(numberOfServings) ?? item.lastNumberOfServings
  }

  init(item: FoodMaster, onSelect: @escaping (FoodMaster, Double) -> Void) {
    self.item = item
    self.onSelect = onSelect
    // 最後に使用したサービング数を初期値として設定
    _numberOfServings = State(initialValue: String(format: "%.1f", item.lastNumberOfServings))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(item.brandName) \(item.productName)")
            .font(.headline)

        }

        Spacer()

        // カロリーを現在のサービング数に応じて計算
        Text("\(item.calories * currentServings, specifier: "%.0f")")
          .font(.title3.bold())
          + Text(" kcal")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      HStack(spacing: 8) {
        // 栄養素の値も現在のサービング数に応じて計算
        MacroNutrientBadge(label: "P", value: item.protein * currentServings, color: .blue)
        MacroNutrientBadge(label: "F", value: item.fat * currentServings, color: .yellow)
        MacroNutrientBadge(label: "S", value: item.sugar * currentServings, color: .green)
        MacroNutrientBadge(label: "Fiber", value: item.dietaryFiber * currentServings, color: .brown)
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
          onSelect(item, currentServings)
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
