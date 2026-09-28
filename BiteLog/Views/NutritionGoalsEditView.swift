import SwiftUI

struct NutritionGoalsEditView: View {
  @EnvironmentObject private var nutritionGoalsManager: NutritionGoalsManager
  @Environment(\.dismiss) private var dismiss

  @State private var proteinText: String = ""
  @State private var fatText: String = ""
  @State private var netCarbsText: String = ""
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
            .monospacedDigit()
            .foregroundColor(.secondary)
        }

        Text(NSLocalizedString("Calories are automatically calculated", comment: "Calorie note"))
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section {
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
          text: $netCarbsText,
          unit: "g"
        )

        nutrientInputRow(
          label: NSLocalizedString("Dietary Fiber", comment: "Nutrient label"),
          text: $fiberText,
          unit: "g"
        )
      } header: {
        Text(NSLocalizedString("Macronutrients", comment: "Section header"))
      } footer: {
        // 0 や空欄を黙って捨てていると、入れたつもりの値が反映されない理由が分からない。
        if hasInvalidInput {
          Text(
            NSLocalizedString(
              "Enter a number greater than 0. Fields left as they are keep their current goal.",
              comment: "Goal validation message")
          )
          .foregroundStyle(.red)
        }
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
    let isInvalid = !text.wrappedValue.isEmpty && positiveValue(text.wrappedValue) == nil

    HStack {
      Text(label)
      Spacer()
      TextField("0", text: text)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .foregroundStyle(isInvalid ? Color.red : Color.primary)
        .frame(width: 80)
      Text(unit)
        .foregroundColor(.secondary)
    }
  }

  /// 0 より大きい数値として読めたときだけ値を返す。
  private func positiveValue(_ text: String) -> Double? {
    guard let value = Double(text), value > 0 else { return nil }
    return value
  }

  private var hasInvalidInput: Bool {
    [proteinText, fatText, netCarbsText, fiberText]
      .contains { !$0.isEmpty && positiveValue($0) == nil }
  }

  private var calculatedCalories: Double {
    let protein = Double(proteinText) ?? 0
    let fat = Double(fatText) ?? 0
    let netCarbs = Double(netCarbsText) ?? 0
    let fiber = Double(fiberText) ?? 0
    return protein * 4 + fat * 9 + netCarbs * 4 + fiber * 2
  }

  private func loadCurrentValues() {
    proteinText = formatValue(nutritionGoalsManager.targetProtein)
    fatText = formatValue(nutritionGoalsManager.targetFat)
    netCarbsText = formatValue(nutritionGoalsManager.targetNetCarbs)
    fiberText = formatValue(nutritionGoalsManager.targetFiber)
  }

  /// 4値をまとめて1回だけ保存する。
  /// 値ごとに保存すると PUT が並走し、最後に返った応答で他の値が巻き戻る。
  private func saveValues() {
    let manager = nutritionGoalsManager
    let protein = positiveValue(proteinText) ?? manager.targetProtein
    let fat = positiveValue(fatText) ?? manager.targetFat
    let netCarbs = positiveValue(netCarbsText) ?? manager.targetNetCarbs
    let fiber = positiveValue(fiberText) ?? manager.targetFiber

    guard protein != manager.targetProtein || fat != manager.targetFat
      || netCarbs != manager.targetNetCarbs || fiber != manager.targetFiber
    else { return }

    Task {
      await manager.update(protein: protein, fat: fat, netCarbs: netCarbs, fiber: fiber)
    }
  }

  private func resetToDefaults() {
    Task {
      await nutritionGoalsManager.resetToDefaults()
      loadCurrentValues()
    }
  }

  private func formatValue(_ value: Double) -> String {
    if value.truncatingRemainder(dividingBy: 1) == 0 {
      return String(Int(value))
    } else {
      return String(format: "%.1f", value)
    }
  }
}
