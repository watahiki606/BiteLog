import Foundation

/// 何品かを足した合計と、栄養素ごとに値の分かっていた品の数とカロリー。
///
/// あとから足した栄養素は、値の分からない品がある。0 として足すと少なく見えるので、
/// 分かっている品だけを足す。どの品も分からなければ「不明」と出す。
/// 食事の質スコアは、分かっている品の量をその品のカロリーで割って換算するので、そのカロリーも持つ。
struct NutrientTotals {
  let values: NutritionValues
  /// 合計に入れた品の数
  let itemCount: Int
  /// 栄養素ごとの、値の分かっていた品の数
  let knownCounts: [NutrientID: Int]
  /// 栄養素ごとの、値の分かっていた品のカロリーの合計
  private let knownEnergies: [NutrientID: Double]

  /// サーバーが日と食事の区分ごとにまとめた合計から作る。
  ///
  /// 区分の中のどの品の値が分かっていたかは届かないので、分かっていた品のカロリーは品数の割合で見積もる。
  /// 区分の全品が分かっているときと、1品も分からないときは正確になる。
  /// サーバーが栄養素ごとに、分かっていた品のカロリーの合計も返せば、混ざった区分も正確にできる
  init(values: NutritionValues, itemCount: Int, knownCounts: [NutrientID: Int]) {
    var energies: [NutrientID: Double] = [:]
    for (id, count) in knownCounts where itemCount > 0 {
      energies[id] = values.calories * Double(count) / Double(itemCount)
    }
    self.init(values: values, itemCount: itemCount, knownCounts: knownCounts, knownEnergies: energies)
  }

  /// 1品ずつの値から作る。分かっていた品のカロリーはそのまま足す
  init(items: [NutritionValues]) {
    var knownCounts: [NutrientID: Int] = [:]
    var knownEnergies: [NutrientID: Double] = [:]
    for id in NutrientID.allCases {
      let known = items.filter { $0.amounts[id] != nil }
      knownCounts[id] = known.count
      knownEnergies[id] = known.map(\.calories).reduce(0, +)
    }
    self.init(
      values: items.reduce(.zero, +), itemCount: items.count, knownCounts: knownCounts, knownEnergies: knownEnergies)
  }

  private init(
    values: NutritionValues, itemCount: Int, knownCounts: [NutrientID: Int], knownEnergies: [NutrientID: Double]
  ) {
    self.values = values
    self.itemCount = itemCount
    self.knownCounts = knownCounts
    self.knownEnergies = knownEnergies
  }

  /// その栄養素の値が分かっていた品の数
  func knownCount(_ id: NutrientID) -> Int {
    knownCounts[id] ?? (id.definition.core ? itemCount : 0)
  }

  /// その栄養素の値が分かっていた品のカロリーの合計。最初の5項目は全品が分かっているとみなす
  func knownEnergy(_ id: NutrientID) -> Double {
    knownEnergies[id] ?? (id.definition.core ? values.calories : 0)
  }

  /// 値の分からない品が1つでもある栄養素か
  func hasUnknownItems(_ id: NutrientID) -> Bool {
    knownCount(id) < itemCount
  }

  static func + (lhs: NutrientTotals, rhs: NutrientTotals) -> NutrientTotals {
    var knownCounts: [NutrientID: Int] = [:]
    var knownEnergies: [NutrientID: Double] = [:]
    for id in NutrientID.allCases {
      knownCounts[id] = lhs.knownCount(id) + rhs.knownCount(id)
      knownEnergies[id] = lhs.knownEnergy(id) + rhs.knownEnergy(id)
    }
    return NutrientTotals(
      values: lhs.values + rhs.values, itemCount: lhs.itemCount + rhs.itemCount, knownCounts: knownCounts,
      knownEnergies: knownEnergies)
  }

  static let empty = NutrientTotals(values: .zero, itemCount: 0, knownCounts: [:])
}
