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
  @State private var showsDetailNutrients = false

  /// 値が分からなければ「不明」
  private func valueText(_ value: Double?, _ nutrient: some NutrientDisplaying) -> some View {
    Text(value.map { "\(nutrient.format($0))\(nutrient.unit)" }
      ?? NSLocalizedString("Unknown", comment: "Unknown nutrient value"))
      .monospacedDigit()
      .fontWeight(.medium)
  }

  private func card(
    _ nutrient: any NutrientDisplaying, @ViewBuilder value: @escaping () -> some View
  ) -> some View {
    NutrientCardRow(nutrient: nutrient, background: Color(UIColor.secondarySystemGroupedBackground), value: value)
    .listRowAsCard()
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text(NSLocalizedString("Basic Info", comment: "Basic info"))) {
          // 国の食品成分表の食品はブランド名が空。空の行を出すと、値が抜けているように見える
          if !foodMaster.brandName.trimmingCharacters(in: .whitespaces).isEmpty {
            LabeledContent(
              NSLocalizedString("Brand Name", comment: "Brand name"),
              value: foodMaster.brandName
            )
          }
          LabeledContent(
            NSLocalizedString("Product Name", comment: "Product name"),
            value: foodMaster.productName
          )
          LabeledContent(
            NSLocalizedString("Portion Size", comment: "Portion size"),
            value: "\(NutritionFormatter.formatNutrition(foodMaster.portionSize)) \(foodMaster.portionUnit)"
          )
        }

        Section {
          // 食品の入力と同じく、印の丸を添えたカードを画面の地に1枚ずつ並べる
          card(Nutrient.calories) { valueText(foodMaster.calories, Nutrient.calories) }
          card(Nutrient.protein) { valueText(foodMaster.protein, Nutrient.protein) }
          card(Nutrient.fat) { valueText(foodMaster.fat, Nutrient.fat) }
          // 入力と同じく、ラベルの並びの炭水化物、食物繊維、糖質の順に出す
          card(Nutrient.carbs) {
            Text("\(CarbohydrateInput.carbohydrateText(netCarbs: foodMaster.netCarbs, dietaryFiber: foodMaster.dietaryFiber))g")
              .monospacedDigit()
              .fontWeight(.medium)
          }
          card(Nutrient.fiber) { valueText(foodMaster.dietaryFiber, Nutrient.fiber) }
          card(Nutrient.netCarbs) {
            valueText(foodMaster.netCarbs, Nutrient.netCarbs)
          }
          ForEach(NutrientID.labelNutrients, id: \.self) { id in
            card(id) { valueText(foodMaster.nutrients[id], id) }
          }
          // 詳しい栄養素は食品表示に載ることがまれで、数も多いので畳んでおく
          DisclosureHeading(
            NSLocalizedString("Detailed Nutrients", comment: "Disclosure of nutrients rarely on food labels"),
            isExpanded: $showsDetailNutrients
          )
          .listRowAsCard()
          if showsDetailNutrients {
            ForEach(NutrientID.detailNutrients, id: \.self) { id in
              card(id) { valueText(foodMaster.nutrients[id], id) }
            }
          }
        } header: {
          Text(
            String(
              format: NSLocalizedString(
                "Nutrition (per %@ %@)", comment: "Nutrition with portion size and unit"),
              NutritionFormatter.formatNutrition(foodMaster.portionSize),
              foodMaster.portionUnit
            ))
          .sectionHeaderAlignedToCard()
        }
        .headerProminence(.increased)
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
  /// 欄は値を1桁に丸めて出すので、全部を送ると触っていない値まで丸めて保存してしまう
  @State private var initialAddedValues: [NutrientID: String] = [:]
  @State private var showsDetailFields = false
  @State private var isSaving = false
  @State private var failure: OperationFailure?

  @FocusState private var focusedField: FocusedField?

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

  /// キーボードの前後の欄へ移る順番。画面に並ぶ順。畳んだ詳しい栄養素の欄には移らない
  private var fieldOrder: [FocusedField] {
    [.brandName, .productName, .portionSize, .portionUnit, .calories, .protein, .fat, .carbohydrate, .dietaryFiber]
      + (showsDetailFields ? NutrientID.addedNutrients : NutrientID.labelNutrients).map { .added($0) }
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
          // 値が入ると placeholder の項目名が消え、何の欄か分からなくなる。名前は欄の外に出す
          textRow(NSLocalizedString("Brand Name", comment: "Brand name"), text: $brandName, field: .brandName)
          textRow(NSLocalizedString("Product Name", comment: "Product name"), text: $productName, field: .productName)
          LabeledContent(NSLocalizedString("Portion Size", comment: "Portion size")) {
            TextField("1", text: $portionSize)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .monospacedDigit()
              .focused($focusedField, equals: .portionSize)
              .frame(width: 84)
              .inputFieldStyle(isFocused: focusedField == .portionSize)
          }
          textRow(
            NSLocalizedString("Unit", comment: "Unit"), text: $portionUnit, field: .portionUnit,
            placeholder: NSLocalizedString("e.g. piece, g", comment: "Placeholder of the portion unit"))
        }

        Section {
          // 1日の合計や統計と同じく、栄養素を1枚ずつのカードにして画面の地に並べる
          numberCard(Nutrient.calories, text: $calories, field: .calories)
          numberCard(Nutrient.protein, text: $protein, field: .protein)
          numberCard(Nutrient.fat, text: $fat, field: .fat)
          // ラベルと同じ並びで、炭水化物とその内訳の食物繊維を入れる。糖質は引き算で出す
          numberCard(Nutrient.carbs, text: $carbohydrate, field: .carbohydrate)
          numberCard(Nutrient.fiber, text: $dietaryFiber, field: .dietaryFiber)
          // 計算で出るだけの値なので枠を付けない。入力の欄と見分けられるようにする
          NutrientCardRow(
            nutrient: Nutrient.netCarbs, background: Self.cardBackground
          ) {
            HStack(spacing: 6) {
              Text(carbohydrateInput.isValid ? NutritionFormatter.formatNutrition(carbohydrateInput.netCarbs) : "—")
                .monospacedDigit()
                .fontWeight(.medium)
                // 枠の中の数字と右端をそろえる
                .padding(.trailing, 10)
              Text(Nutrient.netCarbs.unit)
                .foregroundStyle(.secondary)
                .frame(minWidth: unitWidth, alignment: .leading)
            }
          }
          .listRowAsCard()
        } header: {
          Text(
            String(
              format: NSLocalizedString("Nutrition (per %@ %@)", comment: "Nutrition with portion size and unit"),
              portionSize.isEmpty ? "1" : portionSize,
              portionUnit.isEmpty ? NSLocalizedString("unit", comment: "Default unit") : portionUnit
            ))
          .sectionHeaderAlignedToCard()
        } footer: {
          if !carbohydrateInput.isValid {
            Text(NSLocalizedString(
              "Dietary fiber can't be more than carbohydrates.",
              comment: "Validation message in the food form"))
            .foregroundColor(.red)
          }
        }
        .headerProminence(.increased)

        Section {
          ForEach(NutrientID.labelNutrients, id: \.self) { addedCard($0) }
          DisclosureHeading(
            NSLocalizedString("Detailed Nutrients", comment: "Disclosure of nutrients rarely on food labels"),
            isExpanded: $showsDetailFields
          )
          .listRowAsCard()
          if showsDetailFields {
            ForEach(NutrientID.detailNutrients, id: \.self) { addedCard($0) }
          }
        } header: {
          Text(NSLocalizedString("Other Nutrients", comment: "Form section for nutrients added later"))
            .sectionHeaderAlignedToCard()
        }
        .headerProminence(.increased)
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

  /// 栄養素のカードの地。行の地を消して画面の地に直接置くので、1日の合計や統計のカードと同じ地にする
  private static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)

  /// 糖質の行の単位を、入力の欄の単位と同じ幅にそろえる
  @ScaledMetric(relativeTo: .subheadline) private var unitWidth: CGFloat = 32

  /// 名前を左に、文字を打つ枠を右に置いた行
  private func textRow(
    _ label: String, text: Binding<String>, field: FocusedField, placeholder: String = ""
  ) -> some View {
    LabeledContent(label) {
      TextField(placeholder, text: text)
        .focused($focusedField, equals: field)
        .inputFieldStyle(isFocused: focusedField == field)
    }
  }

  /// 栄養素1つのカードに、数を打つ枠を置く。カードのどこを押しても枠に打てるようにする
  private func numberCard(
    _ nutrient: any NutrientDisplaying, text: Binding<String>,
    placeholder: String = NSLocalizedString("0", comment: "0"), field: FocusedField
  ) -> some View {
    NutrientCardRow(nutrient: nutrient, background: Self.cardBackground) {
      NumberInputField(
        title: nutrient.localizedName, text: text, placeholder: placeholder, unit: nutrient.unit,
        focus: $focusedField, field: field)
    }
    .contentShape(Rectangle())
    .onTapGesture { focusedField = field }
    .listRowAsCard()
  }

  private func addedCard(_ id: NutrientID) -> some View {
    numberCard(
      id, text: Binding(get: { addedValues[id] ?? "" }, set: { addedValues[id] = $0 }),
      placeholder: NSLocalizedString("Unknown", comment: "Placeholder for an unknown nutrient value"),
      field: .added(id))
  }

  private func focusNextField() {
    let allFields = fieldOrder
    guard let current = focusedField, let idx = allFields.firstIndex(of: current) else {
      focusedField = allFields.first; return
    }
    focusedField = allFields[(idx + 1) % allFields.count]
  }

  private func focusPreviousField() {
    let allFields = fieldOrder
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
        for id in NutrientID.addedNutrients where addedValues[id] ?? "" != initialAddedValues[id] ?? "" {
          if let value = entered[id] {
            dto.nutrients[id] = value
          } else {
            // 空欄にした値は分からないに戻す。送らないとサーバーは前の値を残す
            dto.clearedNutrients.insert(id)
          }
        }
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
    for id in NutrientID.addedNutrients {
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
      for id in NutrientID.addedNutrients {
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
      for id in NutrientID.addedNutrients {
        addedValues[id] = UserDefaults.standard.string(forKey: "\(stateKey)_\(id.rawValue)")
      }
    case .add:
      break
    }
  }

  private func clearSavedState() {
    guard case .quickAdd = mode else { return }
    (["_brandName", "_productName", "_calories", "_carbohydrate", "_dietaryFiber", "_fat", "_protein", "_portionSize", "_portionUnit"]
      + NutrientID.addedNutrients.map { "_\($0.rawValue)" }).forEach {
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
