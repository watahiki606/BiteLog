import SwiftData
import SwiftUI

struct AddItemView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var items: [Item]

  let preselectedMealType: MealType
  let mealType: MealType
  var selectedDate: Date

  @State private var brandName = ""
  @State private var productName = ""
  @State private var portion: String = ""
  @State private var calories: String = ""
  @State private var protein: String = ""
  @State private var fat: String = ""
  @State private var carbohydrates: String = ""
  @State private var showingPastItems = false
  @State private var date: Date

  init(preselectedMealType: MealType, selectedDate: Date) {
    self.preselectedMealType = preselectedMealType
    self.mealType = preselectedMealType
    self.selectedDate = selectedDate
    _date = State(initialValue: selectedDate)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("基本情報") {
          TextField("ブランド名", text: $brandName)
          TextField("商品名", text: $productName)
          TextField("量 (例: 1個, 100g)", text: $portion)
          Text(mealType.rawValue)
        }

        Section("栄養素") {
          TextField("カロリー (kcal)", text: $calories)
            .keyboardType(.decimalPad)
          TextField("タンパク質 (g)", text: $protein)
            .keyboardType(.decimalPad)
          TextField("脂質 (g)", text: $fat)
            .keyboardType(.decimalPad)
          TextField("炭水化物 (g)", text: $carbohydrates)
            .keyboardType(.decimalPad)
        }

        Section {
          Button("過去の食事から選択") {
            showingPastItems = true
          }
        }
      }
      .navigationTitle("食事を追加")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            addItem()
            dismiss()
          }
          .disabled(brandName.isEmpty || productName.isEmpty || portion.isEmpty || calories.isEmpty)
        }
      }
      .sheet(isPresented: $showingPastItems) {
        PastItemsView(selection: selectPastItem)
      }
    }
  }

  private func addItem() {
    let newItem = Item(
      brandName: brandName,
      productName: productName,
      portion: portion,
      calories: Double(calories) ?? 0,
      protein: Double(protein) ?? 0,
      fat: Double(fat) ?? 0,
      carbohydrates: Double(carbohydrates) ?? 0,
      mealType: mealType,
      timestamp: date
    )
    modelContext.insert(newItem)
  }

  private func selectPastItem(_ item: Item) {
    brandName = item.brandName
    productName = item.productName
    portion = item.portion
    calories = String(item.calories)
    protein = String(item.protein)
    fat = String(item.fat)
    carbohydrates = String(item.carbohydrates)
  }
}
