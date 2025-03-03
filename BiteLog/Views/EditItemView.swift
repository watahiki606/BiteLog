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
              brandName.isEmpty || productName.isEmpty || numberOfServings.isEmpty || calories.isEmpty)
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

      // 基本情報のみで検索
      let basicPredicate = #Predicate<FoodMaster> { food in
        food.brandName == brandName &&
        food.productName == productName &&
        food.portionUnit == portionUnit
      }

      let fetchDescriptor = FetchDescriptor<FoodMaster>(
        predicate: basicPredicate
      )

      // 基本情報で検索した結果から栄養価が一致するものを探す
      if let existingFoodMasters = try? modelContext.fetch(fetchDescriptor) {
        var matchedFoodMaster: FoodMaster? = nil
        
        // 取得した結果から栄養価が一致するものを探す
        for candidate in existingFoodMasters {
          if abs(candidate.calories - caloriesValue) < 0.1 &&
             abs(candidate.carbohydrates - carbohydratesValue) < 0.1 &&
             abs(candidate.fat - fatValue) < 0.1 &&
             abs(candidate.protein - proteinValue) < 0.1 {
            matchedFoodMaster = candidate
            break
          }
        }
        
        if let firstFoodMaster = matchedFoodMaster {
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
            portion: 1.0  // 1単位あたりに正規化
          )
          modelContext.insert(foodMasterItem!)
        }
      } else {
        foodMasterItem = FoodMaster(
          brandName: brandName,
          productName: productName,
          calories: caloriesValue,
          carbohydrates: carbohydratesValue,
          fat: fatValue,
          protein: proteinValue,
          portionUnit: portionUnit,
          portion: 1.0  // 1単位あたりに正規化
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
