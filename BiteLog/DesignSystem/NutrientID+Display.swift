import SwiftUI

/// 定義ファイルの栄養素の見た目。表示名と短い名前は生成した Nutrients.strings から引く。
extension NutrientID {
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
