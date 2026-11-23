import SwiftUI

/// 栄養成分と基準値の出典。成分表は出典の明記と、加工したことの明記を求めている
struct DataSourcesView: View {
  var body: some View {
    Form {
      Section {
        Text(NSLocalizedString("DataSources.Composition", comment: "Composition table attribution"))
        Link(
          NSLocalizedString("Ministry of Education: Standard Tables of Food Composition", comment: "Link title"),
          destination: URL(string: "https://www.mext.go.jp/a_menu/syokuhinseibun/mext_00001.html")!)
      } header: {
        Text(NSLocalizedString("Food Nutrients", comment: "Data sources section"))
      }
      Section {
        Text(NSLocalizedString("DataSources.DRI", comment: "Dietary reference intakes attribution"))
        Link(
          NSLocalizedString("Ministry of Health: Dietary Reference Intakes for Japanese 2025", comment: "Link title"),
          destination: URL(string: "https://www.mhlw.go.jp/stf/newpage_44138.html")!)
      } header: {
        Text(NSLocalizedString("Reference Values", comment: "Data sources section"))
      }
      Section {
        Text(NSLocalizedString("DataSources.Score", comment: "Diet quality score method"))
        Link(
          NSLocalizedString("Murakami K, et al. Nutrients 2019", comment: "Link title"),
          destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/31640242/")!)
      } header: {
        Text(NSLocalizedString("Score Method", comment: "Data sources section"))
      }
    }
    .navigationTitle(NSLocalizedString("Data Sources", comment: "Data sources"))
  }
}
