import SwiftUI

/// 栄養素を1行で見せるのに要るもの。画面に並べる `Nutrient` と、定義ファイルの `NutrientID` の両方が持つ
protocol NutrientDisplaying {
  var localizedName: String { get }
  var color: Color { get }
  var glyph: NutrientGlyph { get }
  var unit: String { get }
  func format(_ value: Double) -> String
  func accessibilityLabel(for value: Double) -> String
  /// 読み上げる単位。「グラム」
  var spokenUnit: String { get }
}

extension Nutrient: NutrientDisplaying {}

/// 定義ファイルの栄養素の見た目。表示名と短い名前は生成した Nutrients.strings から引く。
extension NutrientID: NutrientDisplaying {
  var unit: String { definition.unit }

  /// VoiceOver 用。「食塩相当量 2.5 グラム」のように単位を読み上げさせる
  func accessibilityLabel(for value: Double) -> String {
    "\(localizedName) \(format(value)) \(spokenUnit)"
  }

  var localizedName: String {
    NSLocalizedString("\(rawValue).name", tableName: "Nutrients", comment: "Nutrient name")
  }

  /// 横幅が取れない場所で使う短い名前
  var shortName: String {
    NSLocalizedString("\(rawValue).shortName", tableName: "Nutrients", comment: "Short nutrient name")
  }

  /// ライト/ダークそれぞれでコントラストを確かめた色を Asset Catalog から引く。
  ///
  /// 並べて見分けられるよう、同じ見出しの中で隣り合う栄養素は別の色にする。赤は上限を超えた印に取っておき、
  /// 主要な栄養素の色とも分ける。ミネラルは寒色、ビタミンは暖色で、脂肪酸は脂質と同じ色にする
  var color: Color {
    switch self {
    case .calories: return Color("NutrientCalories")
    case .protein: return Color("NutrientProtein")
    case .fat, .saturatedFat, .n3FattyAcids, .n6FattyAcids: return Color("NutrientFat")
    case .netCarbs: return Color("NutrientNetCarbs")
    case .dietaryFiber: return Color("NutrientFiber")
    case .saltEquivalent, .iodine: return Color("NutrientSlate")
    case .potassium, .phosphorus, .selenium: return Color("NutrientIndigo")
    case .calcium, .manganese: return Color("NutrientCyan")
    case .magnesium, .zinc, .chromium: return Color("NutrientTeal")
    case .iron, .copper, .molybdenum: return Color("NutrientPurple")
    case .vitaminA, .vitaminB1, .vitaminB6, .pantothenicAcid: return Color("NutrientPink")
    case .vitaminD, .vitaminE, .vitaminB2, .vitaminB12, .biotin: return Color("NutrientYellow")
    case .vitaminC, .vitaminK, .niacin, .folate: return Color("NutrientLime")
    }
  }

  /// 色と一緒に出す印。主要な栄養素は中身を連想できる形にする。
  /// ミネラルは元素記号、ビタミンは A や B1 のような記号にする。形で描き分けられる数ではなく、記号のほうが読み取れる
  var glyph: NutrientGlyph {
    switch self {
    case .calories: return .symbol("flame.fill")
    case .protein: return .symbol("dumbbell.fill")
    case .fat: return .symbol("drop.fill")
    case .netCarbs: return .symbol("cube.fill")
    case .dietaryFiber: return .symbol("leaf.fill")
    case .saltEquivalent: return .text("NaCl")
    // 脂質の仲間なので、脂質の滴の形を半分にする
    case .saturatedFat: return .symbol("drop.halffull")
    case .n3FattyAcids: return .text("n-3")
    case .n6FattyAcids: return .text("n-6")
    case .potassium: return .text("K")
    case .calcium: return .text("Ca")
    case .magnesium: return .text("Mg")
    case .iron: return .text("Fe")
    case .phosphorus: return .text("P")
    case .zinc: return .text("Zn")
    case .copper: return .text("Cu")
    case .manganese: return .text("Mn")
    case .iodine: return .text("I")
    case .selenium: return .text("Se")
    case .chromium: return .text("Cr")
    case .molybdenum: return .text("Mo")
    case .vitaminA: return .text("A")
    case .vitaminD: return .text("D")
    case .vitaminC: return .text("C")
    case .vitaminE: return .text("E")
    case .vitaminK: return .text("K")
    case .vitaminB1: return .text("B1")
    case .vitaminB2: return .text("B2")
    case .niacin: return .text("B3")
    case .vitaminB6: return .text("B6")
    case .vitaminB12: return .text("B12")
    case .folate: return .text("B9")
    case .pantothenicAcid: return .text("B5")
    case .biotin: return .text("B7")
    }
  }

  /// 定義の桁数で整形する
  func format(_ value: Double) -> String {
    NutritionFormatter.format(value, fractionDigits: definition.fractionDigits)
  }

  /// VoiceOver で読み上げる単位の名前。記号のままだと「g」を「ジー」と読む
  var spokenUnit: String {
    switch definition.unit {
    case "kcal": return NSLocalizedString("Unit.Kilocalories", comment: "Spoken unit")
    case "g": return NSLocalizedString("Unit.Grams", comment: "Spoken unit")
    case "mg": return NSLocalizedString("Unit.Milligrams", comment: "Spoken unit")
    case "µg": return NSLocalizedString("Unit.Micrograms", comment: "Spoken unit")
    default: return definition.unit
    }
  }
}

/// 栄養素の印。SF Symbols の形か、元素記号のような短い文字
enum NutrientGlyph: Equatable {
  case symbol(String)
  case text(String)
}
