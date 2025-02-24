import SwiftData
import SwiftUI

struct EditItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Bindable var item: Item

  @State private var brandName: String
  @State private var productName: String
  @State private var portion: String
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
    _calories = State(initialValue: String(item.calories))
    _protein = State(initialValue: String(item.protein))
    _fat = State(initialValue: String(item.fat))
    _carbohydrates = State(initialValue: String(item.carbohydrates))
    _mealType = State(initialValue: item.mealType)
    _date = State(initialValue: item.timestamp)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("基本情報") {
          TextField("ブランド名", text: $brandName)
          TextField("商品名", text: $productName)
          TextField("量 (例: 1個, 100g)", text: $portion)
          Picker("食事タイプ", selection: $mealType) {
            ForEach(MealType.allCases, id: \.self) { type in
              Text(type.rawValue).tag(type)
            }
          }
          DatePicker("日時", selection: $date, displayedComponents: [.date])
        }

        Section("栄養素") {
          HStack {
            TextField("カロリー", text: $calories)
              .keyboardType(.decimalPad)
            Text("kcal")
          }
          HStack {
            TextField("タンパク質", text: $protein)
              .keyboardType(.decimalPad)
            Text("g")
          }
          HStack {
            TextField("脂質", text: $fat)
              .keyboardType(.decimalPad)
            Text("g")
          }
          HStack {
            TextField("炭水化物", text: $carbohydrates)
              .keyboardType(.decimalPad)
            Text("g")
          }
        }
      }
      .navigationTitle("食事を編集")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            updateItem()
            dismiss()
          }
          .disabled(brandName.isEmpty || productName.isEmpty || portion.isEmpty || calories.isEmpty)
        }
      }
    }
  }

  private func updateItem() {
    item.brandName = brandName
    item.productName = productName
    item.portion = portion
    item.calories = Double(calories) ?? 0
    item.protein = Double(protein) ?? 0
    item.fat = Double(fat) ?? 0
    item.carbohydrates = Double(carbohydrates) ?? 0
    item.mealType = mealType
    item.timestamp = date
  }
}
