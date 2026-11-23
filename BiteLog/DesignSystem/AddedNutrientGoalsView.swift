import SwiftUI

/// あとから足した栄養素の期間の1日平均を、食事摂取基準の値と比べてリングで見せる。
///
/// 基準は習慣的な摂取量に対するものなので、選んだ期間の1日平均と比べる。
/// 値の分からない品があると平均は少なく出るので、何品ぶんの値から出したかを添える。
struct AddedNutrientGoalsView: View {
  let totals: NutrientTotals
  /// 平均の母数にする日数。記録の無い日も含める
  let dayCount: Int
  /// プロフィールの性別と年齢で引いた目標量。プロフィールが無ければ空
  let goals: [NutrientID: DietaryReferenceIntakes.Goal]

  /// 飽和脂肪酸の目標量はエネルギーに占める割合なので、期間に食べたエネルギーの1日平均と比べる
  private var energyPerDay: Double { totals.values.calories / Double(max(dayCount, 1)) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if goals.isEmpty {
        Text(NSLocalizedString(
          "Add your sex and birth date in Profile to compare with the dietary goals.",
          comment: "Hint when no profile for dietary goals"))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      grid(NutrientID.labelNutrients)

      // 詳しい栄養素は15あり、並べると画面が長くなりすぎる。畳んでおく
      DisclosureGroup {
        grid(NutrientID.detailNutrients)
          .padding(.top, 12)
      } label: {
        // 1日の合計の「その他の栄養素」と同じく、補助的な操作なので灰色に落とす
        Text(NSLocalizedString("Detailed Nutrients", comment: "Disclosure of nutrients filled from the composition table"))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .tint(.secondary)
    }
  }

  private func grid(_ nutrients: [NutrientID]) -> some View {
    NutrientRingGrid(
      nutrients: nutrients, totals: totals, aggregation: .dailyAverage(days: dayCount), goals: goals,
      energy: energyPerDay)
  }
}
