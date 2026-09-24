import SwiftUI

struct AddItemView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var selectedTab: AppTab

  let mealType: MealType
  var selectedDate: Date

  @State private var searchText = ""
  @State private var date: Date
  @State private var searchResults: [FoodMasterDTO] = []
  @State private var isDataLoaded = false
  @State private var isInitialLoading = true

  @State private var currentPage = 0
  @State private var isLoading = false
  @State private var hasMoreData = true
  private let pageSize = 20

  @FocusState private var isSearchFocused: Bool
  @State private var searchDebounceTimer: Timer?

  @State private var addedCount = 0

  @State private var showQuickCreationSheet = false

  @State private var showingPhotoPicker = false
  @State private var selectedImage: UIImage?
  @State private var isAnalyzing = false
  @State private var analysisResult: FoodAnalysisResult?
  @State private var showingAnalysisResult = false
  @State private var showingAPIKeyError = false
  @State private var analysisError: String?

  init(preselectedMealType: MealType, selectedDate: Date, selectedTab: Binding<AppTab>) {
    self.mealType = preselectedMealType
    self.selectedDate = selectedDate
    _date = State(initialValue: selectedDate)
    _selectedTab = selectedTab
  }

  var body: some View {
    NavigationStack {
      contentView
        .background(Color(UIColor.systemGroupedBackground))
        .searchable(
          text: $searchText,
          placement: .navigationBarDrawer(displayMode: .always),
          prompt: Text(NSLocalizedString("Search food items", comment: "Search placeholder"))
        )
        .searchFocused($isSearchFocused)
        .onChange(of: searchText) { _, _ in
          searchDebounceTimer?.invalidate()
          searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            Task { await resetAndSearch() }
          }
        }
        // 自前のバナーで 0.5 秒だけ「追加しました」と出していたが、
        // 追加はリストから消えないので見て分かりにくい。触覚で返す。
        .sensoryFeedback(.success, trigger: addedCount)
      .navigationTitle(NSLocalizedString("Add Meal", comment: "Navigation title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            if AIFoodAnalyzer.shared.isAvailable() { showingPhotoPicker = true }
            else { showingAPIKeyError = true }
          } label: {
            Label(
              NSLocalizedString("Analyze photo", comment: "AI photo analysis"),
              systemImage: "camera.viewfinder")
          }
        }
      }
      .onAppear {
        if !isDataLoaded { Task { await loadFoodMasters() } }
      }
      .sheet(isPresented: $showingPhotoPicker) {
        PhotoPickerView(selectedImage: $selectedImage) { image, note in analyzeImage(image, note: note) }
      }
      .sheet(isPresented: $showingAnalysisResult) {
        if let result = analysisResult, let image = selectedImage {
          AIAnalysisResultView(result: result, image: image, mealType: mealType, date: date, onSave: { dismiss() })
        }
      }
      .alert(NSLocalizedString("Sign In Required", comment: "Alert title"), isPresented: $showingAPIKeyError) {
        Button(NSLocalizedString("OK", comment: "Button title"), role: .cancel) {}
      } message: {
        Text(NSLocalizedString("Please sign in to use AI food analysis.", comment: "Alert message"))
      }
      .alert(NSLocalizedString("Analysis Error", comment: "Alert title"), isPresented: .constant(analysisError != nil)) {
        Button(NSLocalizedString("OK", comment: "Button title"), role: .cancel) { analysisError = nil }
      } message: {
        if let error = analysisError { Text(error) }
      }
      .overlay {
        if isAnalyzing {
          ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
              ProgressView().scaleEffect(1.5).tint(.white)
              Text(NSLocalizedString("Analyzing food...", comment: "Loading message"))
                .foregroundColor(.white).font(.headline)
            }
            .padding(30)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
            .shadow(radius: 10)
          }
        }
      }
    }
  }

  private func analyzeImage(_ image: UIImage, note: String?) {
    Task {
      await MainActor.run { isAnalyzing = true; showingPhotoPicker = false }
      do {
        let result = try await AIFoodAnalyzer.shared.analyzeFood(image: image, note: note)
        await MainActor.run { isAnalyzing = false; analysisResult = result; showingAnalysisResult = true }
      } catch {
        await MainActor.run { isAnalyzing = false; analysisError = error.localizedDescription }
      }
    }
  }

  @ViewBuilder
  private var contentView: some View {
    Group {
      if isInitialLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if searchResults.isEmpty && !isDataLoaded {
        EmptyFoodMasterPromptView(selectedTab: $selectedTab, dismiss: dismiss)
      } else if searchResults.isEmpty {
        emptySearchResultsView
      } else {
        searchResultsListView
      }
    }
    .sheet(isPresented: $showQuickCreationSheet) {
      FoodMasterFormView(mode: .quickAdd(initialProductName: searchText)) { createdFood in
        Task {
          await addFoodItem(createdFood)
          dismiss()
        }
      }
    }
  }

  private var searchResultsListView: some View {
    List {
      ForEach(searchResults, id: \.id) { item in
        Button { Task { await addFoodItem(item) } } label: { PastItemCard(item: item) }
          .buttonStyle(ScaleButtonStyle())
          .onAppear {
            if item.id == searchResults.last?.id && hasMoreData && !isLoading {
              Task { await loadMoreContent() }
            }
          }
      }

      if !searchText.isEmpty && !hasMoreData {
        Button { showQuickCreationSheet = true } label: {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(
                String(
                  format: NSLocalizedString(
                    "Create and add \"%@\"", comment: "Create and add button"), searchText))
              Text(NSLocalizedString("Quickly add a new food item", comment: "Quick add description"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "plus.circle.fill")
          }
        }
      }

      if hasMoreData {
        HStack {
          Spacer()
          if isLoading { ProgressView() }
          Spacer()
        }
        .listRowBackground(Color.clear)
      }
    }
    .listStyle(.insetGrouped)
  }

  @ViewBuilder
  private var emptySearchResultsView: some View {
    if searchText.isEmpty {
      ContentUnavailableView {
        Label(
          NSLocalizedString("No Food Items", comment: "No food items"), systemImage: "fork.knife")
      } description: {
        Text(
          NSLocalizedString(
            "Register new food items in the food tab", comment: "No search results message"))
      } actions: {
        Button(NSLocalizedString("Go to Food Management", comment: "Go to food management button")) {
          dismiss()
          selectedTab = .food
        }
        .buttonStyle(.borderedProminent)
      }
    } else {
      ContentUnavailableView {
        Label(
          NSLocalizedString("No search results found", comment: "No search results message"),
          systemImage: "magnifyingglass")
      } description: {
        Text(
          NSLocalizedString(
            "Register new food items in the food tab", comment: "No search results message"))
      } actions: {
        Button {
          showQuickCreationSheet = true
        } label: {
          Text(
            String(
              format: NSLocalizedString("Create and add \"%@\"", comment: "Create and add button"),
              searchText))
        }
        .buttonStyle(.borderedProminent)

        Button(NSLocalizedString("Go to Food Management", comment: "Go to food management button")) {
          dismiss()
          selectedTab = .food
        }
      }
    }
  }

  private func addFoodItem(_ foodMaster: FoodMasterDTO) async {
    let dto = LogItemCreateDTO(
      id: UUID().uuidString,
      timestamp: ISO8601DateFormatter().string(from: date),
      logDate: LogItemDTO.formatLogDate(date),
      mealType: mealType.rawValue,
      numberOfServings: foodMaster.lastNumberOfServings,
      foodMasterId: foodMaster.id.uuidString,
      nutritionSnapshot: NutritionSnapshot.from(foodMaster)
    )
    do {
      _ = try await APIClient.shared.createLogItem(dto)
    } catch {
      print("AddItemView addFoodItem error: \(error)")
    }

    addedCount += 1
    searchText = ""
    await resetAndSearch()
    isSearchFocused = true
  }

  private func resetAndSearch() async {
    currentPage = 0; hasMoreData = true
    await loadFoodMasters()
  }

  private func loadFoodMasters() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let resp = try await APIClient.shared.fetchFoodMasters(query: searchText, limit: pageSize, offset: currentPage * pageSize)
      await MainActor.run {
        if currentPage == 0 { withAnimation(.easeInOut(duration: 0.3)) { searchResults = resp.items } }
        else { searchResults.append(contentsOf: resp.items) }
        hasMoreData = resp.hasMore
        isDataLoaded = true
        isInitialLoading = false
      }
    } catch {
      await MainActor.run { isLoading = false; isDataLoaded = true; isInitialLoading = false }
    }
  }

  private func loadMoreContent() async {
    guard !isLoading && hasMoreData else { return }
    currentPage += 1
    await loadFoodMasters()
  }
}

/// 食品マスタが1件も無いときの案内。
struct EmptyFoodMasterPromptView: View {
  @Binding var selectedTab: AppTab
  var dismiss: DismissAction

  var body: some View {
    ContentUnavailableView {
      Label(
        NSLocalizedString("No Food Items Registered", comment: "No food items"),
        systemImage: "fork.knife")
    } description: {
      Text(
        NSLocalizedString(
          "You need to register food items before you can add meals.",
          comment: "Register food prompt"))
    } actions: {
      Button(NSLocalizedString("Go to Food Management", comment: "Go to food management button")) {
        dismiss()
        selectedTab = .food
      }
      .buttonStyle(.borderedProminent)
    }
  }
}

/// 検索結果の行。ここだけは前回の摂取量 (`lastNumberOfServings`) 換算の値を出すので、
/// 1食分を出す `FoodMasterRow` とは表示する数値が異なる。
struct PastItemCard: View {
  let item: FoodMasterDTO

  private var servings: Double { item.lastNumberOfServings }

  var body: some View {
    FoodRow(
      title: FoodRow.displayName(brand: item.brandName, product: item.productName),
      subtitle: FoodRow.amountText(servings, unit: item.portionUnit),
      values: NutritionSnapshot.from(item).scaled(by: servings)
    )
  }
}
