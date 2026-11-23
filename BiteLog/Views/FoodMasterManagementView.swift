import SwiftUI

struct FoodMasterManagementView: View {
  @State private var foodMasters: [FoodMasterDTO] = []
  @State private var isDataLoaded = false
  @State private var isInitialLoading = true

  @State private var searchText = ""
  @State private var filterMyItems = false
  @State private var showingAddForm = false
  @State private var selectedFoodMaster: FoodMasterDTO?
  @State private var viewingFoodMaster: FoodMasterDTO?

  @State private var currentPage = 0
  private let pageSize = 20
  @State private var isLoading = false
  @State private var hasMoreData = true
  /// 読み込めなかった状態。0件と区別する。同じ見た目で出すと、
  /// 既に登録済みの食品をもう一度登録する操作を誘発する。
  @State private var loadFailed = false
  @State private var failure: OperationFailure?

  @FocusState private var isSearchFocused: Bool
  @State private var searchDebounceTimer: Timer?

  var body: some View {
    contentView
      .searchable(
        text: $searchText,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: Text(NSLocalizedString("Search food items", comment: "Search food items"))
      )
      .searchFocused($isSearchFocused)
      .onChange(of: searchText) { _, _ in
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
          Task { await resetAndSearch() }
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
        .accessibilityLabel(NSLocalizedString("Add Food Item", comment: "Add food item"))
      }
    }
    .sheet(
      isPresented: $showingAddForm,
      onDismiss: { Task { await resetAndSearch() } }
    ) {
      FoodMasterFormView(mode: .add)
    }
    .sheet(
      item: $selectedFoodMaster,
      onDismiss: {
        selectedFoodMaster = nil
        Task { await resetAndSearch() }
      }
    ) { foodMaster in
      FoodMasterFormView(mode: .edit(foodMaster))
    }
    .sheet(item: $viewingFoodMaster, onDismiss: { viewingFoodMaster = nil }) { foodMaster in
      FoodMasterDetailView(foodMaster: foodMaster)
    }
    .onAppear {
      if !isDataLoaded { Task { await loadFoodMasters() } }
    }
    .onReceive(NotificationCenter.default.publisher(for: .allDataDeleted)) { _ in
      foodMasters = []
      isDataLoaded = false
    }
    .operationFailureAlert($failure)
  }

  @ViewBuilder
  private var contentView: some View {
    if isInitialLoading {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if loadFailed && foodMasters.isEmpty {
      LoadFailureView { await resetAndSearch() }
    } else if foodMasters.isEmpty {
      if searchText.isEmpty {
        EmptyFoodMasterView(showAddForm: $showingAddForm)
      } else {
        ContentUnavailableView.search(text: searchText)
      }
    } else {
      List {
        Section {
          ForEach(foodMasters, id: \.id) { foodMaster in
            Button {
              isSearchFocused = false
              if canEdit(foodMaster) {
                selectedFoodMaster = foodMaster
              } else {
                viewingFoodMaster = foodMaster
              }
            } label: {
              FoodMasterRow(foodMaster: foodMaster)
            }
            .buttonStyle(.plain)
            .cardRow()
            .onAppear {
              if foodMaster.id == foodMasters.last?.id && hasMoreData && !isLoading {
                Task { await loadMoreContent() }
              }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              if canEdit(foodMaster) {
                Button(role: .destructive) {
                  deleteFoodMaster(foodMaster)
                } label: {
                  Label(NSLocalizedString("Delete", comment: "Delete"), systemImage: "trash")
                }
              }
            }
          }
        } header: {
          // 絞り込みは検索欄の直下に置き、常に状態が見えるようにする。
          Toggle(isOn: myItemsBinding) {
            Label(
              NSLocalizedString("My Items", comment: "My food items filter"),
              systemImage: "person.fill")
          }
          .toggleStyle(.button)
          .buttonStyle(.bordered)
          .textCase(nil)
        }

        if hasMoreData {
          HStack {
            Spacer()
            if isLoading { ProgressView() }
            Spacer()
          }
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        }
      }
      .listStyle(.insetGrouped)
      .refreshable {
        currentPage = 0
        hasMoreData = true
        await loadFoodMasters()
      }
    }
  }

  private var myItemsBinding: Binding<Bool> {
    Binding(
      get: { filterMyItems },
      set: { newValue in
        filterMyItems = newValue
        Task { await resetAndSearch() }
      }
    )
  }

  private func resetAndSearch() async {
    currentPage = 0
    hasMoreData = true
    await loadFoodMasters()
  }

  private func loadFoodMasters() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let resp = try await APIClient.shared.fetchFoodMasters(
        query: searchText,
        limit: pageSize,
        offset: currentPage * pageSize,
        onlyMine: filterMyItems
      )
      await MainActor.run {
        if currentPage == 0 {
          withAnimation(.easeInOut(duration: 0.3)) { foodMasters = resp.items }
        } else {
          foodMasters.append(contentsOf: resp.items)
        }
        hasMoreData = resp.hasMore
        isDataLoaded = true
        isInitialLoading = false
        loadFailed = false
      }
    } catch {
      await MainActor.run {
        isDataLoaded = true
        isInitialLoading = false
        if foodMasters.isEmpty {
          loadFailed = true
        } else {
          failure = .refreshing(error)
        }
      }
    }
  }

  private func loadMoreContent() async {
    guard !isLoading && hasMoreData else { return }
    currentPage += 1
    await loadFoodMasters()
  }

  private func canEdit(_ foodMaster: FoodMasterDTO) -> Bool {
    AuthManager.shared.isAdmin || foodMaster.isMine == true
  }

  /// 反応を待たせないよう先に行を消し、失敗したら元の位置へ戻す。
  /// 戻さないと、消えたように見えて消えていない行が次の読み込みで蘇る。
  private func deleteFoodMaster(_ foodMaster: FoodMasterDTO) {
    guard let index = foodMasters.firstIndex(where: { $0.id == foodMaster.id }) else { return }
    foodMasters.remove(at: index)
    Task {
      do {
        try await APIClient.shared.deleteFoodMaster(id: foodMaster.id)
      } catch {
        foodMasters.insert(foodMaster, at: min(index, foodMasters.count))
        failure = .deleting(error)
      }
    }
  }
}

// フードマスター詳細表示（読み取り専用）
struct FoodMasterDetailView: View {
  let foodMaster: FoodMasterDTO
  @Environment(\.dismiss) var dismiss
  @State private var detail: FoodMasterDTO?

  private var shown: FoodMasterDTO { detail ?? foodMaster }

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text(NSLocalizedString("Basic Info", comment: "Basic info"))) {
          LabeledContent(
            NSLocalizedString("Brand Name", comment: "Brand name"),
            value: foodMaster.brandName
          )
          LabeledContent(
            NSLocalizedString("Product Name", comment: "Product name"),
            value: foodMaster.productName
          )
          LabeledContent(
            NSLocalizedString("Portion Size", comment: "Portion size"),
            value: "\(NutritionFormatter.formatNutrition(foodMaster.portionSize)) \(foodMaster.portionUnit)"
          )
        }

        Section(
          header: Text(
            String(
              format: NSLocalizedString(
                "Nutrition (per %@ %@)", comment: "Nutrition with portion size and unit"),
              NutritionFormatter.formatNutrition(foodMaster.portionSize),
              foodMaster.portionUnit
            ))
        ) {
          LabeledContent(
            NSLocalizedString("Calories", comment: "Calories"),
            value: "\(NutritionFormatter.formatNutrition(foodMaster.calories)) kcal"
          )
          LabeledContent(
            NSLocalizedString("Protein", comment: "Protein"),
            value: "\(NutritionFormatter.formatNutrition(foodMaster.protein)) g"
          )
          LabeledContent(
            NSLocalizedString("Fat", comment: "Fat"),
            value: "\(NutritionFormatter.formatNutrition(foodMaster.fat)) g"
          )
          // 入力と同じく、ラベルの並びの炭水化物、うち食物繊維、糖質の順に出す
          LabeledContent(
            NSLocalizedString("Carbohydrates", comment: "Carbohydrates"),
            value: "\(CarbohydrateInput.carbohydrateText(netCarbs: shown.netCarbs, dietaryFiber: shown.dietaryFiber)) g"
          )
          LabeledContent(
            NSLocalizedString("Of which dietary fiber", comment: "Dietary fiber as part of carbohydrates"),
            value: "\(NutritionFormatter.formatNutrition(shown.dietaryFiber)) g"
          )
          LabeledContent(
            NSLocalizedString("Sugar", comment: "Sugar"),
            value: "\(NutritionFormatter.formatNutrition(shown.netCarbs)) g"
          )
          ForEach(NutrientID.labelNutrients, id: \.self) { id in
            LabeledContent {
              Text(shown.nutrients[id].map { "\(id.format($0)) \(id.unit)" }
                ?? NSLocalizedString("Unknown", comment: "Unknown nutrient value"))
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(id.localizedName)
                if shown.isSupplemented(id) {
                  Text(NSLocalizedString("Filled from the food composition table", comment: "Supplemented value mark"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
          // 詳しい栄養素はどれも成分表で補った値なので、1つずつに印を付けない
          DisclosureGroup(NSLocalizedString("Detailed Nutrients", comment: "Disclosure of nutrients filled from the composition table")) {
            ForEach(NutrientID.detailNutrients, id: \.self) { id in
              LabeledContent(id.localizedName) {
                Text(shown.nutrients[id].map { "\(id.format($0)) \(id.unit)" }
                  ?? NSLocalizedString("Unknown", comment: "Unknown nutrient value"))
              }
            }
          }
        }
        .headerProminence(.increased)

        if let components = shown.components, !components.isEmpty {
          Section(NSLocalizedString("Food Composition Table", comment: "Composition link section")) {
            ForEach(components) { component in
              LabeledContent(component.name ?? component.foodNumber, value: "\(NutritionFormatter.formatNutrition(component.grams)) g")
            }
          }
        }
      }
      .task {
        // 一覧の食品には、ひも付けと補った印が付いていない。1件を読み直す
        if let fetched = try? await APIClient.shared.fetchFoodMaster(id: foodMaster.id) { detail = fetched }
      }
      .navigationTitle(NSLocalizedString("Food Detail", comment: "Food detail"))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Close", comment: "Close")) { dismiss() }
        }
      }
    }
  }
}

/// 食品マスタが1件も無いときの案内。
struct EmptyFoodMasterView: View {
  @Binding var showAddForm: Bool

  var body: some View {
    ContentUnavailableView {
      Label(
        NSLocalizedString("No Food Items", comment: "No food items"), systemImage: "fork.knife")
    } description: {
      Text(
        NSLocalizedString(
          "Add your first food item to start tracking your nutrition.", comment: "Add food prompt"))
    } actions: {
      Button(NSLocalizedString("Add Food Item", comment: "Add food item")) {
        showAddForm = true
      }
      .buttonStyle(.borderedProminent)
    }
  }
}

/// 食品マスタ1件の行。表示する量は1食分 (portionSize)。
struct FoodMasterRow: View {
  let foodMaster: FoodMasterDTO
  /// 一覧では2行に抑える。似た名前から1つ選ばせる場面では nil を渡す。
  var titleLineLimit: Int? = 2

  var body: some View {
    FoodRow(
      title: FoodRow.displayName(
        brand: foodMaster.brandName, product: foodMaster.productName),
      subtitle: FoodRow.amountText(foodMaster.portionSize, unit: foodMaster.portionUnit),
      values: foodMaster.portionNutritionValues,
      leadingSymbol: foodMaster.isMine == true ? "person.fill" : nil,
      leadingSymbolLabel: NSLocalizedString("My Items", comment: "My food items filter"),
      titleLineLimit: titleLineLimit
    )
  }
}

// フード追加・編集フォーム
struct FoodMasterFormView: View {
  enum FormMode: Equatable {
    case add
    case edit(FoodMasterDTO)
    case quickAdd(initialProductName: String)
  }

  let mode: FormMode
  let onSaved: ((FoodMasterDTO) -> Void)?
  @Environment(\.dismiss) var dismiss

  @State private var brandName = ""
  @State private var productName = ""
  @State private var calories = ""
  /// 炭水化物。保存のときに食物繊維を引いて糖質にする
  @State private var carbohydrate = ""
  @State private var dietaryFiber = ""
  @State private var fat = ""
  @State private var protein = ""
  @State private var portionSize = ""
  @State private var portionUnit = ""
  /// 最初の5項目のあとに足した栄養素の入力。空欄は分からないとして保存する
  @State private var addedValues: [NutrientID: String] = [:]
  /// 開いたときの「その他の栄養素」の欄。直すときは変えた欄だけを送る。
  /// 成分表で補った値も欄に出るので、全部を送るとサーバーは手で入れた値とみなし、補った印を外してしまう
  @State private var initialAddedValues: [NutrientID: String] = [:]
  /// 成分表とのひも付け。食品名から候補を出し、押すと決まる
  @State private var components: [FoodComponent] = []
  @State private var initialComponents: [FoodComponent] = []
  /// 成分表で補った栄養素。欄に印を付ける
  @State private var supplemented: Set<NutrientID> = []
  @State private var isSaving = false
  @State private var failure: OperationFailure?

  @FocusState private var focusedField: FocusedField?

  /// 「その他の栄養素」に並べる栄養素。定義ファイルの並び。
  /// 詳しい栄養素は食品表示に載ることがまれなので欄を出さず、成分表とのひも付けから補う
  private static let addedNutrients = NutrientID.labelNutrients

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

  enum FocusedField: Hashable {
    case brandName, productName, portionSize, portionUnit
    case calories, protein, fat, carbohydrate, dietaryFiber
    case added(NutrientID)
  }

  /// キーボードの前後の欄へ移る順番。画面に並ぶ順
  private static let fieldOrder: [FocusedField] =
    [.brandName, .productName, .portionSize, .portionUnit, .calories, .protein, .fat, .carbohydrate, .dietaryFiber]
    + addedNutrients.map { .added($0) }

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

  init(mode: FormMode, onSaved: ((FoodMasterDTO) -> Void)? = nil) {
    self.mode = mode
    self.onSaved = onSaved

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
          HStack {
            Text(NSLocalizedString("Portion Size", comment: "Portion size"))
            Spacer()
            TextField("1", text: $portionSize)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .portionSize)
              .frame(width: 80)
          }
          TextField(
            NSLocalizedString("Portion Unit (e.g. piece, g)", comment: "Portion unit"),
            text: $portionUnit)
            .focused($focusedField, equals: .portionUnit)
        }

        Section {
          HStack {
            Text(NSLocalizedString("Calories", comment: "Calories"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $calories)
              .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .calories)
            Text(NSLocalizedString("kcal", comment: "kcal"))
          }
          HStack {
            Text(NSLocalizedString("Protein", comment: "Protein"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $protein)
              .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .protein)
            Text(NSLocalizedString("g", comment: "g"))
          }
          HStack {
            Text(NSLocalizedString("Fat", comment: "Fat"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $fat)
              .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .fat)
            Text(NSLocalizedString("g", comment: "g"))
          }
          // ラベルと同じ並びで、炭水化物とその内訳の食物繊維を入れる。糖質は引き算で出す
          HStack {
            Text(NSLocalizedString("Carbohydrates", comment: "Carbohydrates"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $carbohydrate)
              .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .carbohydrate)
            Text(NSLocalizedString("g", comment: "g"))
          }
          HStack {
            Text(NSLocalizedString("Of which dietary fiber", comment: "Dietary fiber as part of carbohydrates"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $dietaryFiber)
              .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .dietaryFiber)
            Text(NSLocalizedString("g", comment: "g"))
          }
          HStack {
            Text(NSLocalizedString("Sugar (Carbohydrates − Fiber)", comment: "Net carbs computed from the inputs"))
            Spacer()
            Text(carbohydrateInput.isValid ? NutritionFormatter.formatNutrition(carbohydrateInput.netCarbs) : "—")
              .foregroundColor(.secondary)
            Text(NSLocalizedString("g", comment: "g")).foregroundColor(.secondary)
          }
        } header: {
          Text(
            String(
              format: NSLocalizedString("Nutrition (per %@ %@)", comment: "Nutrition with portion size and unit"),
              portionSize.isEmpty ? "1" : portionSize,
              portionUnit.isEmpty ? NSLocalizedString("unit", comment: "Default unit") : portionUnit
            ))
        } footer: {
          if !carbohydrateInput.isValid {
            Text(NSLocalizedString(
              "Dietary fiber can't be more than carbohydrates.",
              comment: "Validation message in the food form"))
            .foregroundColor(.red)
          }
        }
        .headerProminence(.increased)
        .font(.subheadline)
        .foregroundColor(.secondary)

        Section {
          ForEach(Self.addedNutrients, id: \.self) { id in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(id.localizedName)
                if supplemented.contains(id) && addedValues[id] == initialAddedValues[id] {
                  Text(NSLocalizedString("Filled from the food composition table", comment: "Supplemented value mark"))
                    .font(.caption2)
                }
              }
              Spacer()
              TextField(
                NSLocalizedString("Unknown", comment: "Placeholder for an unknown nutrient value"),
                text: Binding(get: { addedValues[id] ?? "" }, set: { addedValues[id] = $0 })
              )
              .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .added(id))
              Text(id.definition.unit)
            }
          }
        } header: {
          Text(NSLocalizedString("Other Nutrients", comment: "Form section for nutrients added later"))
        } footer: {
          // 0 と入れれば 0 として、空欄なら分からないとして保存する。合計では分からない品を数えて添える
          Text(NSLocalizedString(
            "Leave blank if the label doesn't show it. Enter 0 only when it is really 0.",
            comment: "Footer of other nutrients"))
        }
        .font(.subheadline)
        .foregroundColor(.secondary)

        CompositionLinkSection(
          productName: productName,
          defaultGrams: CompositionLink.defaultGrams(portionSize: Double(portionSize) ?? 1, portionUnit: portionUnit),
          components: $components)
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Button(action: { focusPreviousField() }) {
            Image(systemName: "chevron.up")
          }
          .accessibilityLabel(NSLocalizedString("Previous field", comment: "Keyboard toolbar"))

          Button(action: { focusNextField() }) {
            Image(systemName: "chevron.down")
          }
          .accessibilityLabel(NSLocalizedString("Next field", comment: "Keyboard toolbar"))
          Spacer()
          Button(NSLocalizedString("Done", comment: "Done")) { focusedField = nil }
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Save", comment: "Save")) {
            Task { await saveAndDismiss() }
          }
          .disabled(
            brandName.isEmpty || productName.isEmpty || portionUnit.isEmpty || !carbohydrateInput.isValid
              || isSaving)
        }
      }
      .operationFailureAlert($failure)
      .onAppear { loadState() }
      .task { await loadComposition() }
      .onDisappear { saveState() }
      .onChange(of: brandName) { _, _ in saveState() }
      .onChange(of: productName) { _, _ in saveState() }
      .onChange(of: calories) { _, _ in saveState() }
      .onChange(of: carbohydrate) { _, _ in saveState() }
      .onChange(of: dietaryFiber) { _, _ in saveState() }
      .onChange(of: fat) { _, _ in saveState() }
      .onChange(of: protein) { _, _ in saveState() }
      .onChange(of: portionSize) { _, _ in saveState() }
      .onChange(of: portionUnit) { _, _ in saveState() }
      .onChange(of: addedValues) { _, _ in saveState() }
    }
  }

  private func focusNextField() {
    let allFields = Self.fieldOrder
    guard let current = focusedField, let idx = allFields.firstIndex(of: current) else {
      focusedField = allFields.first; return
    }
    focusedField = allFields[(idx + 1) % allFields.count]
  }

  private func focusPreviousField() {
    let allFields = Self.fieldOrder
    guard let current = focusedField, let idx = allFields.firstIndex(of: current) else {
      focusedField = allFields.last; return
    }
    focusedField = allFields[idx == 0 ? allFields.count - 1 : idx - 1]
  }

  private func saveAndDismiss() async {
    isSaving = true
    defer { isSaving = false }

    let caloriesValue = Double(calories) ?? 0
    let netCarbsValue = carbohydrateInput.netCarbs
    let dietaryFiberValue = carbohydrateInput.fiber
    let fatValue = Double(fat) ?? 0
    let proteinValue = Double(protein) ?? 0
    let portionSizeValue = Double(portionSize) ?? 1.0
    let resolvedBrandName = brandName.isEmpty ? NSLocalizedString("Unknown", comment: "Unknown brand") : brandName

    do {
      let saved: FoodMasterDTO
      switch mode {
      case .add, .quickAdd:
        let uniqueKey = FoodMasterDTO.createUniqueKey(
          brandName: resolvedBrandName, productName: productName, portionUnit: portionUnit)
        let dto = FoodMasterCreateDTO(
          id: UUID().uuidString,
          brandName: resolvedBrandName,
          productName: productName,
          calories: caloriesValue,
          dietaryFiber: dietaryFiberValue,
          netCarbs: netCarbsValue,
          fat: fatValue,
          protein: proteinValue,
          portionSize: portionSizeValue,
          portionUnit: portionUnit,
          uniqueKey: uniqueKey
        )
        var withAdded = dto
        for (id, value) in enteredAddedValues { withAdded.nutrients[id] = value }
        withAdded.nutrientSource = "manual"
        if !components.isEmpty { withAdded.components = components }
        saved = try await APIClient.shared.createFoodMaster(withAdded)
        clearSavedState()
      case .edit(let foodMaster):
        var dto = FoodMasterUpdateDTO(
          brandName: resolvedBrandName,
          productName: productName,
          calories: caloriesValue,
          dietaryFiber: dietaryFiberValue,
          netCarbs: netCarbsValue,
          fat: fatValue,
          protein: proteinValue,
          portionSize: portionSizeValue,
          portionUnit: portionUnit
        )
        let entered = enteredAddedValues
        for id in Self.addedNutrients where addedValues[id] ?? "" != initialAddedValues[id] ?? "" {
          if let value = entered[id] {
            dto.nutrients[id] = value
          } else {
            // 空欄にした値は分からないに戻す。送らないとサーバーは前の値を残す
            dto.clearedNutrients.insert(id)
          }
        }
        if components != initialComponents { dto.components = components }
        saved = try await APIClient.shared.updateFoodMaster(id: foodMaster.id, dto)
      }
      onSaved?(saved)
      dismiss()
    } catch {
      // 失敗しても閉じると、入力した内容ごと消えたうえに登録できたつもりになる。
      failure = .saving(error)
    }
  }

  private var carbohydrateInput: CarbohydrateInput {
    CarbohydrateInput(carbohydrate: carbohydrate, dietaryFiber: dietaryFiber)
  }

  /// 「その他の栄養素」で数として読めた値。空欄や読めない値は含めない
  private var enteredAddedValues: [NutrientID: Double] {
    addedValues.compactMapValues { Double($0.trimmingCharacters(in: .whitespaces)) }
  }

  private func saveState() {
    guard case .quickAdd = mode else { return }
    for id in Self.addedNutrients {
      UserDefaults.standard.set(addedValues[id] ?? "", forKey: "\(stateKey)_\(id.rawValue)")
    }
    UserDefaults.standard.set(brandName, forKey: "\(stateKey)_brandName")
    UserDefaults.standard.set(productName, forKey: "\(stateKey)_productName")
    UserDefaults.standard.set(calories, forKey: "\(stateKey)_calories")
    UserDefaults.standard.set(carbohydrate, forKey: "\(stateKey)_carbohydrate")
    UserDefaults.standard.set(dietaryFiber, forKey: "\(stateKey)_dietaryFiber")
    UserDefaults.standard.set(fat, forKey: "\(stateKey)_fat")
    UserDefaults.standard.set(protein, forKey: "\(stateKey)_protein")
    UserDefaults.standard.set(portionSize, forKey: "\(stateKey)_portionSize")
    UserDefaults.standard.set(portionUnit, forKey: "\(stateKey)_portionUnit")
  }

  private func loadState() {
    switch mode {
    case .edit(let foodMaster):
      brandName = foodMaster.brandName
      productName = foodMaster.productName
      calories = NutritionFormatter.formatNutrition(foodMaster.calories)
      carbohydrate = CarbohydrateInput.carbohydrateText(
        netCarbs: foodMaster.netCarbs, dietaryFiber: foodMaster.dietaryFiber)
      dietaryFiber = NutritionFormatter.formatNutrition(foodMaster.dietaryFiber)
      fat = NutritionFormatter.formatNutrition(foodMaster.fat)
      protein = NutritionFormatter.formatNutrition(foodMaster.protein)
      portionSize = NutritionFormatter.formatNutrition(foodMaster.portionSize)
      portionUnit = foodMaster.portionUnit
      for id in Self.addedNutrients {
        addedValues[id] = foodMaster.nutrients[id].map(NutritionFormatter.formatNutrition)
      }
      initialAddedValues = addedValues
    case .quickAdd(let initialProductName):
      brandName = UserDefaults.standard.string(forKey: "\(stateKey)_brandName") ?? ""
      productName = UserDefaults.standard.string(forKey: "\(stateKey)_productName") ?? initialProductName
      calories = UserDefaults.standard.string(forKey: "\(stateKey)_calories") ?? ""
      carbohydrate = UserDefaults.standard.string(forKey: "\(stateKey)_carbohydrate") ?? ""
      dietaryFiber = UserDefaults.standard.string(forKey: "\(stateKey)_dietaryFiber") ?? ""
      fat = UserDefaults.standard.string(forKey: "\(stateKey)_fat") ?? ""
      protein = UserDefaults.standard.string(forKey: "\(stateKey)_protein") ?? ""
      portionSize = UserDefaults.standard.string(forKey: "\(stateKey)_portionSize") ?? ""
      portionUnit = UserDefaults.standard.string(forKey: "\(stateKey)_portionUnit") ?? ""
      for id in Self.addedNutrients {
        addedValues[id] = UserDefaults.standard.string(forKey: "\(stateKey)_\(id.rawValue)")
      }
    case .add:
      break
    }
  }

  /// 直すときは、ひも付けと補った印を読む。一覧の食品には付いていない
  private func loadComposition() async {
    guard case .edit(let foodMaster) = mode,
      let detail = try? await APIClient.shared.fetchFoodMaster(id: foodMaster.id)
    else { return }
    components = detail.components ?? []
    initialComponents = components
    supplemented = Set(Self.addedNutrients.filter(detail.isSupplemented))
  }

  private func clearSavedState() {
    guard case .quickAdd = mode else { return }
    (["_brandName", "_productName", "_calories", "_carbohydrate", "_dietaryFiber", "_fat", "_protein", "_portionSize", "_portionUnit"]
      + Self.addedNutrients.map { "_\($0.rawValue)" }).forEach {
      UserDefaults.standard.removeObject(forKey: "\(stateKey)\($0)")
    }
  }
}

extension FoodMasterFormView.FormMode: Identifiable {
  var id: String {
    switch self {
    case .add: return "add"
    case .edit(let fm): return "edit_\(fm.id.uuidString)"
    case .quickAdd(let name): return "quickAdd_\(name.hashValue)"
    }
  }
}

#Preview {
  FoodMasterManagementView()
}
