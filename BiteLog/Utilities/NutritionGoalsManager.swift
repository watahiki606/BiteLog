import Foundation
import SwiftUI

/// NutritionGoalsのObservableObjectラッパー（Cloudflare APIベース）
@MainActor
class NutritionGoalsManager: ObservableObject {
  @Published private(set) var goals: NutritionGoalsDTO = NutritionGoalsDTO(
    targetProtein: 150, targetFat: 80, targetNetCarbs: 250, targetFiber: 25
  )

  var targetProtein: Double {
    get { goals.targetProtein }
    set { goals.targetProtein = newValue; Task { await save() } }
  }

  var targetFat: Double {
    get { goals.targetFat }
    set { goals.targetFat = newValue; Task { await save() } }
  }

  var targetNetCarbs: Double {
    get { goals.targetNetCarbs }
    set { goals.targetNetCarbs = newValue; Task { await save() } }
  }

  var targetFiber: Double {
    get { goals.targetFiber }
    set { goals.targetFiber = newValue; Task { await save() } }
  }

  var targetCalories: Double { goals.targetCalories }

  init() {
    Task { await fetch() }
  }

  func fetch() async {
    guard AuthManager.shared.isSignedIn else { return }
    do {
      goals = try await APIClient.shared.fetchNutritionGoals()
    } catch {
      print("NutritionGoalsManager fetch error: \(error)")
    }
  }

  func resetToDefaults() {
    goals = NutritionGoalsDTO(targetProtein: 150, targetFat: 80, targetNetCarbs: 250, targetFiber: 25)
    Task { await save() }
  }

  private func save() async {
    do {
      goals = try await APIClient.shared.updateNutritionGoals(goals)
    } catch {
      print("NutritionGoalsManager save error: \(error)")
    }
  }
}
