import SwiftData
import SwiftUI

struct FoodMasterManagementView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var foodMasters: [FoodMaster] = []
  @State private var isDataLoaded = false
  @State private var isInitialLoading = true  // 初回ロード用のフラグを追加

  @State private var searchText = ""
  @State private var showingAddForm = false
  @State private var selectedFoodMaster: FoodMaster?

  // ページネーション用
  @State private var currentPage = 0
  private let pageSize = 20
  @State private var isLoading = false
  @State private var hasMoreData = true

  // キーボードを閉じるためのFocusStateを追加
  @FocusState private var searchFieldIsFocused: Bool

  // 検索テキストが変更されたときのタイマー
  @State private var searchDebounceTimer: Timer?

  var body: some View {
    VStack {
      // 検索バー
      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.secondary)
          .padding(.leading, 8)

        TextField(
          NSLocalizedString("Search food items", comment: "Search food items"), text: $searchText
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
          searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
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
      } else if foodMasters.isEmpty {
        // フードが0件の場合に表示する登録促進ビュー
        EmptyFoodMasterView(showAddForm: $showingAddForm)
      } else {
        // フード一覧
        List {
          ForEach(foodMasters, id: \.self) { foodMaster in
            FoodMasterRow(foodMaster: foodMaster)
              .contentShape(Rectangle())
              .onTapGesture {
                selectedFoodMaster = foodMaster
                // リスト項目をタップしたらキーボードを閉じる
                searchFieldIsFocused = false
              }
              .onAppear {
                // リストの最後のアイテムが表示されたら次のページを読み込む
                if foodMaster == foodMasters.last && hasMoreData && !isLoading {
                  loadMoreContent()
                }
              }
          }
          .onDelete(perform: deleteFoodMasters)

          // ローディングインジケーター（別のセクションとして追加）
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
      }
    }
    .navigationTitle(NSLocalizedString("Manage food", comment: "Manage food"))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          showingAddForm = true
        } label: {
          Image(systemName: "plus")
        }
      }
    }
    .sheet(
      isPresented: $showingAddForm,
      onDismiss: {
        // フォームが閉じられたら再度データをロード
        resetAndSearch()
      }
    ) {
      FoodMasterFormView(mode: .add)
    }
    .sheet(
      item: $selectedFoodMaster,
      onDismiss: {
        selectedFoodMaster = nil
        // 編集フォームが閉じられたら再度データをロード
        resetAndSearch()
      }
    ) { foodMaster in
      FoodMasterFormView(mode: .edit(foodMaster))
    }
    .onAppear {
      // 画面が表示されたときにデータをロード
      if !isDataLoaded {
        loadFoodMasters()
      }
    }
  }

  private func resetAndSearch() {
    // 検索条件が変更されたら、ページをリセットして最初から検索
    isInitialLoading = true  // 検索時は初回ロード状態に戻す
    currentPage = 0
    foodMasters = []
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
              foodMasters = newItems
            }
          } else {
            // 追加ページの場合は追加
            foodMasters.append(contentsOf: newItems)
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

  private func deleteFoodMasters(offsets: IndexSet) {
    for index in offsets {
      let foodMaster = foodMasters[index]
      deleteFoodMasterItem(foodMaster)
    }
  }

  private func deleteFoodMasterItem(_ foodMaster: FoodMaster) {
    // FoodMasterManagerを使用して安全に削除
    FoodMasterManager.safeDeleteFoodMaster(foodMaster: foodMaster, modelContext: modelContext)

    // 削除後にリストを更新
    if let index = foodMasters.firstIndex(where: { $0.id == foodMaster.id }) {
      foodMasters.remove(at: index)
    }
  }
}

// フードが0件の場合に表示するビュー
struct EmptyFoodMasterView: View {
  @Binding var showAddForm: Bool

  var body: some View {
    VStack(spacing: 20) {
      Spacer()

      Image(systemName: "fork.knife")
        .font(.system(size: 70))
        .foregroundColor(.secondary)

      Text(NSLocalizedString("No Food Items", comment: "No food items"))
        .font(.title2)
        .fontWeight(.bold)

      Text(
        NSLocalizedString(
          "Add your first food item to start tracking your nutrition.", comment: "Add food prompt")
      )
      .multilineTextAlignment(.center)
      .foregroundColor(.secondary)
      .padding(.horizontal, 40)
      .lineLimit(nil)

      Button {
        showAddForm = true
      } label: {
        Text(NSLocalizedString("Add Food Item", comment: "Add food item"))
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

// フード行表示用コンポーネント
struct FoodMasterRow: View {
  let foodMaster: FoodMaster

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("\(foodMaster.brandName) \(foodMaster.productName)")
          .font(.headline)

        Spacer()

        Text("\(foodMaster.calories, specifier: "%.0f") kcal")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      HStack {
        Text("P: \(foodMaster.protein, specifier: "%.1f")g")
          .font(.caption)
          .foregroundColor(.blue)

        Text("F: \(foodMaster.fat, specifier: "%.1f")g")
          .font(.caption)
          .foregroundColor(.yellow)

        Text("C: \(foodMaster.carbohydrates, specifier: "%.1f")g")
          .font(.caption)
          .foregroundColor(.green)

        Spacer()

        Text("1 \(foodMaster.portionUnit)")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

// フード追加・編集フォーム
struct FoodMasterFormView: View {
  enum FormMode: Equatable {
    case add
    case edit(FoodMaster)
  }

  let mode: FormMode
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext

  @State private var brandName = ""
  @State private var productName = ""
  @State private var calories = ""
  @State private var carbohydrates = ""
  @State private var fat = ""
  @State private var protein = ""
  @State private var portionUnit = ""

  var title: String {
    switch mode {
    case .add:
      return NSLocalizedString("Add Food Item", comment: "Add food item")
    case .edit:
      return NSLocalizedString("Edit Food Item", comment: "Edit food item")
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text(NSLocalizedString("Basic Info", comment: "Basic info"))) {
          TextField(NSLocalizedString("Brand Name", comment: "Brand name"), text: $brandName)
          TextField(NSLocalizedString("Product Name", comment: "Product name"), text: $productName)
          TextField(
            NSLocalizedString("Portion Unit (e.g. piece, g)", comment: "Portion unit"),
            text: $portionUnit)
        }

        Section(
          header: Text(
            String(
              format: NSLocalizedString("Nutrition (per 1 %@)", comment: "Nutrition with unit"),
              portionUnit.isEmpty ? NSLocalizedString("unit", comment: "Default unit") : portionUnit
            ))
        ) {
          HStack {
            Text(NSLocalizedString("Calories", comment: "Calories"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $calories)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
            Text(NSLocalizedString("kcal", comment: "kcal"))
          }

          HStack {
            Text(NSLocalizedString("Protein", comment: "Protein"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $protein)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
            Text(NSLocalizedString("g", comment: "g"))
          }

          HStack {
            Text(NSLocalizedString("Fat", comment: "Fat"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $fat)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
            Text(NSLocalizedString("g", comment: "g"))
          }

          HStack {
            Text(NSLocalizedString("Carbohydrates", comment: "Carbohydrates"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $carbohydrates)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
            Text(NSLocalizedString("g", comment: "g"))
          }
        }
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Cancel")) {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Save", comment: "Save")) {
            saveFoodMaster()
            dismiss()
          }
          .disabled(brandName.isEmpty || productName.isEmpty || portionUnit.isEmpty)
        }
      }
      .onAppear {
        if case .edit(let foodMaster) = mode {
          // 編集モードの場合、既存の値をフォームにセット
          brandName = foodMaster.brandName
          productName = foodMaster.productName
          calories = String(format: "%.1f", foodMaster.calories)
          carbohydrates = String(format: "%.1f", foodMaster.carbohydrates)
          fat = String(format: "%.1f", foodMaster.fat)
          protein = String(format: "%.1f", foodMaster.protein)
          portionUnit = foodMaster.portionUnit
        }
      }
    }
  }

  private func saveFoodMaster() {
    // 入力値を数値に変換
    let caloriesValue = Double(calories) ?? 0
    let carbohydratesValue = Double(carbohydrates) ?? 0
    let fatValue = Double(fat) ?? 0
    let proteinValue = Double(protein) ?? 0

    switch mode {
    case .add:
      // 新規追加
      let newFoodMaster = FoodMaster(
        brandName: brandName,
        productName: productName,
        calories: caloriesValue,
        carbohydrates: carbohydratesValue,
        fat: fatValue,
        protein: proteinValue,
        portionUnit: portionUnit,
        portion: 1.0  // 1単位あたりに正規化
      )
      modelContext.insert(newFoodMaster)

    case .edit(let foodMaster):
      // 既存データの更新
      foodMaster.brandName = brandName
      foodMaster.productName = productName
      foodMaster.calories = caloriesValue
      foodMaster.carbohydrates = carbohydratesValue
      foodMaster.fat = fatValue
      foodMaster.protein = proteinValue
      foodMaster.portionUnit = portionUnit

      // uniqueKeyも更新
      let caloriesStr = String(format: "%.2f", caloriesValue)
      let carbsStr = String(format: "%.2f", carbohydratesValue)
      let fatStr = String(format: "%.2f", fatValue)
      let proteinStr = String(format: "%.2f", proteinValue)
      foodMaster.uniqueKey =
        "\(brandName)|\(productName)|\(caloriesStr)|\(carbsStr)|\(fatStr)|\(proteinStr)|\(portionUnit)"
    }
  }
}

// Identifiableプロトコル準拠のための拡張
extension FoodMasterFormView.FormMode: Identifiable {
  var id: String {
    switch self {
    case .add:
      return "add"
    case .edit(let foodMaster):
      return "edit_\(foodMaster.id.uuidString)"
    }
  }
}

#Preview {
  FoodMasterManagementView()
    .modelContainer(for: [FoodMaster.self, LogItem.self], inMemory: true)
}
