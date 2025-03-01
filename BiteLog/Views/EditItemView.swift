import SwiftData
import SwiftUI

struct EditItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Bindable var item: Item

  @State private var brandName: String
  @State private var productName: String
  @State private var portion: String
  @State private var numberOfServings: String
  @State private var calories: String
  @State private var protein: String
  @State private var fat: String
  @State private var carbohydrates: String
  @State private var mealType: MealType
  @State private var date: Date

  init(item: Item) {
    self.item = item
    _brandName = State(initialValue: item.brandName)
    _productName = State(initialValue: item.productName)
    _portion = State(initialValue: item.portion)
    _numberOfServings = State(initialValue: String(item.numberOfServings))
    _calories = State(initialValue: String(item.calories))
    _protein = State(initialValue: String(item.protein))
    _fat = State(initialValue: String(item.fat))
    _carbohydrates = State(initialValue: String(item.carbohydrates))
    _mealType = State(initialValue: item.mealType)
    _date = State(initialValue: item.timestamp)
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
                  placeholder: "ブランド名",
                  text: $brandName
                )

                CustomTextField(
                  icon: "cart.fill",
                  placeholder: "商品名",
                  text: $productName
                )

                CustomTextField(
                  icon: "scalemass.fill",
                  placeholder: "量 (例: 1個, 100g)",
                  text: $portion
                )

                CustomTextField(
                  icon: "number",
                  placeholder: "食事量 (例: 1.5)",
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
    item.brandName = brandName
    item.productName = productName
    item.portion = portion
    item.numberOfServings = Double(numberOfServings) ?? 1.0
    item.baseCalories = Double(calories) ?? 0
    item.baseProtein = Double(protein) ?? 0
    item.baseFat = Double(fat) ?? 0
    item.baseCarbohydrates = Double(carbohydrates) ?? 0
    item.mealType = mealType
    item.timestamp = date

  }
}
