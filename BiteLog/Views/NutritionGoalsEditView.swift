import SwiftUI

struct NutritionGoalsEditView: View {
  @EnvironmentObject private var nutritionGoalsManager: NutritionGoalsManager
  @Environment(\.dismiss) private var dismiss

  @State private var proteinText: String = ""
  @State private var fatText: String = ""
  @State private var sugarText: String = ""
  @State private var fiberText: String = ""

  var body: some View {
    Form {
      Section(
        header: Text(NSLocalizedString("Daily Nutrition Goals", comment: "Section header"))
      ) {
        // カロリー（自動計算、表示のみ）
        HStack {
          Text(NSLocalizedString("Calories", comment: "Nutrient label"))
          Spacer()
          Text("\(Int(calculatedCalories)) kcal")
            .foregroundColor(.secondary)
        }

        Text(NSLocalizedString("Calories are automatically calculated", comment: "Calorie note"))
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section(
        header: Text(NSLocalizedString("Macronutrients", comment: "Section header"))
      ) {
        nutrientInputRow(
          label: NSLocalizedString("Protein", comment: "Nutrient label"),
          text: $proteinText,
          unit: "g"
        )

        nutrientInputRow(
          label: NSLocalizedString("Fat", comment: "Nutrient label"),
          text: $fatText,
          unit: "g"
        )

        nutrientInputRow(
          label: NSLocalizedString("Sugar", comment: "Nutrient label"),
          text: $sugarText,
          unit: "g"
        )

        nutrientInputRow(
          label: NSLocalizedString("Dietary Fiber", comment: "Nutrient label"),
          text: $fiberText,
          unit: "g"
        )
      }

      Section {
        Button(action: resetToDefaults) {
          HStack {
            Spacer()
            Text(NSLocalizedString("Reset to Defaults", comment: "Button title"))
            Spacer()
          }
        }
      }
    }
    .navigationTitle(NSLocalizedString("Nutrition Goals", comment: "Navigation title"))
    .onAppear {
      loadCurrentValues()
    }
    .onDisappear {
      saveValues()
    }
  }

  @ViewBuilder
  private func nutrientInputRow(label: String, text: Binding<String>, unit: String) -> some View {
    HStack {
      Text(label)
      Spacer()
      TextField("0", text: text)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(width: 80)
      Text(unit)
        .foregroundColor(.secondary)
    }
  }

  private var calculatedCalories: Double {
    let protein = Double(proteinText) ?? 0
    let fat = Double(fatText) ?? 0
    let sugar = Double(sugarText) ?? 0
    let fiber = Double(fiberText) ?? 0
    return protein * 4 + fat * 9 + sugar * 4 + fiber * 2
  }

  private func loadCurrentValues() {
    proteinText = formatValue(nutritionGoalsManager.targetProtein)
    fatText = formatValue(nutritionGoalsManager.targetFat)
    sugarText = formatValue(nutritionGoalsManager.targetSugar)
    fiberText = formatValue(nutritionGoalsManager.targetFiber)
  }

  private func saveValues() {
    if let protein = Double(proteinText), protein > 0 {
      nutritionGoalsManager.targetProtein = protein
    }
    if let fat = Double(fatText), fat > 0 {
      nutritionGoalsManager.targetFat = fat
    }
    if let sugar = Double(sugarText), sugar > 0 {
      nutritionGoalsManager.targetSugar = sugar
    }
    if let fiber = Double(fiberText), fiber > 0 {
      nutritionGoalsManager.targetFiber = fiber
    }
  }

  private func resetToDefaults() {
    nutritionGoalsManager.resetToDefaults()
    loadCurrentValues()
  }

  private func formatValue(_ value: Double) -> String {
    if value.truncatingRemainder(dividingBy: 1) == 0 {
      return String(Int(value))
    } else {
      return String(format: "%.1f", value)
    }
  }
}
