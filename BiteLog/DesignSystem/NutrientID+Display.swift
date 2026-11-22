import SwiftUI

/// 栄養素を1行で見せるのに要るもの。画面に並べる `Nutrient` と、定義ファイルの `NutrientID` の両方が持つ
protocol NutrientDisplaying {
  var localizedName: String { get }
  var color: Color { get }
  var symbolName: String { get }
  var unit: String { get }
  func format(_ value: Double) -> String
  func accessibilityLabel(for value: Double) -> String
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
  /// 栄養素を足すときは個別の色を作らず、グループで共通の色にする。数十色に増えると見分けがつかない
  var color: Color {
    switch self {
    case .calories: return Color("NutrientCalories")
    case .protein: return Color("NutrientProtein")
    case .fat: return Color("NutrientFat")
    case .netCarbs: return Color("NutrientNetCarbs")
    case .dietaryFiber: return Color("NutrientFiber")
    default: return definition.group.color
    }
  }

  /// 色と一緒に出す形。頭文字の丸ではなく中身を連想できる形にする
  var symbolName: String {
    switch self {
    case .calories: return "flame.fill"
    case .protein: return "dumbbell.fill"
    case .fat: return "drop.fill"
    case .netCarbs: return "cube.fill"
    case .dietaryFiber: return "leaf.fill"
    default: return definition.group.symbolName
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
    default: return definition.unit
    }
  }
}

extension NutrientGroup {
  /// 最初の5項目のあとに足した栄養素の色。脂質の仲間は脂質と同じ系統にし、
  /// それ以外は控えめな色にする。Asset Catalog の色はコントラストを確かめてあるので、それを使い回す
  var color: Color {
    switch self {
    case .energy: return Color("NutrientCalories")
    case .macro: return Color("NutrientProtein")
    case .lipid: return Color("NutrientFat")
    case .carbohydrate: return Color("NutrientNetCarbs")
    case .vitamin, .mineral: return .secondary
    }
  }

  var symbolName: String {
    switch self {
    case .energy: return "flame.fill"
    case .macro: return "circle.fill"
    case .lipid: return "drop.halffull"
    case .carbohydrate: return "cube.fill"
    case .vitamin: return "pills.fill"
    case .mineral: return "circle.hexagongrid.fill"
    }
  }
}
