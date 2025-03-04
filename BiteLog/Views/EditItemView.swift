import SwiftData
import SwiftUI

struct EditItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Bindable var item: LogItem

  @State private var brandName: String = ""
  @State private var productName: String = ""
  @State private var portionUnit: String = ""
  @State private var numberOfServings: String = "1"
  @State private var foodMaster: FoodMaster?
  
  // 栄養素の値を計算プロパティとして定義
  private var calories: String {
    return String(format: "%.2f", foodMaster?.calories ?? 0)
  }
  
  private var protein: String {
    return String(format: "%.2f", foodMaster?.protein ?? 0)
  }
  
  private var fat: String {
    return String(format: "%.2f", foodMaster?.fat ?? 0)
  }
  
  private var carbohydrates: String {
    return String(format: "%.2f", foodMaster?.carbohydrates ?? 0)
  }
  
  private var servingsValue: Double {
    return Double(numberOfServings) ?? 1.0
  }
  
  private var totalCalories: Double {
    return (foodMaster?.calories ?? 0) * servingsValue
  }
  
  private var totalProtein: Double {
    return (foodMaster?.protein ?? 0) * servingsValue
  }
  
  private var totalFat: Double {
    return (foodMaster?.fat ?? 0) * servingsValue
  }
  
  private var totalCarbs: Double {
    return (foodMaster?.carbohydrates ?? 0) * servingsValue
  }

  init(item: LogItem) {
    self.item = item
    _brandName = State(initialValue: item.brandName)
    _productName = State(initialValue: item.productName)
    _portionUnit = State(initialValue: item.foodMaster?.portionUnit ?? "")
    _numberOfServings = State(initialValue: String(format: "%.1f", item.numberOfServings))
    _foodMaster = State(initialValue: item.foodMaster)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color(UIColor.systemGroupedBackground)
          .ignoresSafeArea()

        ScrollView {
          VStack(spacing: 24) {
            // 基本情報カード
            CardView(title: NSLocalizedString("Basic Info", comment: "Form section title")) {
              VStack(spacing: 16) {
                CustomTextField(
                  icon: "tag.fill",
                  placeholder: NSLocalizedString("Brand", comment: "Brand name field"),
                  text: $brandName
                )

                CustomTextField(
                  icon: "cart.fill",
                  placeholder: NSLocalizedString("Product", comment: "Product name field"),
                  text: $productName
                )

                HStack {
                  CustomTextField(
                    icon: "number",
                    placeholder: NSLocalizedString("Servings (e.g. 1.5)", comment: "Servings field"),
                    text: $numberOfServings
                  )
                  
                  CustomTextField(
                    icon: "text.badge.checkmark",
                    placeholder: NSLocalizedString("Unit", comment: "Portion unit field"),
                    text: $portionUnit
                  )
                }
                
                Text(NSLocalizedString("Adjust servings to calculate total nutrition intake", comment: "Servings explanation"))
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .padding(.bottom, 4)
              }
            }

            // 栄養素カード
            CardView(title: NSLocalizedString("Nutrition", comment: "Form section title")) {
              VStack(spacing: 16) {
                Text(NSLocalizedString("Values shown as: per serving → total based on servings", comment: "Nutrition explanation"))
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .padding(.bottom, 4)
                
                // 栄養素表示を共通化
                EditNutrientRow(
                  icon: "flame.fill",
                  iconColor: .orange,
                  label: NSLocalizedString("Calories", comment: "Nutrient label"),
                  value: calories,
                  totalValue: totalCalories,
                  unit: "kcal"
                )
                
                EditNutrientRow(
                  icon: "p.circle.fill",
                  iconColor: .blue,
                  label: NSLocalizedString("Protein", comment: "Nutrient label"),
                  value: protein,
                  totalValue: totalProtein,
                  unit: "g"
                )
                
                EditNutrientRow(
                  icon: "f.circle.fill",
                  iconColor: .yellow,
                  label: NSLocalizedString("Fat", comment: "Nutrient label"),
                  value: fat,
                  totalValue: totalFat,
                  unit: "g"
                )
                
                EditNutrientRow(
                  icon: "c.circle.fill",
                  iconColor: .green,
                  label: NSLocalizedString("Carbs", comment: "Nutrient label"),
                  value: carbohydrates,
                  totalValue: totalCarbs,
                  unit: "g"
                )
              }
            }
          }
          .padding()
        }
        .navigationTitle(NSLocalizedString("Edit Meal", comment: "Navigation title"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(action: {
              updateItem()
              dismiss()
            }) {
              Text(NSLocalizedString("Save", comment: "Button title"))
                .bold()
            }
            .disabled(
              brandName.isEmpty || productName.isEmpty || numberOfServings.isEmpty || Double(numberOfServings) == 0)
          }
        }
      }
    }
  }

  private func updateItem() {
    // サービング数のみ更新
    item.numberOfServings = servingsValue
    
    // FoodMasterが既に存在する場合はそのまま使用
    if foodMaster != nil {
      return
    }
    
    // 基本情報のみで検索
    let basicPredicate = #Predicate<FoodMaster> { food in
      food.brandName == brandName &&
      food.productName == productName &&
      food.portionUnit == portionUnit
    }

    let fetchDescriptor = FetchDescriptor<FoodMaster>(
      predicate: basicPredicate
    )

    // 基本情報で検索した結果を使用
    if let existingFoodMasters = try? modelContext.fetch(fetchDescriptor), !existingFoodMasters.isEmpty {
      // 既存のFoodMasterを使用
      item.foodMaster = existingFoodMasters.first
    } else {
      // 新しいFoodMasterを作成
      let newFoodMaster = FoodMaster(
        brandName: brandName,
        productName: productName,
        calories: Double(calories) ?? 0,
        carbohydrates: Double(carbohydrates) ?? 0,
        fat: Double(fat) ?? 0,
        protein: Double(protein) ?? 0,
        portionUnit: portionUnit,
        portion: 1.0  // 1単位あたりに正規化
      )
      modelContext.insert(newFoodMaster)
      item.foodMaster = newFoodMaster
    }
  }
}

// 栄養素表示用の共通コンポーネント
struct EditNutrientRow: View {
  let icon: String
  let iconColor: Color
  let label: String
  let value: String
  let totalValue: Double
  let unit: String
  
  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(iconColor)
        .frame(width: 24)
      
      Text(label)
        .foregroundColor(.primary)
      
      Spacer()
      
      Text(value.isEmpty ? "0" : value)
        .multilineTextAlignment(.trailing)
      
      Text(unit)
        .foregroundColor(.secondary)
        .frame(width: unit == "kcal" ? 40 : 20, alignment: .leading)
      
      Text("→")
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
      
      Text(String(format: "%.2f", totalValue))
        .foregroundColor(.primary)
      
      Text(unit)
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 12)
    .background(Color(UIColor.secondarySystemBackground))
    .cornerRadius(10)
  }
}
