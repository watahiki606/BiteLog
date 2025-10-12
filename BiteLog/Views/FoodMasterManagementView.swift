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
        Text("P: \(foodMaster.protein, specifier: "%.3f")g")
          .font(.caption)
          .foregroundColor(.blue)

        Text("F: \(foodMaster.fat, specifier: "%.3f")g")
          .font(.caption)
          .foregroundColor(.yellow)

        Text("S: \(foodMaster.sugar, specifier: "%.3f")g")
          .font(.caption)
          .foregroundColor(.green)

        Text("Fiber: \(foodMaster.dietaryFiber, specifier: "%.3f")g")
          .font(.caption)
          .foregroundColor(.brown)

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
    case quickAdd(initialProductName: String)
  }

  let mode: FormMode
  let onSaved: ((FoodMaster) -> Void)?
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext

  @State private var brandName = ""
  @State private var productName = ""
  @State private var calories = ""
  @State private var sugar = ""
  @State private var dietaryFiber = ""
  @State private var fat = ""
  @State private var protein = ""
  @State private var portionUnit = ""

  @FocusState private var focusedField: FocusedField?
  
  // 状態保存用のキー
  private var stateKey: String {
    switch mode {
    case .quickAdd(let productName):
      return "quickAdd_\(productName)"
    case .add:
      return "add"
    case .edit(let foodMaster):
      return "edit_\(foodMaster.id.uuidString)"
    }
  }
  
  enum FocusedField {
    case brandName
    case productName
    case portionUnit
    case calories
    case protein
    case fat
    case sugar
    case dietaryFiber
  }

  var title: String {
    switch mode {
    case .add:
      return NSLocalizedString("Add Food Item", comment: "Add food item")
    case .edit:
      return NSLocalizedString("Edit Food Item", comment: "Edit food item")
    case .quickAdd:
      return NSLocalizedString("Quick Add Food", comment: "Quick add food")
    }
  }
  
  init(mode: FormMode, onSaved: ((FoodMaster) -> Void)? = nil) {
    self.mode = mode
    self.onSaved = onSaved
    
    // 初期値を設定（アプリ切り替え時の状態復元に対応）
    switch mode {
    case .quickAdd(let initialProductName):
      _productName = State(initialValue: initialProductName)
      _portionUnit = State(initialValue: "")
    case .add:
      _portionUnit = State(initialValue: "")
    case .edit:
      break
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text(NSLocalizedString("Basic Info", comment: "Basic info"))) {
          TextField(NSLocalizedString("Brand Name", comment: "Brand name"), text: $brandName)
            .focused($focusedField, equals: .brandName)
          TextField(NSLocalizedString("Product Name", comment: "Product name"), text: $productName)
            .focused($focusedField, equals: .productName)
          TextField(
            NSLocalizedString("Portion Unit (e.g. piece, g)", comment: "Portion unit"),
            text: $portionUnit)
            .focused($focusedField, equals: .portionUnit)
        }

        Section(
          header: Text(
            String(
              format: NSLocalizedString("Nutrition (per %@)", comment: "Nutrition with unit"),
              portionUnit.isEmpty ? NSLocalizedString("unit", comment: "Default unit") : portionUnit
            ))
        ) {
          HStack {
            Text(NSLocalizedString("Calories", comment: "Calories"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $calories)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .calories)
            Text(NSLocalizedString("kcal", comment: "kcal"))
          }

          HStack {
            Text(NSLocalizedString("Protein", comment: "Protein"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $protein)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .protein)
            Text(NSLocalizedString("g", comment: "g"))
          }

          HStack {
            Text(NSLocalizedString("Fat", comment: "Fat"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $fat)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .fat)
            Text(NSLocalizedString("g", comment: "g"))
          }

          HStack {
            Text(NSLocalizedString("Sugar", comment: "Sugar"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $sugar)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .sugar)
            Text(NSLocalizedString("g", comment: "g"))
          }

          HStack {
            Text(NSLocalizedString("Dietary Fiber", comment: "Dietary Fiber"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $dietaryFiber)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .dietaryFiber)
            Text(NSLocalizedString("g", comment: "g"))
          }

          // 炭水化物の合計を表示（編集不可）
          HStack {
            Text(NSLocalizedString("Carbohydrates (Sugar + Fiber)", comment: "Carbohydrates"))
            Spacer()
            Text(String(format: "%.3f", (Double(sugar) ?? 0) + (Double(dietaryFiber) ?? 0)))
              .foregroundColor(.secondary)
            Text(NSLocalizedString("g", comment: "g"))
              .foregroundColor(.secondary)
          }
        }
        .headerProminence(.increased)
        .font(.subheadline)
        .foregroundColor(.secondary)
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Button(action: {
            focusPreviousField()
          }) {
            Image(systemName: "chevron.up")
          }
          
          Button(action: {
            focusNextField()
          }) {
            Image(systemName: "chevron.down")
          }
          
          Spacer()
          
          Button(NSLocalizedString("Done", comment: "Done")) {
            focusedField = nil
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Cancel")) {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Save", comment: "Save")) {
            let savedFoodMaster = saveFoodMaster()
            if let savedFood = savedFoodMaster {
              clearSavedState() // 保存成功時に状態をクリア
              onSaved?(savedFood)
            }
            dismiss()
          }
          .disabled(brandName.isEmpty || productName.isEmpty || portionUnit.isEmpty)
        }
      }
      .onAppear {
        loadState()
      }
      .onDisappear {
        saveState()
      }
      .onChange(of: brandName) { _, _ in saveState() }
      .onChange(of: productName) { _, _ in saveState() }
      .onChange(of: calories) { _, _ in saveState() }
      .onChange(of: sugar) { _, _ in saveState() }
      .onChange(of: dietaryFiber) { _, _ in saveState() }
      .onChange(of: fat) { _, _ in saveState() }
      .onChange(of: protein) { _, _ in saveState() }
      .onChange(of: portionUnit) { _, _ in saveState() }
    }
  }
  
  private func focusNextField() {
    let allFields: [FocusedField] = [.brandName, .productName, .portionUnit, .calories, .protein, .fat, .sugar, .dietaryFiber]
    
    guard let currentField = focusedField,
          let currentIndex = allFields.firstIndex(of: currentField) else {
      focusedField = allFields.first
      return
    }
    
    let nextIndex = (currentIndex + 1) % allFields.count
    focusedField = allFields[nextIndex]
  }
  
  private func focusPreviousField() {
    let allFields: [FocusedField] = [.brandName, .productName, .portionUnit, .calories, .protein, .fat, .sugar, .dietaryFiber]
    
    guard let currentField = focusedField,
          let currentIndex = allFields.firstIndex(of: currentField) else {
      focusedField = allFields.last
      return
    }
    
    let previousIndex = currentIndex == 0 ? allFields.count - 1 : currentIndex - 1
    focusedField = allFields[previousIndex]
  }

  private func saveFoodMaster() -> FoodMaster? {
    // 入力値を数値に変換
    let caloriesValue = Double(calories) ?? 0
    let sugarValue = Double(sugar) ?? 0
    let dietaryFiberValue = Double(dietaryFiber) ?? 0
    let fatValue = Double(fat) ?? 0
    let proteinValue = Double(protein) ?? 0

    switch mode {
    case .add, .quickAdd:
      // 新規追加
      let newFoodMaster = FoodMaster(
        brandName: brandName.isEmpty ? NSLocalizedString("Unknown", comment: "Unknown brand") : brandName,
        productName: productName,
        calories: caloriesValue,
        sugar: sugarValue,
        dietaryFiber: dietaryFiberValue,
        fat: fatValue,
        protein: proteinValue,
        portionUnit: portionUnit,
        portion: 1.0  // 1単位あたりに正規化
      )
      modelContext.insert(newFoodMaster)
      return newFoodMaster

    case .edit(let foodMaster):
      // 既存データの更新
      foodMaster.brandName = brandName
      foodMaster.productName = productName
      foodMaster.calories = caloriesValue
      foodMaster.sugar = sugarValue
      foodMaster.dietaryFiber = dietaryFiberValue
      foodMaster.fat = fatValue
      foodMaster.protein = proteinValue
      foodMaster.portionUnit = portionUnit

      // uniqueKeyも更新
      let caloriesStr = String(format: "%.2f", caloriesValue)
      let sugarStr = String(format: "%.2f", sugarValue)
      let fiberStr = String(format: "%.2f", dietaryFiberValue)
      let fatStr = String(format: "%.2f", fatValue)
      let proteinStr = String(format: "%.2f", proteinValue)
      foodMaster.uniqueKey =
        "\(brandName)|\(productName)|\(caloriesStr)|\(sugarStr)|\(fiberStr)|\(fatStr)|\(proteinStr)|\(portionUnit)"
      return foodMaster
    }
  }
  
  private func saveState() {
    // クイック追加モードの場合のみ状態を保存
    guard case .quickAdd = mode else { return }
    
    UserDefaults.standard.set(brandName, forKey: "\(stateKey)_brandName")
    UserDefaults.standard.set(productName, forKey: "\(stateKey)_productName")
    UserDefaults.standard.set(calories, forKey: "\(stateKey)_calories")
    UserDefaults.standard.set(sugar, forKey: "\(stateKey)_sugar")
    UserDefaults.standard.set(dietaryFiber, forKey: "\(stateKey)_dietaryFiber")
    UserDefaults.standard.set(fat, forKey: "\(stateKey)_fat")
    UserDefaults.standard.set(protein, forKey: "\(stateKey)_protein")
    UserDefaults.standard.set(portionUnit, forKey: "\(stateKey)_portionUnit")
  }
  
  private func loadState() {
    switch mode {
    case .edit(let foodMaster):
      // 編集モードの場合、既存の値をフォームにセット
      brandName = foodMaster.brandName
      productName = foodMaster.productName
      calories = String(format: "%.3f", foodMaster.calories)
      sugar = String(format: "%.3f", foodMaster.sugar)
      dietaryFiber = String(format: "%.3f", foodMaster.dietaryFiber)
      fat = String(format: "%.3f", foodMaster.fat)
      protein = String(format: "%.3f", foodMaster.protein)
      portionUnit = foodMaster.portionUnit
      
    case .quickAdd(let initialProductName):
      // 保存された状態があるかチェック
      let savedBrandName = UserDefaults.standard.string(forKey: "\(stateKey)_brandName") ?? ""
      let savedProductName = UserDefaults.standard.string(forKey: "\(stateKey)_productName") ?? initialProductName
      let savedCalories = UserDefaults.standard.string(forKey: "\(stateKey)_calories") ?? ""
      let savedSugar = UserDefaults.standard.string(forKey: "\(stateKey)_sugar") ?? ""
      let savedDietaryFiber = UserDefaults.standard.string(forKey: "\(stateKey)_dietaryFiber") ?? ""
      let savedFat = UserDefaults.standard.string(forKey: "\(stateKey)_fat") ?? ""
      let savedProtein = UserDefaults.standard.string(forKey: "\(stateKey)_protein") ?? ""
      let savedPortionUnit = UserDefaults.standard.string(forKey: "\(stateKey)_portionUnit") ?? ""

      brandName = savedBrandName
      productName = savedProductName
      calories = savedCalories
      sugar = savedSugar
      dietaryFiber = savedDietaryFiber
      fat = savedFat
      protein = savedProtein
      portionUnit = savedPortionUnit
      
    case .add:
      // 通常の追加モードの場合、特に何もしない
      break
    }
  }
  
  private func clearSavedState() {
    // クイック追加モードの場合のみ保存された状態をクリア
    guard case .quickAdd = mode else { return }
    
    UserDefaults.standard.removeObject(forKey: "\(stateKey)_brandName")
    UserDefaults.standard.removeObject(forKey: "\(stateKey)_productName")
    UserDefaults.standard.removeObject(forKey: "\(stateKey)_calories")
    UserDefaults.standard.removeObject(forKey: "\(stateKey)_sugar")
    UserDefaults.standard.removeObject(forKey: "\(stateKey)_dietaryFiber")
    UserDefaults.standard.removeObject(forKey: "\(stateKey)_fat")
    UserDefaults.standard.removeObject(forKey: "\(stateKey)_protein")
    UserDefaults.standard.removeObject(forKey: "\(stateKey)_portionUnit")
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
    case .quickAdd(let productName):
      return "quickAdd_\(productName.hashValue)"
    }
  }
}

#Preview {
  FoodMasterManagementView()
    .modelContainer(for: [FoodMaster.self, LogItem.self], inMemory: true)
}
