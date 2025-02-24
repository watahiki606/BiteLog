import SwiftData
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var items: [Item]

  @State private var showingAddItem = false

  var body: some View {
    NavigationStack {
      List {
        ForEach(items) { item in
          VStack(alignment: .leading) {
            Text(item.name)
              .font(.headline)
            Text("\(item.calories, specifier: "%.0f") kcal")
              .font(.subheadline)
            Text(
              "タンパク質: \(item.protein, specifier: "%.1f")g, 脂質: \(item.fat, specifier: "%.1f")g, 炭水化物: \(item.carbohydrates, specifier: "%.1f")g"
            )
            .font(.caption)
            Text(item.mealType.rawValue)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .onDelete(perform: deleteItems)
      }
      .navigationTitle("食事記録")
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: {
            showingAddItem = true
          }) {
            Label("追加", systemImage: "plus")
          }
        }
      }
      .sheet(isPresented: $showingAddItem) {
        AddItemView()
      }
    }
  }

  private func deleteItems(offsets: IndexSet) {
    withAnimation {
      for index in offsets {
        modelContext.delete(items[index])
      }
    }
  }
}

struct AddItemView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext

  @State private var name = ""
  @State private var calories = ""
  @State private var protein = ""
  @State private var fat = ""
  @State private var carbohydrates = ""
  @State private var mealType: MealType = .breakfast

  var body: some View {
    NavigationStack {
      Form {
        Section("基本情報") {
          TextField("食事名", text: $name)
          Picker("食事タイプ", selection: $mealType) {
            ForEach(MealType.allCases, id: \.self) { type in
              Text(type.rawValue).tag(type)
            }
          }
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
      }
      .navigationTitle("食事を追加")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            addItem()
            dismiss()
          }
          .disabled(name.isEmpty || calories.isEmpty)
        }
      }
    }
  }

  private func addItem() {
    let newItem = Item(
      name: name,
      calories: Double(calories) ?? 0,
      protein: Double(protein) ?? 0,
      fat: Double(fat) ?? 0,
      carbohydrates: Double(carbohydrates) ?? 0,
      mealType: mealType,
      timestamp: Date()
    )
    modelContext.insert(newItem)
  }
}

#Preview {
  ContentView()
    .modelContainer(for: Item.self, inMemory: true)
}
