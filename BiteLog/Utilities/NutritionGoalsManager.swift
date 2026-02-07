import Foundation
import SwiftUI

class NutritionGoalsManager: ObservableObject {
  // デフォルト値
  static let defaultProtein: Double = 150
  static let defaultFat: Double = 80
  static let defaultSugar: Double = 250
  static let defaultFiber: Double = 25

  @AppStorage("targetProtein") var targetProtein: Double = defaultProtein {
    didSet {
      objectWillChange.send()
    }
  }

  @AppStorage("targetFat") var targetFat: Double = defaultFat {
    didSet {
      objectWillChange.send()
    }
  }

  @AppStorage("targetSugar") var targetSugar: Double = defaultSugar {
    didSet {
      objectWillChange.send()
    }
  }

  @AppStorage("targetFiber") var targetFiber: Double = defaultFiber {
    didSet {
      objectWillChange.send()
    }
  }

  /// カロリーは自動計算（タンパク質×4 + 脂質×9 + 糖質×4 + 食物繊維×2）
  var targetCalories: Double {
    targetProtein * 4 + targetFat * 9 + targetSugar * 4 + targetFiber * 2
  }

  /// デフォルト値にリセット
  func resetToDefaults() {
    targetProtein = Self.defaultProtein
    targetFat = Self.defaultFat
    targetSugar = Self.defaultSugar
    targetFiber = Self.defaultFiber
  }
}
