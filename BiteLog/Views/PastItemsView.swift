import SwiftData
import SwiftUI

struct PastItemsView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var searchText = ""
  @State private var items: [Item] = []
  @State private var currentOffset = 0
  @State private var hasMoreData = true

  let pageSize = 100
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

  func loadMoreItems() {
    var descriptor = FetchDescriptor<Item>(
      predicate: searchPredicate,
      sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
    )
    descriptor.fetchOffset = currentOffset
    descriptor.fetchLimit = pageSize

    if let newItems = try? modelContext.fetch(descriptor) {
      items.append(contentsOf: newItems)
      currentOffset += newItems.count
      hasMoreData = newItems.count == pageSize
    }
  }

  var body: some View {
    NavigationStack {
      List(items) { item in
        Button {
          selection(item)
          dismiss()
        } label: {
          ItemRow(item: item)
        }
        .onAppear {
          // リストの最後から2番目のアイテムが表示されたら追加読み込み
          if items.index(items.endIndex, offsetBy: -2) == items.firstIndex(of: item) {
            if hasMoreData {
              loadMoreItems()
            }
          }
        }
      }
      .searchable(text: $searchText, prompt: "食事を検索")
      .navigationTitle("過去の食事")
      .toolbar {
        Button("閉じる") { dismiss() }
      }
      .onAppear {
        // 初回表示時にデータを読み込む
        if items.isEmpty {
          loadMoreItems()
        }
      }
      .onChange(of: searchText) {
        // 検索テキスト変更時にリセット
        items = []
        currentOffset = 0
        hasMoreData = true
        loadMoreItems()
      }
    }
  }
}
