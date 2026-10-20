import OSLog
import SwiftUI
import PhotosUI

// 写真選択画面
struct PhotoPickerView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var selectedImage: UIImage?
  var onAnalyze: (UIImage, String?) -> Void

  @State private var showingImagePicker = false
  @State private var showingCamera = false
  @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
  @State private var note: String = ""
  
  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        if let image = selectedImage {
          // 選択された画像を表示
          VStack(spacing: 16) {
            Image(uiImage: image)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 400)
              .cornerRadius(12)
              .shadow(radius: 5)

            VStack(alignment: .leading, spacing: 4) {
              Text(NSLocalizedString("Note (optional)", comment: "Label"))
                .font(.caption)
                .foregroundColor(.secondary)
              TextField(
                NSLocalizedString("e.g. Left half, ate two", comment: "Placeholder"),
                text: $note
              )
              .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            HStack(spacing: 16) {
              Button {
                selectedImage = nil
                note = ""
              } label: {
                Label(NSLocalizedString("Reselect", comment: "Button title"), systemImage: "arrow.clockwise")
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(Color.gray.opacity(0.2))
                  .foregroundColor(.primary)
                  .cornerRadius(10)
              }

              Button {
                let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                onAnalyze(image, trimmedNote.isEmpty ? nil : trimmedNote)
              } label: {
                Label(NSLocalizedString("Analyze", comment: "Button title"), systemImage: "sparkles")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
            }
            .padding(.horizontal)
          }
        } else {
          // 写真選択のオプション
          VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
              .font(.system(size: 80))
              .foregroundStyle(.tint)
              .padding()
              .accessibilityHidden(true)
            
            Text(NSLocalizedString("Select Photo", comment: "Title"))
              .font(.title2)
              .fontWeight(.bold)
            
            Text(NSLocalizedString("Take a photo or choose from your library", comment: "Description"))
              .font(.subheadline)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal)
            
            VStack(spacing: 12) {
              Button {
                sourceType = .camera
                showingCamera = true
              } label: {
                Label(NSLocalizedString("Take Photo", comment: "Button title"), systemImage: "camera.fill")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
              .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
              
              Button {
                sourceType = .photoLibrary
                showingImagePicker = true
              } label: {
                Label(
                  NSLocalizedString("Choose from Library", comment: "Button title"),
                  systemImage: "photo.fill"
                )
                .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
              .controlSize(.large)
            }
            .padding(.horizontal)
          }
        }
      }
      .padding()
      .navigationTitle(NSLocalizedString("AI Food Analysis", comment: "Navigation title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Button title")) {
            dismiss()
          }
        }
      }
      .sheet(isPresented: $showingImagePicker) {
        ImagePicker(sourceType: sourceType, selectedImage: $selectedImage)
      }
      .sheet(isPresented: $showingCamera) {
        ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
      }
    }
  }
}

// UIImagePickerControllerのSwiftUIラッパー
struct ImagePicker: UIViewControllerRepresentable {
  let sourceType: UIImagePickerController.SourceType
  @Binding var selectedImage: UIImage?
  @Environment(\.dismiss) var dismiss
  
  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = sourceType
    picker.delegate = context.coordinator
    return picker
  }
  
  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
  
  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }
  
  class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: ImagePicker
    
    init(_ parent: ImagePicker) {
      self.parent = parent
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      if let image = info[.originalImage] as? UIImage {
        parent.selectedImage = image
      }
      parent.dismiss()
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }
  }
}

// AI分析結果表示画面
struct AIAnalysisResultView: View {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.bitelog", category: "PhotoAnalysis")

  @Environment(\.dismiss) var dismiss

  let image: UIImage
  /// 公式の値を調べ直すときに、最初の解析と同じメモを渡す
  let note: String?
  let mealType: MealType
  let date: Date
  var onSave: () -> Void

  /// 表示中の解析結果。公式の値を調べたら入れ替わる
  @State private var current: FoodAnalysisResult
  /// 公式の値を調べる名前。写真のロゴや文字から読み取った見当を入れておく
  @State private var officialName: String
  @State private var isLookingUpOfficial = false
  @State private var lookupError: String?

  @State private var showingSaveConfirmation = false
  @State private var saveError: String?

  /// 同じものが登録済みでないか。自分のものに限らず探す。
  ///
  /// 写真から作った食品は名前が毎回変わるので、放っておくと同じおにぎりが
  /// 「NL…」「国産…」と別々に積まれ、使用回数が1のまま育たない。育たないから
  /// 検索の上位にも出ず、次もまた写真を撮ることになる。その輪をここで切る。
  @State private var candidates: [FoodMasterDTO] = []
  @State private var isSaving = false

  // 編集可能なフィールド
  @State private var productName: String
  @State private var calories: String
  @State private var protein: String
  @State private var fat: String
  @State private var netCarbs: String
  @State private var dietaryFiber: String
  @State private var portionAmount: String
  @State private var portionUnit: String

  init(
    result: FoodAnalysisResult, image: UIImage, note: String?, mealType: MealType, date: Date,
    onSave: @escaping () -> Void
  ) {
    self.image = image
    self.note = note
    self.mealType = mealType
    self.date = date
    self.onSave = onSave

    _current = State(initialValue: result)
    _officialName = State(initialValue: result.menuGuess ?? "")

    // 初期値を設定
    _productName = State(initialValue: result.productName)
    _calories = State(initialValue: String(format: "%.0f", result.calories))
    _protein = State(initialValue: NutritionFormatter.formatNutrition(result.protein))
    _fat = State(initialValue: NutritionFormatter.formatNutrition(result.fat))
    _netCarbs = State(initialValue: NutritionFormatter.formatNutrition(result.netCarbs))
    _dietaryFiber = State(initialValue: NutritionFormatter.formatNutrition(result.dietaryFiber))
    _portionAmount = State(initialValue: NutritionFormatter.formatNutrition(result.portionAmount))
    _portionUnit = State(initialValue: result.portionUnit)
  }
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          // 画像表示
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 300)
            .cornerRadius(12)
            .shadow(radius: 5)
          
          // 信頼度表示
          confidenceBadge

          candidatesSection

          // 分析結果
          VStack(spacing: 16) {
            Text(NSLocalizedString("Analysis Result", comment: "Title"))
              .font(.title2)
              .fontWeight(.bold)
            
            Text(NSLocalizedString("Tap to edit values", comment: "Hint"))
              .font(.caption)
              .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
              EditableField(icon: "fork.knife", label: NSLocalizedString("Food Name", comment: "Label"), text: $productName, keyboardType: .default)
              EditableField(icon: "flame.fill", label: NSLocalizedString("Calories", comment: "Label"), text: $calories, unit: "kcal", keyboardType: .decimalPad, color: .orange)
              
              HStack(spacing: 12) {
                EditableField(icon: "scalemass.fill", label: NSLocalizedString("Portion", comment: "Label"), text: $portionAmount, keyboardType: .decimalPad)
                EditableField(icon: "tag", label: NSLocalizedString("Unit", comment: "Label"), text: $portionUnit, keyboardType: .default)
              }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            
            VStack(spacing: 12) {
              Text(NSLocalizedString("Nutritional Information", comment: "Section title"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
              
              EditableField(icon: "circle.fill", label: NSLocalizedString("Protein", comment: "Label"), text: $protein, unit: "g", keyboardType: .decimalPad, color: .blue)
              EditableField(icon: "circle.fill", label: NSLocalizedString("Fat", comment: "Label"), text: $fat, unit: "g", keyboardType: .decimalPad, color: .yellow)
              EditableField(icon: "circle.fill", label: NSLocalizedString("Sugar", comment: "Label"), text: $netCarbs, unit: "g", keyboardType: .decimalPad, color: .green)
              EditableField(icon: "circle.fill", label: NSLocalizedString("Dietary Fiber", comment: "Label"), text: $dietaryFiber, unit: "g", keyboardType: .decimalPad, color: .brown)
              
              // 炭水化物は計算値として表示（編集不可）
              let carbs = (Double(netCarbs) ?? 0) + (Double(dietaryFiber) ?? 0)
              ResultRow(icon: "circle.fill", label: NSLocalizedString("Carbohydrates", comment: "Label"), value: "\(NutritionFormatter.formatNutrition(carbs))g", color: .purple)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)

            officialLookupSection
          }
          .padding(.horizontal)
          
          // 注意書き
          Text(NSLocalizedString("Note: Nutritional values are estimates by AI and may not be accurate.", comment: "Disclaimer"))
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
          
          // 保存ボタン
          Button {
            showingSaveConfirmation = true
          } label: {
            Text(NSLocalizedString("Save to Food Log", comment: "Button title"))
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .padding(.horizontal)
          .padding(.bottom)
        }
        .padding(.vertical)
      }
      .navigationTitle(NSLocalizedString("Analysis Complete", comment: "Navigation title"))
      .navigationBarTitleDisplayMode(.inline)
      .task { await findCandidates(for: current) }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Button title")) {
            dismiss()
          }
        }
      }
      .alert(NSLocalizedString("Save Food Item", comment: "Alert title"), isPresented: $showingSaveConfirmation) {
        Button(NSLocalizedString("Save", comment: "Button title")) {
          saveFoodItem()
        }
        Button(NSLocalizedString("Cancel", comment: "Button title"), role: .cancel) {}
      } message: {
        Text(String(format: NSLocalizedString("Save \"%@\" to %@?", comment: "Alert message"), productName, mealType.localizedName))
      }
      .alert(NSLocalizedString("Save Failed", comment: "Alert title"), isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
        Button(NSLocalizedString("OK", comment: "Button title"), role: .cancel) {}
      } message: {
        Text(saveError ?? "")
      }
    }
  }
  
  /// 写真だけの値に満足できないときだけ、公式の値を調べる。いつもは撮って保存するだけで済むよう、
  /// 先に店名を入れさせず、結果を見てから選べるようにする。
  private var officialLookupSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("Store or product name", comment: "Label"))
        .font(.headline)
      TextField(
        NSLocalizedString("e.g. Sushiro salmon avocado", comment: "Placeholder"),
        text: $officialName
      )
      .textFieldStyle(.roundedBorder)
      Text(
        NSLocalizedString(
          "We look up the nutrition facts the store or maker publishes and replace the values. This takes about 10 seconds.",
          comment: "Official lookup hint"))
        .font(.caption)
        .foregroundColor(.secondary)

      Button {
        Task { await lookUpOfficial() }
      } label: {
        if isLookingUpOfficial {
          HStack(spacing: 8) {
            ProgressView()
            Text(NSLocalizedString("Looking up official nutrition facts...", comment: "Loading message"))
          }
          .frame(maxWidth: .infinity)
        } else {
          Label(NSLocalizedString("Look up official nutrition facts", comment: "Button title"), systemImage: "globe")
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.bordered)
      .disabled(isLookingUpOfficial || officialName.trimmingCharacters(in: .whitespaces).isEmpty)

      if let lookupError {
        Text(lookupError)
          .font(.caption)
          .foregroundColor(.red)
      }

      basisNote
        .frame(maxWidth: .infinity)
    }
    .padding()
    .background(Color(UIColor.secondarySystemBackground))
    .cornerRadius(12)
  }

  private func lookUpOfficial() async {
    let name = officialName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    isLookingUpOfficial = true
    lookupError = nil
    defer { isLookingUpOfficial = false }
    do {
      let looked = try await AIFoodAnalyzer.shared.analyzeFood(image: image, note: note, menuName: name)
      current = looked
      productName = looked.productName
      calories = String(format: "%.0f", looked.calories)
      protein = NutritionFormatter.formatNutrition(looked.protein)
      fat = NutritionFormatter.formatNutrition(looked.fat)
      netCarbs = NutritionFormatter.formatNutrition(looked.netCarbs)
      dietaryFiber = NutritionFormatter.formatNutrition(looked.dietaryFiber)
      portionAmount = NutritionFormatter.formatNutrition(looked.portionAmount)
      portionUnit = looked.portionUnit
      await findCandidates(for: looked)
    } catch {
      lookupError = error.localizedDescription
    }
  }

  /// 公式の値を調べたあと、値が何に基づくかを出す。
  @ViewBuilder
  private var basisNote: some View {
    switch current.basis {
    case .photoOnly, .nutritionLabel:
      EmptyView()
    case .web(let source):
      VStack(spacing: 6) {
        Label(NSLocalizedString("Values found on the web", comment: "Analysis basis"), systemImage: "globe")
          .font(.subheadline)
        // 似せたドメインのページを拾うこともあるので、押す前にどこのページか読めるようドメインを出す
        if let source, let host = source.host() {
          Link(String(format: NSLocalizedString("Source: %@", comment: "Analysis source"), host), destination: source)
            .font(.subheadline)
        }
        basisText(
          NSLocalizedString(
            "Stores often publish only calories, so the other nutrients may be estimates.",
            comment: "Analysis basis"))
      }
    case .estimatedAfterSearch:
      basisText(
        NSLocalizedString(
          "No official values were found, so these are estimated from the photo.", comment: "Analysis basis"))
    }
  }

  private func basisText(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundColor(.secondary)
      .multilineTextAlignment(.center)
      .padding(.horizontal)
  }

  private var confidenceBadge: some View {
    HStack(spacing: 4) {
      Image(systemName: confidenceIcon)
        .foregroundColor(confidenceColor)
      Text(confidenceText)
        .font(.subheadline)
        .foregroundColor(confidenceColor)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(confidenceColor.opacity(0.1))
    .cornerRadius(20)
  }
  
  private var confidenceIcon: String {
    switch current.confidence {
    case "high": return "checkmark.circle.fill"
    case "low": return "exclamationmark.triangle.fill"
    default: return "info.circle.fill"
    }
  }
  
  private var confidenceColor: Color {
    switch current.confidence {
    case "high": return .green
    case "low": return .orange
    default: return .blue
    }
  }
  
  private var confidenceText: String {
    switch current.confidence {
    case "high": return NSLocalizedString("High Confidence", comment: "Confidence level")
    case "low": return NSLocalizedString("Low Confidence", comment: "Confidence level")
    default: return NSLocalizedString("Medium Confidence", comment: "Confidence level")
    }
  }
  
  /// 登録済みの同じものを出す。選べば写真から作り直さずに済む。
  @ViewBuilder
  private var candidatesSection: some View {
    if !candidates.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text(NSLocalizedString("Registered foods", comment: "AI candidate section title"))
          .font(.headline)

        Text(
          NSLocalizedString(
            "Pick one to log it without adding a new food. The ones you eat often then rise to the top of search.",
            comment: "AI candidate section description")
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        ForEach(candidates) { foodMaster in
          Button {
            Task { await logExisting(foodMaster) }
          } label: {
            // 似た名前から1つ選ばせる場面なので、名前は途中で切らない。
            FoodMasterRow(foodMaster: foodMaster, titleLineLimit: nil)
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                Color(UIColor.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
          .disabled(isSaving)
        }
      }
      .padding(.horizontal)
    }
  }

  /// 他の人の項目と AI の推定値も含めて探す。チェーン店のメニューは誰かが登録していれば、
  /// Web で調べずに済む。見当の名前で当たらなければ料理名の頭で探す。
  private func findCandidates(for analysis: FoodAnalysisResult) async {
    for query in AIFoodAnalyzer.candidateQueries(menuGuess: analysis.menuGuess, productName: analysis.productName) {
      do {
        let items = try await APIClient.shared.fetchFoodMasters(query: query, limit: 5).items
        if !items.isEmpty {
          candidates = items
          return
        }
      } catch {
        // 探せなくても写真の値で記録できるので、候補なしとして進む。原因を追えるようログには残す
        Self.logger.error("登録済みの食品を探せなかった: \(error.localizedDescription, privacy: .public)")
      }
    }
    candidates = []
  }

  /// 既存の食品として記録する。マスタを増やさず、その食品の使用回数が育つ。
  private func logExisting(_ foodMaster: FoodMasterDTO) async {
    isSaving = true
    defer { isSaving = false }

    let dto = LogItemCreateDTO(
      id: UUID().uuidString,
      timestamp: ISO8601DateFormatter().string(from: LogItemDTO.timestamp(for: date)),
      logDate: LogItemDTO.formatLogDate(date),
      mealType: mealType.rawValue,
      numberOfServings: foodMaster.servingsToLog,
      foodMasterId: foodMaster.id.uuidString,
      nutritionSnapshot: NutritionSnapshot.from(foodMaster)
    )
    do {
      _ = try await APIClient.shared.createLogItem(dto)
      onSave()
      dismiss()
    } catch {
      saveError = error.localizedDescription
    }
  }

  private func saveFoodItem() {
    let caloriesValue = Double(calories) ?? 0
    let proteinValue = Double(protein) ?? 0
    let fatValue = Double(fat) ?? 0
    let netCarbsValue = Double(netCarbs) ?? 0
    let dietaryFiberValue = Double(dietaryFiber) ?? 0
    let portionAmountValue = Double(portionAmount) ?? 1

    Task {
      do {
        let fmDTO = FoodMasterCreateDTO(
          id: UUID().uuidString,
          brandName: "AI",
          productName: productName,
          calories: caloriesValue,
          dietaryFiber: dietaryFiberValue,
          netCarbs: netCarbsValue,
          fat: fatValue,
          protein: proteinValue,
          portionSize: portionAmountValue,
          portionUnit: portionUnit,
          uniqueKey: FoodMasterDTO.createUniqueKey(
            brandName: "AI", productName: productName, portionUnit: portionUnit)
        )
        let fm = try await APIClient.shared.createFoodMaster(fmDTO)

        let logDTO = LogItemCreateDTO(
          id: UUID().uuidString,
          timestamp: ISO8601DateFormatter().string(from: LogItemDTO.timestamp(for: date)),
          logDate: LogItemDTO.formatLogDate(date),
          mealType: mealType.rawValue,
          numberOfServings: portionAmountValue,
          foodMasterId: fm.id.uuidString,
          nutritionSnapshot: NutritionSnapshot.from(fm)
        )
        _ = try await APIClient.shared.createLogItem(logDTO)
        await MainActor.run {
          onSave()
          dismiss()
        }
      } catch {
        print("AIAnalysisResultView saveFoodItem error: \(error)")
        await MainActor.run {
          saveError = NSLocalizedString("Failed to save. Please try again.", comment: "Save error message")
        }
      }
    }
  }
}

// 結果行コンポーネント
struct ResultRow: View {
  let icon: String
  let label: String
  let value: String
  var color: Color = .primary
  
  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundStyle(color)
        .frame(width: 24)
        .accessibilityHidden(true)
      
      Text(label)
        .foregroundColor(.primary)
      
      Spacer()
      
      Text(value)
        .fontWeight(.semibold)
        .foregroundColor(color)
    }
    .padding(.vertical, 4)
  }
}

// 編集可能フィールドコンポーネント
struct EditableField: View {
  let icon: String
  let label: String
  @Binding var text: String
  var unit: String = ""
  var keyboardType: UIKeyboardType = .default
  var color: Color = .primary
  
  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundStyle(color)
        .frame(width: 24)
        .accessibilityHidden(true)
      
      Text(label)
        .foregroundColor(.primary)
      
      Spacer()
      
      TextField("0", text: $text)
        .keyboardType(keyboardType)
        .multilineTextAlignment(.trailing)
        .fontWeight(.semibold)
        .foregroundColor(color)
        .frame(maxWidth: 100)
      
      if !unit.isEmpty {
        Text(unit)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(Color(UIColor.tertiarySystemBackground))
    .cornerRadius(8)
  }
}

