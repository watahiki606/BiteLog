import SwiftUI

/// 食品の入力で、成分表の候補を出す欄。
///
/// 食品名で成分表を探し、候補を押すと食材と重さが決まる。選ばなくても保存できる。
/// 結んでおくと、ラベルに書かれていないミネラルやビタミンを成分表の値で補える。
struct CompositionLinkSection: View {
  let productName: String
  let defaultGrams: Double
  @Binding var components: [FoodComponent]

  @State private var candidates: [CompositionFoodDTO] = []
  @State private var gramsText: [String: String] = [:]

  private var query: String { CompositionLink.query(for: productName) }

  var body: some View {
    Section {
      if components.isEmpty {
        if candidates.isEmpty {
          Text(query.isEmpty
            ? NSLocalizedString("Enter the product name to see candidates.", comment: "Composition link hint")
            : NSLocalizedString("No match in the food composition table.", comment: "Composition link empty"))
            .foregroundStyle(.secondary)
        }
        ForEach(candidates) { food in
          Button {
            components = [FoodComponent(foodNumber: food.foodNumber, grams: defaultGrams, name: food.name)]
          } label: {
            HStack {
              Text(food.name).foregroundStyle(.primary).multilineTextAlignment(.leading)
              Spacer(minLength: 8)
              Image(systemName: "plus.circle").foregroundStyle(.tint)
            }
          }
          .accessibilityHint(NSLocalizedString("Links this food", comment: "Composition candidate hint"))
        }
      } else {
        ForEach($components) { $component in
          HStack {
            Text(component.name ?? component.foodNumber)
            Spacer(minLength: 8)
            TextField("100", value: $component.grams, format: .number)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .frame(width: 70)
            Text("g")
          }
        }
        .onDelete { components.remove(atOffsets: $0) }
        Button(NSLocalizedString("Remove the link", comment: "Composition link remove"), role: .destructive) {
          components = []
        }
      }
    } header: {
      Text(NSLocalizedString("Food Composition Table", comment: "Composition link section"))
    } footer: {
      Text(NSLocalizedString(
        "Nutrients not on the label are filled from the table. The weight is the edible part in one portion.",
        comment: "Composition link footer"))
    }
    .task(id: query) {
      // 打つたびに探さないよう、少し待ってから探す。名前を変えれば候補も変わる
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      candidates = query.isEmpty ? [] : ((try? await APIClient.shared.searchComposition(query: query, limit: 4)) ?? [])
    }
  }
}
