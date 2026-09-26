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
  /// 読み込めなかった状態。0件と区別しないと、登録済みの食品を
  /// 「無い」と思って作り直すことになる。
  @State private var loadFailed = false

  @State private var currentPage = 0
  @State private var isLoading = false
  @State private var hasMoreData = true
  private let pageSize = 20

  @FocusState private var isSearchFocused: Bool
  @State private var searchDebounceTimer: Timer?

  /// このシートで追加できたもの。閉じるまで残し、何を追加したか見て分かるようにする。
  @State private var addedEntries: [AddedEntry] = []
  /// 送信中の件数。タップ直後に反応を出すために通信完了を待たずに増やす。
  @State private var pendingCount = 0
  @State private var addFailureCount = 0
  @State private var showingAddFailure = false
  @State private var isUndoing = false
  @State private var undoFailure: OperationFailure?

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
        // 追加しても一覧からは消えないので、タップの結果は自分で示す必要がある。
        // 一瞬で消える表示は見逃せるため、シートを閉じるまで残す。
        .safeAreaInset(edge: .bottom) { addedSummaryBar }
        .sensoryFeedback(.success, trigger: addedEntries.count)
        .sensoryFeedback(.error, trigger: addFailureCount)
        .alert(
          NSLocalizedString("Couldn't add", comment: "Add failure alert title"),
          isPresented: $showingAddFailure
        ) {
          Button(NSLocalizedString("OK", comment: "Button title"), role: .cancel) {}
        } message: {
          Text(
            NSLocalizedString(
              "The meal was not saved. Check your connection and try again.",
              comment: "Add failure alert message"))
        }
        .operationFailureAlert($undoFailure)
      .navigationTitle(NSLocalizedString("Add Meal", comment: "Navigation title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          // 追加は即座に保存されるので、1件でも追加したあとに「キャンセル」と
          // 出すと取り消せるように読めてしまう。完了に切り替える。
          Button(
            addedEntries.isEmpty
              ? NSLocalizedString("Cancel", comment: "Button title")
              : NSLocalizedString("Done", comment: "Button title")
          ) {
            dismiss()
          }
        }
        // .confirmationAction に置くと塗りつぶしの確定ボタンとして描かれる。
        // 写真解析はこのシートの確定操作ではないので通常配置にする。
        ToolbarItem(placement: .topBarTrailing) {
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

  /// 追加したものを示す下部バー。送信中は即座に出し、完了後は内容に切り替える。
  @ViewBuilder
  private var addedSummaryBar: some View {
    if pendingCount > 0 || !addedEntries.isEmpty {
      HStack(spacing: 10) {
        if pendingCount > 0 {
          ProgressView()
            .controlSize(.small)

          Text(NSLocalizedString("Adding…", comment: "Add in progress"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if let latest = addedEntries.last {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 1) {
            Text(
              String(
                format: NSLocalizedString("Added %@", comment: "Added food confirmation"),
                latest.name)
            )
            .font(.subheadline.weight(.medium))
            .lineLimit(1)

            Text(addedTotalsText)
              .font(.caption)
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: 0)

        // 行をタップした時点で保存されるので、誤タップの戻し方がここにしか無い。
        // 無いとログのタブへ移動して消しに行くことになる。
        if !addedEntries.isEmpty {
          Button(NSLocalizedString("Undo", comment: "Undo last add")) {
            Task { await undoLastAdd() }
          }
          .font(.subheadline)
          .disabled(isUndoing)
        }

        // 追加後は検索欄に戻るためキーボードが出たままで、
        // ナビゲーションバーの閉じるボタンに手が届かない。ここにも置く。
        if !addedEntries.isEmpty {
          Button(NSLocalizedString("Done", comment: "Button title")) { dismiss() }
            .font(.subheadline.weight(.semibold))
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity)
      .background(.bar)
      .overlay(alignment: .top) {
        Divider()
      }
      .animation(.easeInOut(duration: 0.2), value: pendingCount)
      .animation(.easeInOut(duration: 0.2), value: addedEntries.count)
      .accessibilityElement(children: .combine)
    }
  }

  /// 「計2品 · 150 kcal」。1品でも合計を出して、何が積み上がったかを示す。
  /// 英語は 1 と複数で語形が変わるので stringsdict 側で出し分ける。
  private var addedTotalsText: String {
    return String.localizedStringWithFormat(
      NSLocalizedString("AddedSummary", comment: "Added items summary"),
      addedEntries.count,
      NutritionFormatter.formatCalories(addedEntries.totalCalories))
  }

  @ViewBuilder
  private var contentView: some View {
    Group {
      if isInitialLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if loadFailed {
        LoadFailureView { await resetAndSearch() }
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
          // 失敗したときに閉じるとエラーを見せられないので、成功時だけ閉じる。
          if await addFoodItem(createdFood) { dismiss() }
        }
      }
    }
  }

  private var searchResultsListView: some View {
    List {
      ForEach(searchResults, id: \.id) { item in
        // .plain にしないと食品名と数値まで着色されて読みにくくなる。
        // タップの受け付けは List 標準の行ハイライトが示す。
        Button { Task { await addFoodItem(item) } } label: { PastItemCard(item: item) }
          .buttonStyle(.plain)
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
              .accessibilityHidden(true)
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

  /// - Returns: 保存できたら true。失敗したら false を返し、呼び出し側が画面を閉じないようにする。
  @discardableResult
  private func addFoodItem(_ foodMaster: FoodMasterDTO) async -> Bool {
    let logItemID = UUID()
    let dto = LogItemCreateDTO(
      id: logItemID.uuidString,
      timestamp: ISO8601DateFormatter().string(from: date),
      logDate: LogItemDTO.formatLogDate(date),
      mealType: mealType.rawValue,
      numberOfServings: foodMaster.lastNumberOfServings,
      foodMasterId: foodMaster.id.uuidString,
      nutritionSnapshot: NutritionSnapshot.from(foodMaster)
    )

    // 通信の完了を待つと、回線によっては数秒のあいだ画面が無反応になる。
    // タップを受け付けたことは先に示す。
    pendingCount += 1
    defer { pendingCount -= 1 }

    do {
      _ = try await APIClient.shared.createLogItem(dto)
    } catch {
      // 握りつぶすと、保存されていないのに記録したつもりになれてしまう。
      print("AddItemView addFoodItem error: \(error)")
      addFailureCount += 1
      showingAddFailure = true
      return false
    }

    let nutrition = NutritionSnapshot.from(foodMaster)
      .scaled(by: foodMaster.lastNumberOfServings)
    addedEntries.append(
      AddedEntry(
        logItemID: logItemID,
        name: FoodRow.displayName(
          brand: foodMaster.brandName, product: foodMaster.productName),
        calories: nutrition.calories))

    announceAdded()

    searchText = ""
    await resetAndSearch()
    isSearchFocused = true
    return true
  }

  /// 直前に追加した1件を取り消す。
  private func undoLastAdd() async {
    guard let latest = addedEntries.last, !isUndoing else { return }
    isUndoing = true
    defer { isUndoing = false }

    do {
      try await APIClient.shared.deleteLogItem(id: latest.logItemID)
    } catch {
      undoFailure = .deleting(error)
      return
    }

    addedEntries.removeLast()
    AccessibilityNotification.Announcement(
      String(
        format: NSLocalizedString("Removed %@", comment: "Undo confirmation"), latest.name)
    ).post()
  }

  /// VoiceOver は画面の下部バーが変わっても読まないので、追加できたことを明示的に伝える。
  private func announceAdded() {
    guard let latest = addedEntries.last else { return }
    let message = String(
      format: NSLocalizedString("Added %@", comment: "Added food confirmation"), latest.name)
    AccessibilityNotification.Announcement(message).post()
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
        loadFailed = false
      }
    } catch {
      // 握りつぶすと「食品が1件も登録されていません」と出る。
      // 登録済みの食品を作り直す操作に直結する。
      await MainActor.run {
        isDataLoaded = true
        isInitialLoading = false
        loadFailed = searchResults.isEmpty
      }
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

/// このシートで追加できた1件。確認バーに出すぶんと、取り消しに要る記録の ID を持つ。
struct AddedEntry: Identifiable {
  let id = UUID()
  /// 作成した記録の ID。取り消すときにこれを消す。
  let logItemID: UUID
  let name: String
  let calories: Double
}

extension Array where Element == AddedEntry {
  /// 確認バーに出す累計カロリー。
  var totalCalories: Double {
    reduce(0) { $0 + $1.calories }
  }
}
