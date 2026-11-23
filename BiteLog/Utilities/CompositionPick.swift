import Foundation

/// 食品を成分表の食品と重さにひも付けるときの決まり。
enum CompositionLink {
  /// 食材の重さの初期値。量の単位が重さか体積ならその数、個や人前は重さが分からないので 100 g
  static func defaultGrams(portionSize: Double, portionUnit: String) -> Double {
    let unit = portionUnit.trimmingCharacters(in: .whitespaces).lowercased()
    let byWeight = ["g", "gram", "grams", "グラム", "ml", "ミリリットル"].contains(unit)
    return byWeight && portionSize > 0 ? portionSize : 100
  }

  /// 候補を探す語。食品名の最初の語で探す。「鶏むね肉（皮なし）」なら「鶏むね肉」
  static func query(for productName: String) -> String {
    AIFoodAnalyzer.searchTerm(for: productName)
  }
}
