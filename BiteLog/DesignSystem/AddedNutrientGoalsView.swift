import SwiftUI

/// あとから足した栄養素の期間の1日平均を、食事摂取基準の値と比べてリングで見せる。
///
/// 基準は習慣的な摂取量に対するものなので、選んだ期間の1日平均と比べる。
struct AddedNutrientGoalsView: View {
  let totals: NutrientTotals
  /// 平均の母数にする日数。記録の無い日も含める
  let dayCount: Int
  /// プロフィールの性別と年齢で引いた目標量。プロフィールが無ければ空
  let goals: [NutrientID: DietaryReferenceIntakes.Goal]
  /// 栄養素のカードを押したとき。説明を開く
  var onSelect: ((NutrientID) -> Void)? = nil

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

      // 食品表示に載るものと載りにくいものを分けて畳むと、全部を見るのに開く手間が増える。
      // 見出しで種類ごとに分かれているので、まとめて並べる
      grid(NutrientID.addedNutrients)
    }
  }

  private func grid(_ nutrients: [NutrientID]) -> some View {
    NutrientRingGrid(
      nutrients: nutrients, totals: totals, aggregation: .dailyAverage(days: dayCount), goals: goals,
      energy: energyPerDay, onSelect: onSelect)
  }
}
