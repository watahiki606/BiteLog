import SwiftUI

/// 食事の質のスコアを、参考の点として栄養素ごとの割合と並べる。
///
/// 医療的な判断に見えないよう、点にも割合にも色で良し悪しを付けず、「不足」「良い」とも書かない。
/// 死亡リスクも書かない。疾病のリスクを個人の結果として出すことになるため。
struct DietQualityScoreView: View {
  let result: DietQualityScore.Result

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      switch result {
      case .score(let score):
        scoreView(score)
      case .unavailable(let shortfalls):
        VStack(alignment: .leading, spacing: 6) {
          ForEach(Array(shortfalls.enumerated()), id: \.offset) { _, shortfall in
            Text(Self.text(shortfall))
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
      notes
    }
  }

  private func scoreView(_ score: DietQualityScore) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text("\(Int(score.score.rounded()))")
          .font(.largeTitle.weight(.semibold))
        Text("/ \(Int(DietQualityScore.maximum))")
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      .monospacedDigit()
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        String(
          format: NSLocalizedString("%1$d of %2$d points", comment: "Diet quality score for VoiceOver"),
          Int(score.score.rounded()), Int(DietQualityScore.maximum)))

      ForEach(score.components, id: \.nutrient) { component in
        row(component)
      }
    }
  }

  private func row(_ component: DietQualityScore.Component) -> some View {
    let name = Label {
      Text(component.nutrient.localizedName)
    } icon: {
      NutrientBadge(nutrient: component.nutrient, size: 24)
    }
    let value = Text(Self.percentText(component))
      .monospacedDigit()
      .fontWeight(.medium)
    return Group {
      // 大きな文字で名前と値を横に並べると、どちらも語の途中で折れる。縦に積む
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          // 親が提案した高さに縮められて「Salt equival…」と切れるので、要る行数ぶんの高さを取る
          name.fixedSize(horizontal: false, vertical: true)
          value.fixedSize(horizontal: false, vertical: true)
        }
      } else {
        HStack(alignment: .firstTextBaseline) {
          name
          Spacer(minLength: 8)
          value
        }
      }
    }
    .font(.subheadline)
    .accessibilityElement(children: .combine)
  }

  /// 推奨する栄養素は点に入る割合を出すので、100%で打ち切る。制限する栄養素は目標量に対する割合をそのまま出す
  static func percentText(_ component: DietQualityScore.Component) -> String {
    let percent = Int(component.percentOfReference.rounded())
    switch component.role {
    case .encouraged:
      return "\(min(100, percent))%"
    case .limited:
      return String(format: NSLocalizedString("%d%% of the goal", comment: "Share of the dietary goal"), percent)
    }
  }

  static func text(_ shortfall: DietQualityScore.Shortfall) -> String {
    switch shortfall {
    case .noProfile:
      return NSLocalizedString(
        "Add your sex and birth date in Profile to see the score.", comment: "Diet quality score unavailable")
    case .notAdult:
      return NSLocalizedString("The score is for people aged 18 and over.", comment: "Diet quality score unavailable")
    case .periodTooShort:
      return NSLocalizedString(
        "Choose a period of 7 days or more to see the score.", comment: "Diet quality score unavailable")
    case .tooFewLoggedDays:
      return NSLocalizedString(
        "The score needs meals logged on 5 days or more in the period.", comment: "Diet quality score unavailable")
    case .manyUnknownItems(let ids):
      return String(
        format: NSLocalizedString(
          "Too many items have unknown values for %@.", comment: "Diet quality score unavailable"),
        ids.map(\.localizedName).joined(separator: NSLocalizedString("ListSeparator", comment: "Separator between items in a list")))
    case .noEnergy:
      return NSLocalizedString("No calories are logged in this period.", comment: "Diet quality score unavailable")
    }
  }

  private var notes: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(NSLocalizedString("DietQualityScore.Note.Reference", comment: "Diet quality score note"))
      Text(NSLocalizedString("DietQualityScore.Note.AddedSugar", comment: "Diet quality score note"))
      Text(NSLocalizedString("DietQualityScore.Note.Consult", comment: "Diet quality score note"))
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
  }
}
