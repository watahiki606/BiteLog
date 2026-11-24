import SwiftUI

/// 栄養素1つの説明。統計で栄養素を押すとシートで開く。
///
/// 何のための栄養素か、足りないとき、とりすぎたとき、多く含む食品の例、出典の順に並べる。
/// 出典に書かれていない欄は出さない。病気を見分けたり治したりする言い方はしない。
struct NutrientInfoView: View {
  let info: NutrientInfo

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack(spacing: 12) {
            NutrientBadge(nutrient: info.nutrient, size: 40)
            Text(info.nutrient.localizedName)
              .font(.title2.weight(.bold))
              .fixedSize(horizontal: false, vertical: true)
          }
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(.isHeader)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        }

        field(NSLocalizedString("What it does", comment: "Nutrient info section"), info.role)
        field(NSLocalizedString("When you get too little", comment: "Nutrient info section"), info.shortage)
        field(NSLocalizedString("When you get too much", comment: "Nutrient info section"), info.excess)
        field(NSLocalizedString("Foods rich in it", comment: "Nutrient info section"), info.foods)

        Section {
          ForEach(info.sources, id: \.self) { source in
            Link(destination: source.url) {
              Text(source.title)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        } header: {
          Text(NSLocalizedString("Sources", comment: "Nutrient info section"))
        } footer: {
          Text(NSLocalizedString(
            "General information about the nutrient, not advice for your own health. Ask a doctor or dietitian about your own case.",
            comment: "Nutrient info footer"))
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Close", comment: "Close")) { dismiss() }
        }
      }
    }
  }

  @ViewBuilder
  private func field(_ title: String, _ text: String?) -> some View {
    if let text {
      Section {
        Text(text)
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
      } header: {
        Text(title)
      }
    }
  }
}

#Preview {
  NutrientInfoView(info: NutrientInfo(.vitaminD))
}
