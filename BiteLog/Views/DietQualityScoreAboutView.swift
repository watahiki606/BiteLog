import SwiftUI

/// 食事の質のスコアの根拠と計算のしかた。統計のスコアのカードから開く。
///
/// 書くのは、出典で確かめられることと、アプリが実際にしている計算だけにする。
/// 死亡率との関連は書かない。疾病のリスクを個人の結果として出すことに近づくため。
struct DietQualityScoreAboutView: View {
  var body: some View {
    Form {
      section("DietQualityScore.About.What.Title", paragraphs: ["DietQualityScore.About.What.Body"])
      section(
        "DietQualityScore.About.Study.Title",
        paragraphs: [
          "DietQualityScore.About.Study.Origin", "DietQualityScore.About.Study.Validity",
          "DietQualityScore.About.Study.Survey",
        ])
      section(
        "DietQualityScore.About.Reference.Title",
        paragraphs: ["DietQualityScore.About.Reference.Body", "DietQualityScore.About.Reference.Values"])
      Section {
        ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, key in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(index + 1)")
              .font(.subheadline.weight(.semibold))
              .monospacedDigit()
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
            paragraph(key)
          }
        }
        paragraph("DietQualityScore.About.Steps.Conditions")
      } header: {
        Text(NSLocalizedString("DietQualityScore.About.Steps.Title", comment: "Diet quality score explanation"))
      }
      section(
        "DietQualityScore.About.Differences.Title",
        paragraphs: [
          "DietQualityScore.About.Differences.AddedSugar", "DietQualityScore.About.Differences.Edition",
          "DietQualityScore.About.Differences.Unknown",
        ])
      section("DietQualityScore.About.Care.Title", paragraphs: ["DietQualityScore.Note.Consult"])
      Section {
        ForEach(Self.sources, id: \.url) { source in
          Link(NSLocalizedString(source.title, comment: "Diet quality score source"), destination: source.url)
        }
      } header: {
        Text(NSLocalizedString("DietQualityScore.About.Sources.Title", comment: "Diet quality score explanation"))
      }
    }
    .navigationTitle(NSLocalizedString("About the Diet Quality Score", comment: "Diet quality score explanation"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private static let steps = [
    "DietQualityScore.About.Steps.Sum", "DietQualityScore.About.Steps.Adjust",
    "DietQualityScore.About.Steps.Encouraged", "DietQualityScore.About.Steps.Limited",
    "DietQualityScore.About.Steps.Total",
  ]

  private static let sources: [(title: String, url: URL)] = [
    ("Murakami K, et al. Nutrients 2019", URL(string: "https://pubmed.ncbi.nlm.nih.gov/31640242/")!),
    ("Murakami K, et al. PLoS One 2020", URL(string: "https://pubmed.ncbi.nlm.nih.gov/31999772/")!),
    ("Fulgoni VL 3rd, et al. J Nutr 2009", URL(string: "https://pubmed.ncbi.nlm.nih.gov/19549759/")!),
    ("Ministry of Health: Dietary Reference Intakes for Japanese 2025", URL(string: "https://www.mhlw.go.jp/stf/newpage_44138.html")!),
    ("Ministry of Education: Standard Tables of Food Composition", URL(string: "https://www.mext.go.jp/a_menu/syokuhinseibun/mext_00001.html")!),
  ]

  private func section(_ title: String, paragraphs: [String]) -> some View {
    Section {
      ForEach(paragraphs, id: \.self) { paragraph($0) }
    } header: {
      Text(NSLocalizedString(title, comment: "Diet quality score explanation"))
    }
  }

  private func paragraph(_ key: String) -> some View {
    Text(NSLocalizedString(key, comment: "Diet quality score explanation"))
      .font(.subheadline)
      .fixedSize(horizontal: false, vertical: true)
  }
}

#Preview {
  NavigationStack { DietQualityScoreAboutView() }
}
