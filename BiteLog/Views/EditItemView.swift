import SwiftData
import SwiftUI

struct EditItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Bindable var item: LogItem

  @State private var brandName: String = ""
  @State private var productName: String = ""
  @State private var calories: String = ""
  @State private var carbohydrates: String = ""
  @State private var fat: String = ""
  @State private var protein: String = ""
  @State private var portionUnit: String = ""
  @State private var portion: String = ""  // String型のまま（UIで入力用）
  @State private var numberOfServings: String = "1"
  @State private var mealType: MealType = .breakfast
  @State private var date: Date = Date()
  @State private var foodMaster: FoodMaster?

  init(item: LogItem) {
    self.item = item
    _brandName = State(initialValue: item.brandName)
    _productName = State(initialValue: item.productName)
    _calories = State(initialValue: String(format: "%.0f", item.foodMaster?.calories ?? 0))
    _carbohydrates = State(
      initialValue: String(format: "%.0f", item.foodMaster?.carbohydrates ?? 0))
    _fat = State(initialValue: String(format: "%.0f", item.foodMaster?.fat ?? 0))
    _protein = State(initialValue: String(format: "%.0f", item.foodMaster?.protein ?? 0))
    _portionUnit = State(initialValue: item.foodMaster?.portionUnit ?? "")
    _portion = State(initialValue: String(format: "%.1f", item.foodMaster?.portion ?? 0))  // Double型からString型に変換
    _numberOfServings = State(initialValue: String(format: "%.1f", item.numberOfServings))
    _mealType = State(initialValue: item.mealType)
    _date = State(initialValue: item.timestamp)
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

                // Portion入力を数量と単位に分ける
                HStack {
                  CustomTextField(
                    icon: "number",
                    placeholder: NSLocalizedString("Amount", comment: "Portion amount field"),
                    text: $portion
                  )
                  .frame(width: 120)

                  CustomTextField(
                    icon: "text.badge.checkmark",
                    placeholder: NSLocalizedString("Unit", comment: "Portion unit field"),
                    text: $portionUnit
                  )
                }

                CustomTextField(
                  icon: "number",
                  placeholder: NSLocalizedString("Servings (e.g. 1.5)", comment: "Servings field"),
                  text: $numberOfServings
                )

                HStack {
                  Image(systemName: "fork.knife")
                    .foregroundColor(.blue)
                    .frame(width: 24)

                  Picker(
                    NSLocalizedString("Meal Type", comment: "Picker label"), selection: $mealType
                  ) {
                    ForEach(MealType.allCases, id: \.self) { type in
                      Text(type.localizedName).tag(type)
                    }
                  }
                  .pickerStyle(.menu)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)

                HStack {
                  Image(systemName: "calendar")
                    .foregroundColor(.blue)
                    .frame(width: 24)

                  DatePicker(
                    NSLocalizedString("Date", comment: "Date picker label"), selection: $date,
                    displayedComponents: [.date]
                  )
                  .labelsHidden()
                  .datePickerStyle(.compact)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
              }
            }

            // 栄養素カード
            CardView(title: NSLocalizedString("Nutrition", comment: "Form section title")) {
              VStack(spacing: 16) {
                NutrientInputField(
                  icon: "flame.fill",
                  iconColor: .orange,
                  label: NSLocalizedString("Calories", comment: "Nutrient label"),
                  value: $calories,
                  unit: "kcal"
                )

                NutrientInputField(
                  icon: "p.circle.fill",
                  iconColor: .blue,
                  label: NSLocalizedString("Protein", comment: "Nutrient label"),
                  value: $protein,
                  unit: "g"
                )

                NutrientInputField(
                  icon: "f.circle.fill",
                  iconColor: .yellow,
                  label: NSLocalizedString("Fat", comment: "Nutrient label"),
                  value: $fat,
                  unit: "g"
                )

                NutrientInputField(
                  icon: "c.circle.fill",
                  iconColor: .green,
                  label: NSLocalizedString("Carbs", comment: "Nutrient label"),
                  value: $carbohydrates,
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
              brandName.isEmpty || productName.isEmpty || portion.isEmpty || calories.isEmpty)
          }
        }
      }
    }
  }

  private func updateItem() {
    // FoodMaster を更新または取得
    var foodMasterItem: FoodMaster? = foodMaster
    if foodMasterItem == nil {
      let caloriesValue = Double(calories) ?? 0
      let carbohydratesValue = Double(carbohydrates) ?? 0
      let fatValue = Double(fat) ?? 0
      let proteinValue = Double(protein) ?? 0

      let fetchDescriptor = FetchDescriptor<FoodMaster>(
        predicate: #Predicate<FoodMaster> { food in
          food.brandName == brandName
            && food.productName == productName
            && food.calories == caloriesValue
            && food.carbohydrates == carbohydratesValue
            && food.fat == fatValue
            && food.protein == proteinValue
            && food.portionUnit == portionUnit
        }
      )

      if let existingFoodMaster = try? modelContext.fetch(fetchDescriptor),
        let firstFoodMaster = existingFoodMaster.first
      {
        foodMasterItem = firstFoodMaster
      } else {
        foodMasterItem = FoodMaster(
          brandName: brandName,
          productName: productName,
          calories: caloriesValue,
          carbohydrates: carbohydratesValue,
          fat: fatValue,
          protein: proteinValue,
          portionUnit: portionUnit,
          portion: Double(portion) ?? 0  // String型からDouble型に変換
        )
        modelContext.insert(foodMasterItem!)
      }
    }

    item.timestamp = date
    item.mealType = mealType
    item.numberOfServings = Double(numberOfServings) ?? 1.0
    item.foodMaster = foodMasterItem
  }
}
