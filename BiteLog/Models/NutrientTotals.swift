import Foundation

/// 何品かを足した合計と、栄養素ごとに値の分かっていた品数。
///
/// あとから足した栄養素は、値の分からない品がある。0 として足すと少なく見えるので、
/// 分かっている品だけを足し、「5品中3品の合計」と添えられるように品数を持つ。
struct NutrientTotals {
  let values: NutritionValues
  /// 合計に入れた品の数
  let itemCount: Int
  /// 栄養素ごとの、値の分かっていた品の数
  let knownCounts: [NutrientID: Int]

  init(values: NutritionValues, itemCount: Int, knownCounts: [NutrientID: Int]) {
    self.values = values
    self.itemCount = itemCount
    self.knownCounts = knownCounts
  }

  /// 1品ずつの値から作る
  init(items: [NutritionValues]) {
    var knownCounts: [NutrientID: Int] = [:]
    for id in NutrientID.allCases {
      knownCounts[id] = items.filter { $0.amounts[id] != nil }.count
    }
    self.init(values: items.reduce(.zero, +), itemCount: items.count, knownCounts: knownCounts)
  }

  /// その栄養素の値が分かっていた品の数
  func knownCount(_ id: NutrientID) -> Int {
    knownCounts[id] ?? (id.definition.core ? itemCount : 0)
  }

  /// 全品の値が分かっていれば true
  func isComplete(_ id: NutrientID) -> Bool { knownCount(id) == itemCount }

  static func + (lhs: NutrientTotals, rhs: NutrientTotals) -> NutrientTotals {
    var knownCounts: [NutrientID: Int] = [:]
    for id in NutrientID.allCases { knownCounts[id] = lhs.knownCount(id) + rhs.knownCount(id) }
    return NutrientTotals(
      values: lhs.values + rhs.values, itemCount: lhs.itemCount + rhs.itemCount, knownCounts: knownCounts)
  }

  static let empty = NutrientTotals(values: .zero, itemCount: 0, knownCounts: [:])
}
