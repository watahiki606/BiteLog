import Foundation

/// 食品の入力で、成分表から選んだ食品の値を欄に入れるときの決まり。
///
/// 入れた値は手で打った値と同じで、保存の前でもあとでも直せる。食品と成分表は結ばない。
enum CompositionPick {
  /// 値を入れる欄。炭水化物の欄は、成分表の糖質と食物繊維を足した値にする
  enum Field: Hashable {
    case calories, protein, fat, carbohydrate, dietaryFiber
    case added(NutrientID)
  }

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

  /// 成分表の100 g あたりの値を、重さの分にして欄の文字にする。成分表で未測定の栄養素は含めない
  static func fieldTexts(per100g: [String: Double], grams: Double) -> [Field: String] {
    func amount(_ id: NutrientID) -> Double? { per100g[id.rawValue].map { $0 * grams / 100 } }
    func text(_ value: Double, _ id: NutrientID) -> String {
      NutritionFormatter.format(value, fractionDigits: id.definition.fractionDigits)
    }

    var texts: [Field: String] = [:]
    let core: [(Field, NutrientID)] = [
      (.calories, .calories), (.protein, .protein), (.fat, .fat), (.dietaryFiber, .dietaryFiber),
    ]
    for (field, id) in core {
      if let value = amount(id) { texts[field] = text(value, id) }
    }
    if let netCarbs = amount(.netCarbs), let fiber = amount(.dietaryFiber) {
      texts[.carbohydrate] = text(netCarbs + fiber, .netCarbs)
    }
    for id in NutrientID.allCases where !id.definition.core {
      if let value = amount(id) { texts[.added(id)] = text(value, id) }
    }
    return texts
  }

  /// 欄に書く文字を決める。返すのは書き換える欄だけ。
  ///
  /// 空の欄と、前に成分表から入れたまま触っていない欄だけを書き換える。ラベルを見て手で入れた値は
  /// 商品に近いので残す。選び直したとき、新しい候補で未測定の栄養素は、前に入れた値を空に戻す
  static func merge(
    current: [Field: String], picked: [Field: String], previouslyPicked: [Field: String]
  ) -> [Field: String] {
    var result: [Field: String] = [:]
    for field in Set(picked.keys).union(previouslyPicked.keys) {
      let now = current[field]?.trimmingCharacters(in: .whitespaces) ?? ""
      let untouched = now.isEmpty || now == previouslyPicked[field]
      guard untouched else { continue }
      result[field] = picked[field] ?? ""
    }
    return result
  }
}
