import SwiftUI

struct EditItemView: View {
  @Environment(\.dismiss) var dismiss

  @State var item: LogItemDTO
  var onSaved: ((LogItemDTO) -> Void)?

  @State private var numberOfServings: String
  @State private var mealType: MealType
  @State private var foodMaster: FoodMasterDTO?
  @State private var showingFoodSearch = false
  @State private var searchResults: [FoodMasterDTO] = []
  @State private var currentOffset = 0
  @State private var hasMoreData = true
  @State private var isSaving = false
  @State private var showsDetailNutrients = false
  @State private var failure: OperationFailure?
  private let pageSize = 100

  @FocusState private var isServingsFocused: Bool?

  private var portionUnit: String { foodMaster?.portionUnit ?? item.portionUnit }

  private var servingsValue: Double { Double(numberOfServings) ?? 1.0 }

  private var totalNutrition: NutritionValues {
    if let fm = foodMaster {
      return NutritionSnapshot.from(fm).scaled(by: servingsValue)
    } else if let snapshot = item.nutritionSnapshot {
      return snapshot.scaled(by: servingsValue)
    }
    return .zero
  }

  private var totalCalories: Double { totalNutrition.calories }
  private var totalProtein: Double { totalNutrition.protein }
  private var totalFat: Double { totalNutrition.fat }
  private var totalNetCarbs: Double { totalNutrition.netCarbs }
  private var totalDietaryFiber: Double { totalNutrition.dietaryFiber }
  private var totalCarbs: Double { totalNutrition.carbs }

  init(item: LogItemDTO, onSaved: ((LogItemDTO) -> Void)? = nil) {
    _item = State(initialValue: item)
    _numberOfServings = State(initialValue: NutritionFormatter.formatNutrition(item.numberOfServings))
    _mealType = State(initialValue: item.mealType)
    _foodMaster = State(initialValue: item.foodMaster)
    self.onSaved = onSaved
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          MealTypeSelector(selection: $mealType)
            // 追加画面と同じく行の地は敷かない。選んだ食事の影が行の外で切れないよう、下だけ余白を広く取る
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 14, trailing: 0))
            .listRowBackground(Color.clear)
        }

        Section {
          foodRow

          // 直せるのは食事と食べた量だけ。量の欄にだけ枠を付け、食品は表示だけと分かるようにする
          LabeledContent(NSLocalizedString("Servings", comment: "Servings label")) {
            NumberInputField(
              title: NSLocalizedString("Servings", comment: "Servings label"), text: $numberOfServings,
              placeholder: "1", unit: portionUnit, focus: $isServingsFocused, field: true)
          }
        } header: {
          Text(NSLocalizedString("Food Item", comment: "Form section title"))
        }

        if foodMaster != nil || item.isMasterDeleted {
          Section {
            NutritionOverview(values: totalNutrition)
              // カードの地は NutritionOverview が持つ。フォームの行の地を敷くと二重になる
              .listRowInsets(EdgeInsets())
              .listRowBackground(Color.clear)
          }

          Section {
            EditNutrientRow(nutrient: .calories, total: totalCalories)
            EditNutrientRow(nutrient: .protein, total: totalProtein)
            EditNutrientRow(nutrient: .fat, total: totalFat)
            EditNutrientRow(nutrient: .netCarbs, total: totalNetCarbs)
            EditNutrientRow(nutrient: .fiber, total: totalDietaryFiber)
            EditNutrientRow(nutrient: .carbs, total: totalCarbs)
            ForEach(NutrientID.labelNutrients, id: \.self) { id in
              EditNutrientRow(addedNutrient: id, total: totalNutrition.amounts[id])
            }
            DisclosureHeading(
              NSLocalizedString("Detailed Nutrients", comment: "Disclosure of nutrients rarely on food labels"),
              isExpanded: $showsDetailNutrients
            )
            .listRowAsCard()
            if showsDetailNutrients {
              ForEach(NutrientID.detailNutrients, id: \.self) { id in
                EditNutrientRow(addedNutrient: id, total: totalNutrition.amounts[id])
              }
            }
          } header: {
            // 何の値かを一覧の前に言う。脚注に書くと、最後まで読まないと何を見ているか分からない
            Text(
              String(
                format: NSLocalizedString("Nutrition for %@ %@", comment: "Nutrition for the eaten amount"),
                NutritionFormatter.formatNutrition(servingsValue), portionUnit))
            .sectionHeaderAlignedToCard()
          }
          .headerProminence(.increased)
        }
      }
      .navigationTitle(NSLocalizedString("Edit Meal", comment: "Navigation title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Save", comment: "Button title"), action: saveLogItem)
            .disabled(
              isSaving || (foodMaster == nil && !item.isMasterDeleted)
                || numberOfServings.isEmpty || Double(numberOfServings) == 0)
        }
      }
      .operationFailureAlert($failure)
      .sheet(isPresented: $showingFoodSearch) {
        FoodSearchView(onSelect: { selected in
          foodMaster = selected
          numberOfServings = NutritionFormatter.formatNutrition(selected.servingsToLog)
        })
      }
    }
  }

  @ViewBuilder
  private var foodRow: some View {
    if let foodMaster {
      Text(FoodRow.displayName(brand: foodMaster.brandName, product: foodMaster.productName))
        .font(.headline)
        .lineLimit(2)
    } else if item.isMasterDeleted {
      HStack(spacing: 4) {
        Text(FoodRow.displayName(brand: item.brandName, product: item.productName))
          .font(.headline)
          .lineLimit(2)
          .foregroundStyle(.secondary)
          .strikethrough()

        Text(NSLocalizedString("(Deleted)", comment: "Deleted Food indicator"))
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize()
      }
    } else {
      Button {
        showingFoodSearch = true
      } label: {
        Label(
          NSLocalizedString("Search for food", comment: "Search for food"),
          systemImage: "magnifyingglass")
      }
    }
  }

  private func saveLogItem() {
    let dto = LogItemUpdateDTO(changesFrom: item, numberOfServings: servingsValue, mealType: mealType)
    Task {
      isSaving = true
      defer { isSaving = false }
      do {
        let updated = try await APIClient.shared.updateLogItem(id: item.id, dto)
        dismiss()
        onSaved?(updated)
      } catch {
        // 失敗しても閉じると、保存できていないのに保存したつもりになる。
        // 入力を残したまま伝え、もう一度試せるようにする。
        failure = .saving(error)
      }
    }
  }
}

/// 食べた量の分の栄養素を1行のカードで示す。栄養素の名前・色・単位・印は栄養素の型から引く。
///
/// 1単位あたりの値は並べない。「67kcal → 134kcal」と2つ並べると、どちらが食べた量なのか説明が要る。
/// 1単位あたりの値は食品の詳細で見られる。
struct EditNutrientRow: View {
  let nutrient: any NutrientDisplaying
  /// 分からなければ nil。あとから足した栄養素は、値の分からない食品がある
  let total: Double?

  init(nutrient: Nutrient, total: Double) {
    self.nutrient = nutrient
    self.total = total
  }

  init(addedNutrient: NutrientID, total: Double?) {
    self.nutrient = addedNutrient
    self.total = total
  }

  var body: some View {
    NutrientCardRow(nutrient: nutrient, background: Color(UIColor.secondarySystemGroupedBackground)) {
      Text(
        total.map { "\(nutrient.format($0))\(nutrient.unit)" }
          ?? NSLocalizedString("Unknown", comment: "Unknown nutrient value")
      )
      .monospacedDigit()
      .fontWeight(.medium)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      total.map(nutrient.accessibilityLabel(for:))
        ?? "\(nutrient.localizedName) \(NSLocalizedString("Unknown", comment: "Unknown nutrient value"))")
    .listRowAsCard()
  }
}

// 食品検索ビュー
struct FoodSearchView: View {
  @Environment(\.dismiss) var dismiss
  var onSelect: (FoodMasterDTO) -> Void

  @State private var searchText = ""
  @State private var searchResults: [FoodMasterDTO] = []
  @State private var currentOffset = 0
  @State private var hasMoreData = true
  /// 検索できなかった状態。0件と区別しないと、登録済みの食品を
  /// 「無い」と思って作り直すことになる。
  @State private var loadFailed = false
  private let pageSize = 50

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(NSLocalizedString("Select food", comment: "Navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
          text: $searchText,
          prompt: Text(NSLocalizedString("Search food items", comment: "Search placeholder"))
        )
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
          }
        }
        .onChange(of: searchText) { _, _ in
          searchResults = []
          currentOffset = 0
          hasMoreData = true
          loadFailed = false
          Task { await loadMoreItems() }
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    if searchText.isEmpty {
      ContentUnavailableView {
        Label(
          NSLocalizedString("Search for food", comment: "Search for food"),
          systemImage: "magnifyingglass")
      }
    } else if loadFailed && searchResults.isEmpty {
      LoadFailureView { await loadMoreItems() }
    } else if searchResults.isEmpty {
      ContentUnavailableView.search(text: searchText)
    } else {
      List {
        ForEach(searchResults, id: \.id) { item in
          Button {
            onSelect(item)
            dismiss()
          } label: {
            FoodMasterRow(foodMaster: item)
          }
          .buttonStyle(.plain)
          .cardRow()
          .onAppear {
            if item.id == searchResults.last?.id && hasMoreData {
              Task { await loadMoreItems() }
            }
          }
        }
      }
      .listStyle(.insetGrouped)
    }
  }

  private func loadMoreItems() async {
    guard !searchText.isEmpty else {
      searchResults = []; currentOffset = 0; hasMoreData = true; return
    }
    do {
      let resp = try await APIClient.shared.fetchFoodMasters(query: searchText, limit: pageSize, offset: currentOffset)
      if currentOffset == 0 { searchResults = resp.items } else { searchResults.append(contentsOf: resp.items) }
      currentOffset += resp.items.count
      hasMoreData = resp.hasMore
      loadFailed = false
    } catch {
      loadFailed = true
    }
  }
}
