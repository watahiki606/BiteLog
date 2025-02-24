import SwiftData
import SwiftUI

struct PastItemsView: View {
  @Environment(\.dismiss) var dismiss
  @Query private var items: [Item]
  @State private var searchText = ""

  var selection: (Item) -> Void

  var filteredItems: [Item] {
    if searchText.isEmpty {
      return Array(Set(items)).sorted { $0.timestamp > $1.timestamp }
    }
    return items.filter {
      $0.brandName.localizedCaseInsensitiveContains(searchText)
        || $0.productName.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    NavigationStack {
      List(filteredItems) { item in
        Button {
          selection(item)
          dismiss()
        } label: {
          ItemRow(item: item)
        }
      }
      .searchable(text: $searchText, prompt: "食事を検索")
      .navigationTitle("過去の食事")
      .toolbar {
        Button("閉じる") { dismiss() }
      }
    }
  }
}
