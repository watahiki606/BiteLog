import Foundation

/// 栄養素の値の集まり。キーが無いことを「不明」とし、0 とは区別する。
///
/// JSON では今までと同じ平らなキーで読み書きする。食品やスナップショットの本文に
/// `calories` などが他の項目と並んで入るので、同じ階層から栄養素のキーだけを拾う。
struct NutrientAmounts: Equatable, Hashable, Sendable {
  private(set) var values: [NutrientID: Double]

  init(_ values: [NutrientID: Double] = [:]) {
    self.values = values
  }

  /// 最初からある5項目をまとめて作る
  init(calories: Double, protein: Double, fat: Double, netCarbs: Double, dietaryFiber: Double) {
    self.init([
      .calories: calories, .protein: protein, .fat: fat, .netCarbs: netCarbs, .dietaryFiber: dietaryFiber,
    ])
  }

  /// 値が分からなければ nil
  subscript(id: NutrientID) -> Double? {
    get { values[id] }
    set { values[id] = newValue }
  }

  /// 最初からある5項目の値。必ず持つ項目なので、無ければ 0 として扱う
  func core(_ id: NutrientID) -> Double { values[id] ?? 0 }

  /// どの値も同じ割合で増減させる。不明な栄養素は不明のまま
  func scaled(by ratio: Double) -> NutrientAmounts {
    NutrientAmounts(values.mapValues { $0 * ratio })
  }
}

extension NutrientAmounts {
  private struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ id: NutrientID) { stringValue = id.rawValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  /// 本文と同じ階層から栄養素のキーを読む。
  /// 最初からある5項目は必ず入っている。欠けていれば壊れた本文として扱う。それ以外は無ければ不明
  init(fromFlat decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    var values: [NutrientID: Double] = [:]
    for id in NutrientID.allCases {
      if id.definition.core {
        values[id] = try container.decode(Double.self, forKey: Key(id))
      } else if let value = try container.decodeIfPresent(Double.self, forKey: Key(id)) {
        values[id] = value
      }
    }
    self.init(values)
  }

  /// 本文と同じ階層に、値の分かっている栄養素だけを書く
  func encodeFlat(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    for id in NutrientID.allCases {
      if let value = values[id] { try container.encode(value, forKey: Key(id)) }
    }
  }
}
