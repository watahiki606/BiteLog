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
            CardView(title: "基本情報") {
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

                  Picker("食事タイプ", selection: $mealType) {
                    ForEach(MealType.allCases, id: \.self) { type in
                      Text(type.rawValue).tag(type)
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

                  DatePicker("日時", selection: $date, displayedComponents: [.date])
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
            CardView(title: "栄養成分") {
              VStack(spacing: 16) {
                NutrientInputField(
                  icon: "flame.fill",
                  iconColor: .orange,
                  label: "カロリー",
                  value: $calories,
                  unit: "kcal"
                )

                NutrientInputField(
                  icon: "p.circle.fill",
                  iconColor: .blue,
                  label: "タンパク質",
                  value: $protein,
                  unit: "g"
                )

                NutrientInputField(
                  icon: "f.circle.fill",
                  iconColor: .yellow,
                  label: "脂質",
                  value: $fat,
                  unit: "g"
                )

                NutrientInputField(
                  icon: "c.circle.fill",
                  iconColor: .green,
                  label: "炭水化物",
                  value: $carbohydrates,
                  unit: "g"
                )

              }
            }
          }
          .padding()
        }
        .navigationTitle("食事を編集")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("キャンセル") { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(action: {
              updateItem()
              dismiss()
            }) {
              Text("保存")
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

// PFCパーセンテージラベル
struct PFCPercentageLabel: View {
  let value: Double
  let total: Double
  let color: Color
  let label: String

  var percentage: Int {
    total > 0 ? Int((value / total) * 100) : 0
  }

  var body: some View {
    VStack(spacing: 2) {
      Text(label)
        .font(.caption.bold())
        .foregroundColor(color)

      Text("\(percentage)%")
        .font(.footnote)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
    .background(color.opacity(0.1))
    .cornerRadius(8)
  }
}
