import SwiftData
import SwiftUI

struct PastItemsView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var searchText = ""

  var selection: (Item) -> Void

  var searchPredicate: Predicate<Item> {
    if searchText.isEmpty {
      return #Predicate<Item> { _ in true }
    }
    return #Predicate<Item> { item in
      item.brandName.localizedStandardContains(searchText)
        || item.productName.localizedStandardContains(searchText)
    }
  }

  var filteredItems: [Item] {
    var descriptor = FetchDescriptor<Item>(
      predicate: searchPredicate,
      sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
    )
    descriptor.fetchLimit = 100
    return (try? modelContext.fetch(descriptor)) ?? []
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
