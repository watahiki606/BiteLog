import Foundation

/// 栄養成分の値を適応的にフォーマットするユーティリティ
enum NutritionFormatter {
  /// 栄養成分の値を適応的にフォーマットします
  /// - 整数値の場合: 小数点なし (例: "1")
  /// - 小数点1桁で収まる場合: 1桁表示 (例: "1.5")
  /// - それ以外の場合: 3桁表示 (例: "1.234")
  ///
  /// - Parameter value: フォーマットする数値
  /// - Returns: フォーマットされた文字列
  static func formatNutrition(_ value: Double) -> String {
    // 整数値の場合
    if value.truncatingRemainder(dividingBy: 1) == 0 {
      return String(format: "%.0f", value)
    }
    // 小数点1桁で収まる場合
    else if value * 10 == (value * 10).rounded() {
      return String(format: "%.1f", value)
    }
    // それ以外は3桁表示
    else {
      return String(format: "%.3f", value)
    }
  }

  /// カロリー用のフォーマット（常に整数表示）
  ///
  /// - Parameter value: フォーマットする数値
  /// - Returns: フォーマットされた文字列
  static func formatCalories(_ value: Double) -> String {
    return String(format: "%.0f", value)
  }
}
