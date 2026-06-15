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
}
