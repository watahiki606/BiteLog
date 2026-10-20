import SwiftUI

/// 写真解析で入れた店名に、登録済みの食品が見つかったときの候補。
///
/// 選べば Web で調べずに記録できるので、費用も待ち時間もかからない。
/// 量や中身が違う項目もあり得るので、1件に決めずにユーザーに選んでもらう。
struct MenuMatchesView: View {
  @Environment(\.dismiss) var dismiss

  let menuName: String
  let matches: [FoodMasterDTO]
  var onPick: (FoodMasterDTO) -> Void
  var onLookUpOfficial: () -> Void

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(matches) { item in
            Button { onPick(item) } label: {
              FoodRow(
                title: FoodRow.displayName(brand: item.brandName, product: item.productName),
                subtitle: FoodRow.amountText(item.servingsToLog, unit: item.portionUnit),
                values: NutritionSnapshot.from(item).scaled(by: item.servingsToLog)
              )
            }
            .buttonStyle(.plain)
          }
        } header: {
          Text(
            String(
              format: NSLocalizedString("Registered foods matching \"%@\"", comment: "Menu matches header"),
              menuName))
        } footer: {
          Text(NSLocalizedString("Pick one to log it as is.", comment: "Menu matches footer"))
        }

        Section {
          Button {
            onLookUpOfficial()
          } label: {
            Label(
              NSLocalizedString("None of these. Look up official nutrition facts", comment: "Button title"),
              systemImage: "globe")
          }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle(NSLocalizedString("Found in Registered Foods", comment: "Navigation title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Button title")) { dismiss() }
        }
      }
    }
  }
}
