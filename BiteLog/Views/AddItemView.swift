import SwiftUI

struct AddItemView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var selectedTab: Int

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

  @FocusState private var searchFieldIsFocused: Bool
  @State private var searchDebounceTimer: Timer?

  @State private var showAddedFeedback = false
  @State private var lastAddedItem: String = ""
  @State private var feedbackQueue: [String] = []
  @State private var isProcessingFeedback = false

  @State private var showQuickCreationSheet = false

  @State private var showingPhotoPicker = false
  @State private var selectedImage: UIImage?
  @State private var isAnalyzing = false
  @State private var analysisResult: FoodAnalysisResult?
  @State private var showingAnalysisResult = false
  @State private var showingAPIKeyError = false
  @State private var analysisError: String?

  init(preselectedMealType: MealType, selectedDate: Date, selectedTab: Binding<Int>) {
    self.mealType = preselectedMealType
    self.selectedDate = selectedDate
    _date = State(initialValue: selectedDate)
    _selectedTab = selectedTab
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()
        mainContentView
      }
      .navigationTitle(NSLocalizedString("Add Meal", comment: "Navigation title"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            if AIFoodAnalyzer.shared.isAvailable() { showingPhotoPicker = true }
            else { showingAPIKeyError = true }
          } label: {
            Image(systemName: "camera.viewfinder").font(.title3)
          }
          .buttonStyle(PlainButtonStyle())
        }
      }
      .onAppear {
        if !isDataLoaded { Task { await loadFoodMasters() } }
      }
      .sheet(isPresented: $showingPhotoPicker) {
        PhotoPickerView(selectedImage: $selectedImage) { image in analyzeImage(image) }
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

  private func analyzeImage(_ image: UIImage) {
    Task {
      await MainActor.run { isAnalyzing = true; showingPhotoPicker = false }
      do {
        let result = try await AIFoodAnalyzer.shared.analyzeFood(image: image)
        await MainActor.run { isAnalyzing = false; analysisResult = result; showingAnalysisResult = true }
      } catch {
        await MainActor.run { isAnalyzing = false; analysisError = error.localizedDescription }
      }
    }
  }

  private var mainContentView: some View {
    VStack { searchBarView; feedbackView; contentView }
  }

  private var searchBarView: some View {
    HStack {
      Image(systemName: "magnifyingglass").foregroundColor(.secondary).padding(.leading, 8)
      TextField(NSLocalizedString("Search food items", comment: "Search placeholder"), text: $searchText)
        .padding(10).background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
        .focused($searchFieldIsFocused)
        .onChange(of: searchText) { _, _ in
          searchDebounceTimer?.invalidate()
          searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            Task { await resetAndSearch() }
          }
        }
      if !searchText.isEmpty {
        Button(action: { searchText = ""; Task { await resetAndSearch() } }) {
          Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).padding(.trailing, 8)
        }
      }
      if searchFieldIsFocused {
        Button(NSLocalizedString("Cancel", comment: "Cancel search")) {
          searchText = ""; searchFieldIsFocused = false; Task { await resetAndSearch() }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .padding(.horizontal).padding(.top, 8)
  }

  private var feedbackView: some View {
    Group {
      if showAddedFeedback {
        HStack {
          Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
          Text(String(format: NSLocalizedString("%@ added to %@", comment: "Added food feedback"), lastAddedItem, mealType.localizedName))
            .font(.subheadline)
          Spacer()
        }
        .padding().background(Color.green.opacity(0.1)).cornerRadius(10).padding(.horizontal)
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
      }
    }
  }

  private var contentView: some View {
    Group {
      if isInitialLoading { ProgressView().padding() }
      else if searchResults.isEmpty && !isDataLoaded { EmptyFoodMasterPromptView(selectedTab: $selectedTab, dismiss: dismiss) }
      else if searchResults.isEmpty && isDataLoaded { emptySearchResultsView }
      else { searchResultsListView }
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
        Section {
          Button { showQuickCreationSheet = true } label: {
            HStack {
              Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.blue)
              VStack(alignment: .leading, spacing: 4) {
                Text(String(format: NSLocalizedString("Create and add \"%@\"", comment: "Create and add button"), searchText)).font(.headline)
                Text(NSLocalizedString("Quickly add a new food item", comment: "Quick add description")).font(.caption).foregroundColor(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
          }
          .buttonStyle(PlainButtonStyle())
        }
      }
      if hasMoreData {
        Section {
          HStack { Spacer(); if isLoading { ProgressView() }; Spacer() }.padding(.vertical, 8).id("loadingIndicator")
        }
      }
    }
    .listStyle(.insetGrouped)
    .sheet(isPresented: $showQuickCreationSheet) {
      FoodMasterFormView(mode: .quickAdd(initialProductName: searchText)) { createdFood in
        Task { await addFoodItem(createdFood); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() } }
      }
    }
  }

  private var emptySearchResultsView: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.magnifyingglass").font(.system(size: 48)).foregroundColor(.secondary)
      Text(NSLocalizedString("No search results found", comment: "No search results message")).font(.headline).foregroundColor(.secondary)
      if !searchText.isEmpty {
        Button { showQuickCreationSheet = true } label: {
          HStack {
            Image(systemName: "plus.circle.fill").font(.title2)
            Text(String(format: NSLocalizedString("Create and add \"%@\"", comment: "Create and add button"), searchText)).fontWeight(.semibold)
          }
          .padding(.horizontal, 20).padding(.vertical, 10)
          .background(Color.blue).foregroundColor(.white).cornerRadius(10)
        }
        .padding(.top, 10)
        Text(NSLocalizedString("or", comment: "Or text")).font(.subheadline).foregroundColor(.secondary)
      }
      Text(NSLocalizedString("Register new food items in the food tab", comment: "No search results message"))
        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal).lineLimit(nil)
      Button { dismiss(); selectedTab = 1 } label: {
        Text(NSLocalizedString("Go to Food Management", comment: "Go to food management button"))
          .fontWeight(.semibold).padding(.horizontal, 20).padding(.vertical, 10)
          .background(Color(UIColor.systemGray5)).foregroundColor(.primary).cornerRadius(10)
      }
    }
    .frame(maxWidth: .infinity).padding(.vertical, 40)
    .sheet(isPresented: $showQuickCreationSheet) {
      FoodMasterFormView(mode: .quickAdd(initialProductName: searchText)) { createdFood in
        Task { await addFoodItem(createdFood); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() } }
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

    let feedbackText = "\(foodMaster.brandName) \(foodMaster.productName)"
    feedbackQueue.append(feedbackText)
    processFeedbackQueue()

    searchText = ""
    await resetAndSearch()
    searchFieldIsFocused = true
  }

  private func processFeedbackQueue() {
    guard !isProcessingFeedback, let nextItem = feedbackQueue.first else { return }
    isProcessingFeedback = true
    feedbackQueue.removeFirst()
    lastAddedItem = nextItem
    withAnimation(.easeIn(duration: 0.2)) { showAddedFeedback = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      withAnimation(.easeOut(duration: 0.2)) { showAddedFeedback = false }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isProcessingFeedback = false
        processFeedbackQueue()
      }
    }
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

// マスターデータが0件の場合に表示するビュー
struct EmptyFoodMasterPromptView: View {
  @Binding var selectedTab: Int
  var dismiss: DismissAction

  var body: some View {
    VStack(spacing: 10) {
      Spacer()
      Image(systemName: "fork.knife").font(.system(size: 48)).foregroundColor(.secondary)
      Text(NSLocalizedString("No Food Items Registered", comment: "No food items")).font(.title2).fontWeight(.bold)
      Text(NSLocalizedString("You need to register food items before you can add meals.", comment: "Register food prompt"))
        .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 40).lineLimit(nil)
      Button { dismiss(); selectedTab = 1 } label: {
        Text(NSLocalizedString("Go to Food Management", comment: "Go to food management button"))
          .fontWeight(.semibold).padding(.horizontal, 20).padding(.vertical, 10)
          .background(Color.blue).foregroundColor(.white).cornerRadius(10)
      }
      .padding(.top, 10)
      Spacer()
    }
    .padding()
  }
}

// 過去の食事アイテムカード
struct PastItemCard: View {
  let item: FoodMasterDTO

  private var servings: Double { item.lastNumberOfServings }
  private var nutrition: NutritionValues { NutritionSnapshot.from(item).scaled(by: servings) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(item.brandName) \(item.productName)").font(.headline)
        }
        Spacer()
        Text("\(nutrition.calories, specifier: "%.0f")").font(.title3.bold())
          + Text(" kcal").font(.subheadline).foregroundColor(.secondary)
      }
      HStack(spacing: 8) {
        MacroNutrientBadge(label: "P", value: nutrition.protein, color: .blue)
        MacroNutrientBadge(label: "F", value: nutrition.fat, color: .yellow)
        MacroNutrientBadge(label: "S", value: nutrition.netCarbs, color: .green)
        MacroNutrientBadge(label: "Fiber", value: nutrition.dietaryFiber, color: .brown)
      }
      HStack {
        Text(NSLocalizedString("Servings:", comment: "Servings label")).font(.subheadline).foregroundColor(.secondary)
        Text("\(NutritionFormatter.formatNutrition(servings)) \(item.portionUnit)").font(.subheadline)
        Spacer()
      }
    }
    .padding()
    .background(Color(UIColor.systemBackground))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
  }
}
