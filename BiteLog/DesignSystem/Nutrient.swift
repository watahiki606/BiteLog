import SwiftUI

/// アプリで扱う栄養素。表示名・色・単位・短縮ラベルをここに集約する。
///
/// 以前は同じ栄養素の色と略号が ContentView / DayContentView / CommonComponents /
/// StatisticsView に別々に直書きされており、同じ食品が画面ごとに違う見た目で出ていた。
/// 栄養素の見た目は必ずこの型を経由させる。
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

  var localizedName: String {
    switch self {
    case .calories: return NSLocalizedString("Calories", comment: "Nutrient")
    case .protein: return NSLocalizedString("Protein", comment: "Nutrient")
    case .fat: return NSLocalizedString("Fat", comment: "Nutrient")
    case .netCarbs: return NSLocalizedString("Sugar", comment: "Nutrient")
    case .fiber: return NSLocalizedString("Dietary Fiber", comment: "Nutrient")
    case .carbs: return NSLocalizedString("Carbs", comment: "Nutrient")
    }
  }

  /// 横幅が取れない場所で使う短い名前。
  /// 以前は "S"(糖質) / "Fb"(食物繊維) という推測不能な略号だったため、
  /// 1文字略号ではなく言語ごとに読める語を用意する。
  var shortLabel: String {
    switch self {
    case .calories: return NSLocalizedString("Nutrient.Short.Calories", comment: "Short nutrient label")
    case .protein: return NSLocalizedString("Nutrient.Short.Protein", comment: "Short nutrient label")
    case .fat: return NSLocalizedString("Nutrient.Short.Fat", comment: "Short nutrient label")
    case .netCarbs: return NSLocalizedString("Nutrient.Short.NetCarbs", comment: "Short nutrient label")
    case .fiber: return NSLocalizedString("Nutrient.Short.Fiber", comment: "Short nutrient label")
    case .carbs: return NSLocalizedString("Nutrient.Short.Carbs", comment: "Short nutrient label")
    }
  }

  var unit: String { self == .calories ? "kcal" : "g" }

  /// ライト/ダークそれぞれでコントラストを確保した色を Asset Catalog から引く。
  /// SwiftUI 標準の .yellow / .brown は白背景でコントラストが足りない。
  var color: Color {
    switch self {
    case .calories: return Color("NutrientCalories")
    case .protein: return Color("NutrientProtein")
    case .fat: return Color("NutrientFat")
    case .netCarbs: return Color("NutrientNetCarbs")
    case .fiber: return Color("NutrientFiber")
    // 炭水化物は糖質と同じ系統の指標なので色も揃える。
    case .carbs: return Color("NutrientNetCarbs")
    }
  }

  var symbolName: String {
    switch self {
    case .calories: return "flame.fill"
    case .protein: return "p.circle.fill"
    case .fat: return "f.circle.fill"
    case .netCarbs: return "s.circle.fill"
    case .fiber: return "leaf.circle.fill"
    case .carbs: return "c.circle.fill"
    }
  }

  /// 栄養素ごとに妥当な桁数で整形する。カロリーだけ小数を落とす。
  func format(_ value: Double) -> String {
    self == .calories
      ? NutritionFormatter.formatCalories(value)
      : NutritionFormatter.formatNutrition(value)
  }

  func value(of values: NutritionValues) -> Double {
    switch self {
    case .calories: return values.calories
    case .protein: return values.protein
    case .fat: return values.fat
    case .netCarbs: return values.netCarbs
    case .fiber: return values.dietaryFiber
    case .carbs: return values.carbs
    }
  }

  /// VoiceOver 用。「タンパク質 45グラム」のように単位を読み上げさせる。
  func accessibilityLabel(for value: Double) -> String {
    let formatted = format(value)
    let unitName =
      self == .calories
      ? NSLocalizedString("Unit.Kilocalories", comment: "Spoken unit")
      : NSLocalizedString("Unit.Grams", comment: "Spoken unit")
    return "\(localizedName) \(formatted) \(unitName)"
  }
}
