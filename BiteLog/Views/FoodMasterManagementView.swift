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

  @FocusState private var searchFieldIsFocused: Bool
  @State private var searchDebounceTimer: Timer?

  var body: some View {
    VStack {
      HStack(spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.secondary)
            .font(.system(size: 15, weight: .medium))

          TextField(
            NSLocalizedString("Search food items", comment: "Search food items"), text: $searchText
          )
          .focused($searchFieldIsFocused)
          .onChange(of: searchText) { _, _ in
            searchDebounceTimer?.invalidate()
            searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
              Task { await resetAndSearch() }
            }
          }

          if !searchText.isEmpty {
            Button(action: {
              searchText = ""
              Task { await resetAndSearch() }
            }) {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(UIColor.tertiarySystemFill))
        .cornerRadius(12)

        if searchFieldIsFocused {
          Button(NSLocalizedString("Cancel", comment: "Cancel search")) {
            searchText = ""
            searchFieldIsFocused = false
            Task { await resetAndSearch() }
          }
          .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
      .padding(.horizontal)
      .padding(.top, 8)
      .animation(.easeInOut(duration: 0.2), value: searchFieldIsFocused)

      HStack {
        Button {
          filterMyItems.toggle()
          Task { await resetAndSearch() }
        } label: {
          Label(
            NSLocalizedString("My Items", comment: "My food items filter"),
            systemImage: "person.fill"
          )
          .font(.subheadline.weight(.medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(filterMyItems ? Color.blue : Color(UIColor.tertiarySystemFill))
          .foregroundColor(filterMyItems ? .white : .primary)
          .clipShape(Capsule())
        }
        Spacer()
      }
      .padding(.horizontal)
      .padding(.bottom, 4)
      .animation(.easeInOut(duration: 0.15), value: filterMyItems)

      if isInitialLoading {
        ProgressView()
          .padding()
      } else if foodMasters.isEmpty {
        EmptyFoodMasterView(showAddForm: $showingAddForm)
      } else {
        List {
          ForEach(foodMasters, id: \.id) { foodMaster in
            FoodMasterRow(foodMaster: foodMaster)
              .contentShape(Rectangle())
              .onTapGesture {
                searchFieldIsFocused = false
                if canEdit(foodMaster) {
                  selectedFoodMaster = foodMaster
                } else {
                  viewingFoodMaster = foodMaster
                }
              }
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
                    Label("Delete", systemImage: "trash")
                  }
                }
              }
          }

          if hasMoreData {
            Section {
              HStack {
                Spacer()
                if isLoading { ProgressView() }
                Spacer()
              }
              .padding(.vertical, 8)
              .id("loadingIndicator")
            }
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
      }
    } catch {
      await MainActor.run {
        isDataLoaded = true
        isInitialLoading = false
      }
      print("FoodMasterManagementView loadFoodMasters error: \(error)")
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

  private func deleteFoodMaster(_ foodMaster: FoodMasterDTO) {
    foodMasters.removeAll { $0.id == foodMaster.id }
    Task {
      do {
        try await APIClient.shared.deleteFoodMaster(id: foodMaster.id)
      } catch {
        print("deleteFoodMaster error: \(error)")
      }
    }
  }
}

// フードマスター詳細表示（読み取り専用）
struct FoodMasterDetailView: View {
  let foodMaster: FoodMasterDTO
  @Environment(\.dismiss) var dismiss

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
          LabeledContent(
            NSLocalizedString("Sugar", comment: "Sugar"),
            value: "\(NutritionFormatter.formatNutrition(foodMaster.netCarbs)) g"
          )
          LabeledContent(
            NSLocalizedString("Dietary Fiber", comment: "Dietary Fiber"),
            value: "\(NutritionFormatter.formatNutrition(foodMaster.dietaryFiber)) g"
          )
          LabeledContent(
            NSLocalizedString("Carbohydrates (Sugar + Fiber)", comment: "Carbohydrates"),
            value: "\(NutritionFormatter.formatNutrition(foodMaster.netCarbs + foodMaster.dietaryFiber)) g"
          )
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
  let foodMaster: FoodMasterDTO

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        if foodMaster.isMine == true {
          Image(systemName: "person.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.blue)
            .padding(.top, 2)
        }
        Text("\(foodMaster.brandName) \(foodMaster.productName)")
          .font(.subheadline.weight(.medium))
          .lineLimit(1)

        Spacer()

        Text("\(foodMaster.calories, specifier: "%.0f")")
          .font(.system(size: 15, weight: .semibold, design: .rounded))
          .foregroundColor(.primary)
        + Text(" kcal")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }

      HStack(spacing: 6) {
        MacroChip(label: "P", value: foodMaster.protein, color: .blue)
        MacroChip(label: "F", value: foodMaster.fat, color: .yellow)
        MacroChip(label: "S", value: foodMaster.netCarbs, color: .green)
        MacroChip(label: "Fb", value: foodMaster.dietaryFiber, color: .brown)

        Spacer()

        Text("\(NutritionFormatter.formatNutrition(foodMaster.portionSize)) \(foodMaster.portionUnit)")
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
    case edit(FoodMasterDTO)
    case quickAdd(initialProductName: String)
  }

  let mode: FormMode
  let onSaved: ((FoodMasterDTO) -> Void)?
  @Environment(\.dismiss) var dismiss

  @State private var brandName = ""
  @State private var productName = ""
  @State private var calories = ""
  @State private var netCarbs = ""
  @State private var dietaryFiber = ""
  @State private var fat = ""
  @State private var protein = ""
  @State private var portionSize = ""
  @State private var portionUnit = ""
  @State private var isSaving = false

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

  enum FocusedField {
    case brandName, productName, portionSize, portionUnit
    case calories, protein, fat, netCarbs, dietaryFiber
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

        Section(
          header: Text(
            String(
              format: NSLocalizedString("Nutrition (per %@ %@)", comment: "Nutrition with portion size and unit"),
              portionSize.isEmpty ? "1" : portionSize,
              portionUnit.isEmpty ? NSLocalizedString("unit", comment: "Default unit") : portionUnit
            ))
        ) {
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
          HStack {
            Text(NSLocalizedString("Sugar", comment: "Sugar"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $netCarbs)
              .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .netCarbs)
            Text(NSLocalizedString("g", comment: "g"))
          }
          HStack {
            Text(NSLocalizedString("Dietary Fiber", comment: "Dietary Fiber"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $dietaryFiber)
              .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
              .focused($focusedField, equals: .dietaryFiber)
            Text(NSLocalizedString("g", comment: "g"))
          }
          HStack {
            Text(NSLocalizedString("Carbohydrates (Sugar + Fiber)", comment: "Carbohydrates"))
            Spacer()
            Text(NutritionFormatter.formatNutrition((Double(netCarbs) ?? 0) + (Double(dietaryFiber) ?? 0)))
              .foregroundColor(.secondary)
            Text(NSLocalizedString("g", comment: "g")).foregroundColor(.secondary)
          }
        }
        .headerProminence(.increased)
        .font(.subheadline)
        .foregroundColor(.secondary)
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Button(action: { focusPreviousField() }) {
            Image(systemName: "chevron.up")
          }
          Button(action: { focusNextField() }) {
            Image(systemName: "chevron.down")
          }
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
          .disabled(brandName.isEmpty || productName.isEmpty || portionUnit.isEmpty || isSaving)
        }
      }
      .onAppear { loadState() }
      .onDisappear { saveState() }
      .onChange(of: brandName) { _, _ in saveState() }
      .onChange(of: productName) { _, _ in saveState() }
      .onChange(of: calories) { _, _ in saveState() }
      .onChange(of: netCarbs) { _, _ in saveState() }
      .onChange(of: dietaryFiber) { _, _ in saveState() }
      .onChange(of: fat) { _, _ in saveState() }
      .onChange(of: protein) { _, _ in saveState() }
      .onChange(of: portionSize) { _, _ in saveState() }
      .onChange(of: portionUnit) { _, _ in saveState() }
    }
  }

  private func focusNextField() {
    let allFields: [FocusedField] = [.brandName, .productName, .portionSize, .portionUnit, .calories, .protein, .fat, .netCarbs, .dietaryFiber]
    guard let current = focusedField, let idx = allFields.firstIndex(of: current) else {
      focusedField = allFields.first; return
    }
    focusedField = allFields[(idx + 1) % allFields.count]
  }

  private func focusPreviousField() {
    let allFields: [FocusedField] = [.brandName, .productName, .portionSize, .portionUnit, .calories, .protein, .fat, .netCarbs, .dietaryFiber]
    guard let current = focusedField, let idx = allFields.firstIndex(of: current) else {
      focusedField = allFields.last; return
    }
    focusedField = allFields[idx == 0 ? allFields.count - 1 : idx - 1]
  }

  private func saveAndDismiss() async {
    isSaving = true
    defer { isSaving = false }

    let caloriesValue = Double(calories) ?? 0
    let netCarbsValue = Double(netCarbs) ?? 0
    let dietaryFiberValue = Double(dietaryFiber) ?? 0
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
        saved = try await APIClient.shared.createFoodMaster(dto)
        clearSavedState()
      case .edit(let foodMaster):
        let dto = FoodMasterUpdateDTO(
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
        saved = try await APIClient.shared.updateFoodMaster(id: foodMaster.id, dto)
      }
      onSaved?(saved)
      dismiss()
    } catch {
      print("FoodMasterFormView saveAndDismiss error: \(error)")
      dismiss()
    }
  }

  private func saveState() {
    guard case .quickAdd = mode else { return }
    UserDefaults.standard.set(brandName, forKey: "\(stateKey)_brandName")
    UserDefaults.standard.set(productName, forKey: "\(stateKey)_productName")
    UserDefaults.standard.set(calories, forKey: "\(stateKey)_calories")
    UserDefaults.standard.set(netCarbs, forKey: "\(stateKey)_sugar")
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
      netCarbs = NutritionFormatter.formatNutrition(foodMaster.netCarbs)
      dietaryFiber = NutritionFormatter.formatNutrition(foodMaster.dietaryFiber)
      fat = NutritionFormatter.formatNutrition(foodMaster.fat)
      protein = NutritionFormatter.formatNutrition(foodMaster.protein)
      portionSize = NutritionFormatter.formatNutrition(foodMaster.portionSize)
      portionUnit = foodMaster.portionUnit
    case .quickAdd(let initialProductName):
      brandName = UserDefaults.standard.string(forKey: "\(stateKey)_brandName") ?? ""
      productName = UserDefaults.standard.string(forKey: "\(stateKey)_productName") ?? initialProductName
      calories = UserDefaults.standard.string(forKey: "\(stateKey)_calories") ?? ""
      netCarbs = UserDefaults.standard.string(forKey: "\(stateKey)_sugar") ?? ""
      dietaryFiber = UserDefaults.standard.string(forKey: "\(stateKey)_dietaryFiber") ?? ""
      fat = UserDefaults.standard.string(forKey: "\(stateKey)_fat") ?? ""
      protein = UserDefaults.standard.string(forKey: "\(stateKey)_protein") ?? ""
      portionSize = UserDefaults.standard.string(forKey: "\(stateKey)_portionSize") ?? ""
      portionUnit = UserDefaults.standard.string(forKey: "\(stateKey)_portionUnit") ?? ""
    case .add:
      break
    }
  }

  private func clearSavedState() {
    guard case .quickAdd = mode else { return }
    ["_brandName", "_productName", "_calories", "_sugar", "_dietaryFiber", "_fat", "_protein", "_portionSize", "_portionUnit"].forEach {
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
