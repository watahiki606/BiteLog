import SwiftUI

/// 画面に並べる栄養素。表示名・色・単位・短縮ラベルをここに集約する。
///
/// 栄養素の見た目は必ずこの型を経由させる。View 側で色や略号を直書きすると、
/// 同じ食品が画面ごとに違う見た目になる。
/// 定義ファイルにある栄養素は `NutrientID` から引く。炭水化物は糖質と食物繊維の合計で、
/// 定義ファイルには無いので、ここで持つ。
enum Nutrient: String, CaseIterable, Identifiable {
  case calories
  case protein
  case fat
  /// 糖質。炭水化物から食物繊維を引いた値。
  case netCarbs
  case fiber
  /// 炭水化物（糖質 + 食物繊維）。内訳ではなく合計なので一覧のチップには出さない。
  case carbs

  var id: String { rawValue }

  /// 一覧の行に並べる内訳。合計である炭水化物は内訳と混ざるので含めない。
  static let chipNutrients: [Nutrient] = [.protein, .fat, .netCarbs, .fiber]

  /// 定義ファイルの栄養素。合計である炭水化物は定義に無いので nil
  var nutrientID: NutrientID? {
    switch self {
    case .calories: return .calories
    case .protein: return .protein
    case .fat: return .fat
    case .netCarbs: return .netCarbs
    case .fiber: return .dietaryFiber
    case .carbs: return nil
    }
  }

  var localizedName: String {
    nutrientID?.localizedName ?? NSLocalizedString("Carbohydrates", comment: "Nutrient")
  }

  /// 横幅が取れない場所で使う短い名前。
  /// 1文字に詰めると糖質と食物繊維が区別できないので、言語ごとに読める語を置く。
  var shortLabel: String {
    nutrientID?.shortName ?? NSLocalizedString("Nutrient.Short.Carbs", comment: "Short nutrient label")
  }

  var unit: String { nutrientID?.definition.unit ?? "g" }

  /// SwiftUI 標準の .yellow / .brown は白背景でコントラストが足りないので、Asset Catalog の色を使う。
  /// 炭水化物は糖質と同じ系統の指標なので色も揃える。
  var color: Color { (nutrientID ?? .netCarbs).color }

  /// 色と一緒に出す形。色だけだと、色の見分けにくい人や
  /// 小さく表示したときに栄養素を取り違える。
  var glyph: NutrientGlyph { nutrientID?.glyph ?? .symbol("square.stack.3d.up.fill") }

  /// 栄養素ごとに妥当な桁数で整形する。炭水化物は糖質と食物繊維と同じ桁にする
  func format(_ value: Double) -> String {
    (nutrientID ?? .netCarbs).format(value)
  }

  func value(of values: NutritionValues) -> Double {
    nutrientID.map { values.amounts.core($0) } ?? values.carbs
  }

  /// 読み上げる単位。炭水化物は糖質と同じ g
  var spokenUnit: String { (nutrientID ?? .netCarbs).spokenUnit }

  /// VoiceOver 用。「タンパク質 45グラム」のように単位を読み上げさせる。
  func accessibilityLabel(for value: Double) -> String {
    "\(localizedName) \(format(value)) \(spokenUnit)"
  }
}
