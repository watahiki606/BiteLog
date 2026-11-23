import Foundation

/// 栄養素1つの定義。値は `shared/nutrients.json` から生成した `NutrientID.definition` が持つ。
///
/// 表示名は言語で変わるので、ここには持たせず生成した Nutrients.strings から引く。
struct NutrientDefinition: Equatable, Sendable {
  let id: NutrientID
  /// D1 の食品の表の列名
  let column: String
  /// 内部の単位。食事摂取基準と成分表に合わせてあり、保存のときに換算しない
  let unit: String
  /// 表示する小数の桁数の上限
  let fractionDigits: Int
  let group: NutrientGroup
  /// 最初からある5項目。必須で、未入力は 0 として持つ。それ以外は未入力を「不明」として持つ
  let core: Bool
  /// 成分表から補うだけの詳しい栄養素。食品表示に載ることがまれなので入力欄に出さない。
  /// 基準は習慣的な摂取量に対するものなので、1日の合計にも出さず、統計の期間で見せる
  let detail: Bool
  let label: NutrientLabelRequirement
}

/// 表示でまとめる単位
enum NutrientGroup: String, Sendable {
  case energy, macro, lipid, carbohydrate, vitamin, mineral
}

/// 食品表示基準での扱い。ラベルから値を得られる見込みの目安になる
enum NutrientLabelRequirement: String, Sendable {
  case mandatory, recommended, optional
}

extension NutrientID {
  /// 最初の5項目のあとに足した栄養素のうち、食品表示に載りうるもの。入力欄と1日の合計に出す
  static let labelNutrients = allCases.filter { !$0.definition.core && !$0.definition.detail }
  /// 成分表から補うだけの詳しい栄養素。詳細と統計で、畳んだ中に並べる
  static let detailNutrients = allCases.filter { $0.definition.detail }
}
