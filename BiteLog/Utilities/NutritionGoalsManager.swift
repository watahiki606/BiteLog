import Foundation
import SwiftData
import SwiftUI

@Model
final class NutritionGoals {
  @Attribute(.unique) var id: String = "default"
  var targetProtein: Double = 150
  var targetFat: Double = 80
  var targetNetCarbs: Double = 250
  var targetFiber: Double = 25

  /// カロリーは自動計算（タンパク質×4 + 脂質×9 + 糖質×4 + 食物繊維×2）
  var targetCalories: Double {
    targetProtein * 4 + targetFat * 9 + targetNetCarbs * 4 + targetFiber * 2
  }

  init() {}

  /// デフォルト値にリセット
  func resetToDefaults() {
    targetProtein = 150
    targetFat = 80
    targetNetCarbs = 250
    targetFiber = 25
  }
}

/// NutritionGoalsのObservableObjectラッパー（View間の共有用）
class NutritionGoalsManager: ObservableObject {
  private let modelContext: ModelContext

  @Published private(set) var goals: NutritionGoals

  var targetProtein: Double {
    get { goals.targetProtein }
    set {
      goals.targetProtein = newValue
      objectWillChange.send()
      save()
    }
  }

  var targetFat: Double {
    get { goals.targetFat }
    set {
      goals.targetFat = newValue
      objectWillChange.send()
      save()
    }
  }

  var targetNetCarbs: Double {
    get { goals.targetNetCarbs }
    set {
      goals.targetNetCarbs = newValue
      objectWillChange.send()
      save()
    }
  }

  var targetFiber: Double {
    get { goals.targetFiber }
    set {
      goals.targetFiber = newValue
      objectWillChange.send()
      save()
    }
  }

  var targetCalories: Double {
    goals.targetCalories
  }

  init(modelContext: ModelContext) {
    self.modelContext = modelContext

    // 既存のNutritionGoalsを取得、なければ作成
    let descriptor = FetchDescriptor<NutritionGoals>()
    if let existing = try? modelContext.fetch(descriptor).first {
      self.goals = existing
    } else {
      let newGoals = NutritionGoals()
      modelContext.insert(newGoals)
      try? modelContext.save()
      self.goals = newGoals

      // AppStorageからの移行
      migrateFromAppStorage()
    }
  }

  func resetToDefaults() {
    goals.resetToDefaults()
    objectWillChange.send()
    save()
  }

  private func save() {
    try? modelContext.save()
  }

  /// AppStorageからの移行（初回のみ）
  private func migrateFromAppStorage() {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: "targetProtein") != nil {
      goals.targetProtein = defaults.double(forKey: "targetProtein")
      goals.targetFat = defaults.double(forKey: "targetFat")
      goals.targetNetCarbs = defaults.double(forKey: "targetSugar")
      goals.targetFiber = defaults.double(forKey: "targetFiber")
      save()

      // 移行後にAppStorageのキーを削除
      defaults.removeObject(forKey: "targetProtein")
      defaults.removeObject(forKey: "targetFat")
      defaults.removeObject(forKey: "targetSugar")
      defaults.removeObject(forKey: "targetFiber")
    }
  }
}
