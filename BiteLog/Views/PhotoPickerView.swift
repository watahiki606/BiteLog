import SwiftUI
import PhotosUI

// 写真選択画面
struct PhotoPickerView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var selectedImage: UIImage?
  var onAnalyze: (UIImage) -> Void
  
  @State private var showingImagePicker = false
  @State private var showingCamera = false
  @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
  
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
            
            HStack(spacing: 16) {
              Button {
                selectedImage = nil
              } label: {
                Label(NSLocalizedString("Reselect", comment: "Button title"), systemImage: "arrow.clockwise")
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(Color.gray.opacity(0.2))
                  .foregroundColor(.primary)
                  .cornerRadius(10)
              }
              
              Button {
                onAnalyze(image)
              } label: {
                Label(NSLocalizedString("Analyze", comment: "Button title"), systemImage: "sparkles")
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(Color.blue)
                  .foregroundColor(.white)
                  .cornerRadius(10)
              }
            }
            .padding(.horizontal)
          }
        } else {
          // 写真選択のオプション
          VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
              .font(.system(size: 80))
              .foregroundColor(.blue)
              .padding()
            
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
                HStack {
                  Image(systemName: "camera.fill")
                    .font(.title3)
                  Text(NSLocalizedString("Take Photo", comment: "Button title"))
                    .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
              }
              .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
              
              Button {
                sourceType = .photoLibrary
                showingImagePicker = true
              } label: {
                HStack {
                  Image(systemName: "photo.fill")
                    .font(.title3)
                  Text(NSLocalizedString("Choose from Library", comment: "Button title"))
                    .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(12)
              }
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
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  
  let result: FoodAnalysisResult
  let image: UIImage
  let mealType: MealType
  let date: Date
  var onSave: () -> Void
  
  @State private var showingSaveConfirmation = false
  
  // 編集可能なフィールド
  @State private var productName: String
  @State private var calories: String
  @State private var protein: String
  @State private var fat: String
  @State private var netCarbs: String
  @State private var dietaryFiber: String
  @State private var portionAmount: String
  @State private var portionUnit: String

  init(result: FoodAnalysisResult, image: UIImage, mealType: MealType, date: Date, onSave: @escaping () -> Void) {
    self.result = result
    self.image = image
    self.mealType = mealType
    self.date = date
    self.onSave = onSave

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
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
              .padding()
              .background(Color.blue)
              .foregroundColor(.white)
              .cornerRadius(12)
          }
          .padding(.horizontal)
          .padding(.bottom)
        }
        .padding(.vertical)
      }
      .navigationTitle(NSLocalizedString("Analysis Complete", comment: "Navigation title"))
      .navigationBarTitleDisplayMode(.inline)
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
    }
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
    switch result.confidence {
    case "high": return "checkmark.circle.fill"
    case "low": return "exclamationmark.triangle.fill"
    default: return "info.circle.fill"
    }
  }
  
  private var confidenceColor: Color {
    switch result.confidence {
    case "high": return .green
    case "low": return .orange
    default: return .blue
    }
  }
  
  private var confidenceText: String {
    switch result.confidence {
    case "high": return NSLocalizedString("High Confidence", comment: "Confidence level")
    case "low": return NSLocalizedString("Low Confidence", comment: "Confidence level")
    default: return NSLocalizedString("Medium Confidence", comment: "Confidence level")
    }
  }
  
  private func saveFoodItem() {
    // 編集された値をDoubleに変換
    let caloriesValue = Double(calories) ?? 0
    let proteinValue = Double(protein) ?? 0
    let fatValue = Double(fat) ?? 0
    let netCarbsValue = Double(netCarbs) ?? 0
    let dietaryFiberValue = Double(dietaryFiber) ?? 0
    let portionAmountValue = Double(portionAmount) ?? 1

    // FoodMasterを作成
    let foodMaster = FoodMaster(
      brandName: "AI",
      productName: productName,
      calories: caloriesValue,
      netCarbs: netCarbsValue,
      dietaryFiber: dietaryFiberValue,
      fat: fatValue,
      protein: proteinValue,
      portionSize: portionAmountValue,
      portionUnit: portionUnit
    )
    modelContext.insert(foodMaster)
    
    // LogItemを作成
    let logItem = LogItem(
      timestamp: date,
      mealType: mealType,
      numberOfServings: portionAmountValue,
      foodMaster: foodMaster
    )
    modelContext.insert(logItem)
    
    try? modelContext.save()
    
    onSave()
    dismiss()
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
        .foregroundColor(color)
        .frame(width: 24)
      
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
        .foregroundColor(color)
        .frame(width: 24)
      
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

