import SwiftUI

/// あとから足した栄養素の期間の1日平均を、食事摂取基準の値と並べる。
///
/// 値の分からない品があると平均は少なく出る。少なく出たまま「目標を守れている」とは書けないので、
/// 良し悪しは書かず、何品ぶんの値から出したかを添えるだけにする。「不足」とも書かない。
/// 基準は習慣的な摂取量に対するものなので、選んだ期間の1日平均と比べる。
struct AddedNutrientGoalsView: View {
  let totals: NutrientTotals
  /// 平均の母数にする日数。記録の無い日も含める
  let dayCount: Int
  /// プロフィールの性別と年齢で引いた目標量。プロフィールが無ければ空
  let goals: [NutrientID: DietaryReferenceIntakes.Goal]


  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(NutrientID.labelNutrients, id: \.self) { id in
        row(id)
      }
      // 詳しい栄養素は15あり、並べるとカードが長くなりすぎる。畳んでおく
      DisclosureGroup {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(NutrientID.detailNutrients, id: \.self) { id in
            row(id)
          }
        }
        .padding(.top, 8)
      } label: {
        // 1日の合計の「その他の栄養素」と同じく、補助的な操作なので灰色に落とす
        Text(NSLocalizedString("Detailed Nutrients", comment: "Disclosure of nutrients filled from the composition table"))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .tint(.secondary)
      if goals.isEmpty {
        Text(NSLocalizedString(
          "Add your sex and birth date in Profile to compare with the dietary goals.",
          comment: "Hint when no profile for dietary goals"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func row(_ id: NutrientID) -> some View {
    let known = totals.knownCount(id)
    let name = Label {
      Text(id.localizedName)
    } icon: {
      NutrientBadge(nutrient: id, size: 24)
    }
    let value = Text(known > 0 ? averageText(id) : NSLocalizedString("Unknown", comment: "Unknown nutrient value"))
      .monospacedDigit()
      .fontWeight(.medium)
    return VStack(alignment: .leading, spacing: 4) {
      // 大きな文字で名前と値を横に並べると、どちらも語の途中で折れる。縦に積む
      if dynamicTypeSize.isAccessibilitySize {
        // 親が提案した高さに縮められて「Salt equival…」と切れるので、要る行数ぶんの高さを取る
        name.fixedSize(horizontal: false, vertical: true)
        value
      } else {
        HStack(alignment: .firstTextBaseline) {
          name
          Spacer(minLength: 8)
          value
        }
      }
      if let goal = goals[id] {
        Text(goalText(goal, perDay: known > 0 ? perDay(id) : nil))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if known > 0 && !totals.isComplete(id) {
        Text(String(
          format: NSLocalizedString("From %1$d of %2$d items", comment: "Partial average of a nutrient"),
          known, totals.itemCount))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .font(.subheadline)
    .accessibilityElement(children: .combine)
  }

  private func averageText(_ id: NutrientID) -> String {
    let total = totals.values.amounts[id] ?? 0
    // 飽和脂肪酸の目標量はエネルギーに占める割合なので、比べられる形で出す
    if goals[id]?.comparison == .atMostPercentOfEnergy, totals.values.calories > 0 {
      let percent = total * 9 / totals.values.calories * 100
      return String(
        format: NSLocalizedString("%@%% of energy", comment: "Share of energy"),
        NutritionFormatter.formatNutrition((percent * 10).rounded() / 10))
    }
    return String(
      format: NSLocalizedString("%@ per day", comment: "Average per day"), "\(id.format(perDay(id)))\(id.unit)")
  }

  private func perDay(_ id: NutrientID) -> Double {
    (totals.values.amounts[id] ?? 0) / Double(max(dayCount, 1))
  }

  private func goalText(_ goal: DietaryReferenceIntakes.Goal, perDay: Double?) -> String {
    let value = NutritionFormatter.formatNutrition(goal.value)
    let unit = goal.nutrient.unit
    switch goal.comparison {
    case .atLeast:
      return String(format: NSLocalizedString("Goal: %@ or more", comment: "Dietary goal"), "\(value)\(unit)")
    case .reference:
      return Self.referenceText(goal, perDay: perDay)
    case .lessThan:
      return String(
        format: NSLocalizedString("Goal: less than %@", comment: "Dietary goal"), "\(value)\(goal.nutrient.unit)")
    case .atMostPercentOfEnergy:
      return String(
        format: NSLocalizedString("Goal: %@%% of energy or less", comment: "Dietary goal"), value)
    }
  }

  /// 推奨量は割合を添え、目安量は値だけを並べる。目安量を下回っても不足とは判定できないため
  static func referenceText(_ goal: DietaryReferenceIntakes.Goal, perDay: Double?) -> String {
    let unit = goal.nutrient.unit
    let value = "\(NutritionFormatter.formatNutrition(goal.value))\(unit)"
    if goal.indicator == .adequateIntake {
      return String(format: NSLocalizedString("Adequate intake %@", comment: "Dietary reference"), value)
    }
    if let alt = goal.menstruatingValue {
      return String(
        format: NSLocalizedString("Recommended %1$@, %2$@ if menstruating", comment: "Iron reference for women"),
        value, "\(NutritionFormatter.formatNutrition(alt))\(unit)")
    }
    if let perDay, goal.value > 0 {
      return String(
        format: NSLocalizedString("Recommended %1$@: %2$d%%", comment: "Share of the recommended amount"),
        value, Int((perDay / goal.value * 100).rounded()))
    }
    return String(format: NSLocalizedString("Recommended %@", comment: "Dietary reference"), value)
  }
}
