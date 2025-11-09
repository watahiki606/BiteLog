import SwiftData
import SwiftUI

struct AddItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Binding var selectedTab: Int

  let mealType: MealType
  var selectedDate: Date

  @State private var searchText = ""
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
  
  // 追加成功時のフィードバック表示用
  @State private var showAddedFeedback = false
  @State private var lastAddedItem: String = ""
  @State private var feedbackQueue: [String] = []
  @State private var isProcessingFeedback = false
  
  // 新規作成シート表示用
  @State private var showQuickCreationSheet = false
  
  // AI機能用
  @State private var showingPhotoPicker = false
  @State private var selectedImage: UIImage?
  @State private var isAnalyzing = false
  @State private var analysisResult: FoodAnalysisResult?
  @State private var showingAnalysisResult = false
  @State private var analysisError: String?
  @StateObject private var rewardedAdManager = RewardedAdManager.shared
  @StateObject private var interstitialAdManager = InterstitialAdManager.shared

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

        mainContentView
      }
      .navigationTitle(NSLocalizedString("Add Meal", comment: "Navigation title"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
        }
        
        // AIカメラボタン
        ToolbarItem(placement: .confirmationAction) {
          Button {
            showRewardAdAndOpenCamera()
          } label: {
            Image(systemName: "camera.viewfinder")
              .font(.title3)
          }
          .buttonStyle(PlainButtonStyle())
        }
      }
      .onAppear {
        // 画面が表示されたときにデータをロード
        if !isDataLoaded {
          loadFoodMasters()
        }
      }
      .sheet(isPresented: $showingPhotoPicker) {
        PhotoPickerView(selectedImage: $selectedImage) { image in
          analyzeImage(image)
        }
      }
      .sheet(isPresented: $showingAnalysisResult) {
        if let result = analysisResult, let image = selectedImage {
          AIAnalysisResultView(
            result: result,
            image: image,
            mealType: mealType,
            date: date,
            onSave: {
              dismiss()
            }
          )
        }
      }
      .alert(NSLocalizedString("Analysis Error", comment: "Alert title"), isPresented: .constant(analysisError != nil)) {
        Button(NSLocalizedString("OK", comment: "Button title"), role: .cancel) {
          analysisError = nil
        }
      } message: {
        if let error = analysisError {
          Text(error)
        }
      }
      .overlay {
        if isAnalyzing {
          ZStack {
            Color.black.opacity(0.4)
              .ignoresSafeArea()
            VStack(spacing: 16) {
              ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
              Text(NSLocalizedString("Analyzing food...", comment: "Loading message"))
                .foregroundColor(.white)
                .font(.headline)
            }
            .padding(30)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
            .shadow(radius: 10)
          }
        }
      }
    }
  }
  
  // リワード広告を表示してからカメラを開く（広告が準備できていない場合はそのままカメラを開く）
  private func showRewardAdAndOpenCamera() {
    print("📸 AIカメラ起動要求")
    
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let rootViewController = windowScene.windows.first?.rootViewController else {
      print("⚠️ rootViewControllerが取得できません - 直接カメラを開きます")
      showingPhotoPicker = true
      return
    }
    
    // 広告が準備できている場合は表示し、準備できていない場合はそのままカメラを開く
    rewardedAdManager.showAd(from: rootViewController) { earnedReward in
      print("📸 リワード広告のコールバックが呼ばれました（報酬獲得: \(earnedReward)）")
      // 報酬獲得の有無に関わらず、カメラを開く
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        print("📸 カメラを開きます（showingPhotoPicker = true）")
        showingPhotoPicker = true
        print("📸 showingPhotoPicker設定完了: \(showingPhotoPicker)")
      }
    }
  }
  
  // AI画像分析
  private func analyzeImage(_ image: UIImage) {
    Task {
      await MainActor.run {
        isAnalyzing = true
        showingPhotoPicker = false
      }
      
      do {
        let result = try await AIFoodAnalyzer.shared.analyzeFood(image: image)
        
        await MainActor.run {
          isAnalyzing = false
          analysisResult = result
          showingAnalysisResult = true
          
          // AI分析成功後にインタースティシャル広告を表示（頻度制限付き）
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showInterstitialAdIfReady()
          }
        }
      } catch {
        await MainActor.run {
          isAnalyzing = false
          analysisError = error.localizedDescription
        }
      }
    }
  }
  
  // インタースティシャル広告を表示
  private func showInterstitialAdIfReady() {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let rootViewController = windowScene.windows.first?.rootViewController else {
      return
    }
    
    interstitialAdManager.showAd(from: rootViewController)
  }
  
  // メインコンテンツ部分を切り出し
  private var mainContentView: some View {
    VStack {
      searchBarView
      
      // 追加成功時のフィードバック表示
      feedbackView
      
      contentView
    }
  }
  
  // 検索バー部分
  private var searchBarView: some View {
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
  }
  
  // フィードバック表示部分
  private var feedbackView: some View {
    Group {
      if showAddedFeedback {
        HStack {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
          
          Text(String(format: NSLocalizedString("%@ added to %@", comment: "Added food feedback"), lastAddedItem, mealType.localizedName))
            .font(.subheadline)
            .foregroundColor(.primary)
          
          Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
        .transition(.asymmetric(
          insertion: .move(edge: .top).combined(with: .opacity),
          removal: .move(edge: .top).combined(with: .opacity)
        ))
      }
    }
  }
  
  // メインコンテンツ（状態に応じて表示内容が変わる部分）
  private var contentView: some View {
    Group {
      if isInitialLoading {
        // 初回データロード中の表示
        ProgressView()
          .padding()
      } else if searchResults.isEmpty && !isDataLoaded {
        // マスターデータが0件の場合に表示するビュー
        EmptyFoodMasterPromptView(selectedTab: $selectedTab, dismiss: dismiss)
      } else if searchResults.isEmpty && isDataLoaded {
        // 検索結果がない場合のメッセージ
        emptySearchResultsView
      } else {
        // 検索結果一覧
        searchResultsListView
      }
    }
  }
  
  // 検索結果一覧
  private var searchResultsListView: some View {
    List {
      ForEach(searchResults, id: \.id) { item in
        Button {
          addFoodItem(item)
        } label: {
          PastItemCard(item: item)
        }
        .buttonStyle(ScaleButtonStyle())
        .onAppear {
          // リストの最後のアイテムが表示されたら次のページを読み込む
          if item == searchResults.last && hasMoreData && !isLoading {
            loadMoreContent()
          }
        }
      }
      
      // 検索テキストがある場合、「新規作成して追加」ボタンを表示
      if !searchText.isEmpty && !hasMoreData {
        Section {
          Button {
            showQuickCreationSheet = true
          } label: {
            HStack {
              Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)
              
              VStack(alignment: .leading, spacing: 4) {
                Text(String(format: NSLocalizedString("Create and add \"%@\"", comment: "Create and add button"), searchText))
                  .font(.headline)
                  .foregroundColor(.primary)
                
                Text(NSLocalizedString("Quickly add a new food item", comment: "Quick add description"))
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              
              Spacer()
              
              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
          }
          .buttonStyle(PlainButtonStyle())
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
    .sheet(isPresented: $showQuickCreationSheet) {
      FoodMasterFormView(mode: .quickAdd(initialProductName: searchText)) { createdFood in
        // 作成後すぐに追加
        addFoodItem(createdFood)
        // Log画面に戻る
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          dismiss()
        }
      }
    }
  }
  
  // 検索結果がない場合のメッセージ
  private var emptySearchResultsView: some View {
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

      // 検索テキストがある場合は「新規作成して追加」ボタンを表示
      if !searchText.isEmpty {
        Button {
          showQuickCreationSheet = true
        } label: {
          HStack {
            Image(systemName: "plus.circle.fill")
              .font(.title2)
            
            Text(String(format: NSLocalizedString("Create and add \"%@\"", comment: "Create and add button"), searchText))
              .fontWeight(.semibold)
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(10)
        }
        .padding(.top, 10)
        
        Text(NSLocalizedString("or", comment: "Or text"))
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

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
          .background(Color(UIColor.systemGray5))
          .foregroundColor(.primary)
          .cornerRadius(10)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
    .sheet(isPresented: $showQuickCreationSheet) {
      FoodMasterFormView(mode: .quickAdd(initialProductName: searchText)) { createdFood in
        // 作成後すぐに追加
        addFoodItem(createdFood)
        // Log画面に戻る
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          dismiss()
        }
      }
    }
  }
  
  // フードアイテムを追加する関数
  private func addFoodItem(_ foodMaster: FoodMaster) {
    let newLogItem = LogItem(
      timestamp: date,
      mealType: mealType,
      numberOfServings: foodMaster.lastNumberOfServings,
      foodMaster: foodMaster
    )
    modelContext.insert(newLogItem)
    
    // フィードバックをキューに追加
    let feedbackText = "\(foodMaster.brandName) \(foodMaster.productName)"
    feedbackQueue.append(feedbackText)
    
    // キューの処理を開始
    processFeedbackQueue()
    
    // 検索ワードをクリアして検索欄にフォーカスする
    searchText = ""
    resetAndSearch()
    searchFieldIsFocused = true
    
    // シートは閉じない（dismiss()を呼び出さない）
  }
  
  // フィードバックキューを処理する関数
  private func processFeedbackQueue() {
    guard !isProcessingFeedback, !feedbackQueue.isEmpty else { return }
    
    isProcessingFeedback = true
    
    // キューから最初のアイテムを取り出す
    if let nextItem = feedbackQueue.first {
      feedbackQueue.removeFirst()
      lastAddedItem = nextItem
      
      // フィードバックを表示
      withAnimation(.easeIn(duration: 0.2)) {
        showAddedFeedback = true
      }
      
      // 0.5秒後にフィードバックを非表示にして、次のアイテムを処理
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        withAnimation(.easeOut(duration: 0.2)) {
          showAddedFeedback = false
        }
        
        // 少し待ってから次のフィードバックを処理
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          isProcessingFeedback = false
          processFeedbackQueue()
        }
      }
    } else {
      isProcessingFeedback = false
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
  
  // 常に最後に使用したサービング数を使用
  private var servings: Double {
    return item.lastNumberOfServings
  }

  init(item: FoodMaster) {
    self.item = item
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(item.brandName) \(item.productName)")
            .font(.headline)
        }

        Spacer()

        // カロリーを固定のサービング数に応じて計算
        Text("\(item.calories * servings, specifier: "%.0f")")
          .font(.title3.bold())
          + Text(" kcal")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      HStack(spacing: 8) {
        // 栄養素の値も固定のサービング数に応じて計算
        MacroNutrientBadge(label: "P", value: item.protein * servings, color: .blue)
        MacroNutrientBadge(label: "F", value: item.fat * servings, color: .yellow)
        MacroNutrientBadge(label: "S", value: item.sugar * servings, color: .green)
        MacroNutrientBadge(label: "Fiber", value: item.dietaryFiber * servings, color: .brown)
      }
      
      // 分量の表示を追加
      HStack {
        Text(NSLocalizedString("Servings:", comment: "Servings label"))
          .font(.subheadline)
          .foregroundColor(.secondary)

        Text("\(NutritionFormatter.formatNutrition(servings)) \(item.portionUnit)")
          .font(.subheadline)
          .foregroundColor(.primary)

        Spacer()
      }
    }
    .padding()
    .background(Color(UIColor.systemBackground))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
  }
}
