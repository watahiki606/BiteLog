import Foundation

/// 食品の入力欄の炭水化物と、うち食物繊維。
///
/// 食品表示の義務は炭水化物なので、入力欄はラベルと同じ並びにする。
/// 保存の形は糖質と食物繊維のまま。公開中の古い版のアプリが食物繊維を必須の数値として読むので、
/// 保存の形を変えても食物繊維を「不明」として持てないため。
struct CarbohydrateInput {
  let carbohydrate: Double
  let fiber: Double

  /// 入力欄の文字。空欄や読めない値は 0
  init(carbohydrate: String, dietaryFiber: String) {
    self.carbohydrate = Self.number(carbohydrate)
    self.fiber = Self.number(dietaryFiber)
  }

  /// 保存する糖質。引き算で出る 0.19999… のような誤差は丸める
  var netCarbs: Double { ((carbohydrate - fiber) * 10_000).rounded() / 10_000 }

  /// 食物繊維は炭水化物の内訳なので、炭水化物より多くはならない
  var isValid: Bool { fiber <= carbohydrate + 0.000_1 }

  /// 保存済みの値から、炭水化物の欄に出す文字を作る
  static func carbohydrateText(netCarbs: Double, dietaryFiber: Double) -> String {
    NutritionFormatter.formatNutrition(((netCarbs + dietaryFiber) * 10_000).rounded() / 10_000)
  }

  private static func number(_ text: String) -> Double {
    Double(text.trimmingCharacters(in: .whitespaces)) ?? 0
  }
}
