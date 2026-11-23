import Foundation

/// 栄養成分の値を適応的にフォーマットするユーティリティ
enum NutritionFormatter {
  /// 栄養成分の値を適応的にフォーマットします
  /// - 整数値の場合: 小数点なし (例: "1")
  /// - それ以外の場合: 小数点1桁表示 (例: "1.5"、"1.234" → "1.2")
  ///
  /// - Parameter value: フォーマットする数値
  /// - Returns: フォーマットされた文字列
  static func formatNutrition(_ value: Double) -> String {
    // 整数値の場合は小数点なし、それ以外は最大1桁に丸める
    if value.truncatingRemainder(dividingBy: 1) == 0 {
      return String(format: "%.0f", value)
    } else {
      return String(format: "%.1f", value)
    }
  }

  /// カロリーは 0.1 kcal 単位に意味が無いため整数に丸める。
  ///
  /// - Parameter value: フォーマットするカロリー値
  /// - Returns: 整数に丸めた文字列
  static func formatCalories(_ value: Double) -> String {
    String(format: "%.0f", value.rounded())
  }

  /// 栄養素の定義の桁数で整形する。0 桁なら整数に丸め、それ以外は整数なら小数を付けない
  static func format(_ value: Double, fractionDigits: Int) -> String {
    if fractionDigits == 0 { return formatCalories(value) }
    if value.truncatingRemainder(dividingBy: 1) == 0 { return String(format: "%.0f", value) }
    return String(format: "%.\(fractionDigits)f", value)
  }
}
