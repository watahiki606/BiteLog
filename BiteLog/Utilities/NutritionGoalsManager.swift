import Foundation
import SwiftUI

/// NutritionGoalsのObservableObjectラッパー（Cloudflare APIベース）
@MainActor
class NutritionGoalsManager: ObservableObject {
  static let defaults = NutritionGoalsDTO(
    targetProtein: 150, targetFat: 80, targetNetCarbs: 250, targetFiber: 25
  )

  @Published private(set) var goals: NutritionGoalsDTO = NutritionGoalsManager.defaults

  /// 保存に失敗したこと。目標の編集画面は入力を終えて離れたときに保存するので、
  /// 失敗を伝える頃には画面が無い。View ではなくここに持たせ、設定画面が出す。
  @Published var saveFailure: OperationFailure?

  var targetProtein: Double { goals.targetProtein }
  var targetFat: Double { goals.targetFat }
  var targetNetCarbs: Double { goals.targetNetCarbs }
  var targetFiber: Double { goals.targetFiber }
  var targetCalories: Double { goals.targetCalories }

  init() {
    Task { await fetch() }
  }

  func fetch() async {
    guard AuthManager.shared.isSignedIn else { return }
    do {
      goals = try await APIClient.shared.fetchNutritionGoals()
    } catch {
      // 取得できなくても既定値で表示は続けられる。ここで画面を止める必要はない。
      print("NutritionGoalsManager fetch error: \(error)")
    }
  }

  /// 4つの目標値をまとめて1回で保存する。
  ///
  /// 値ごとに保存を起こすと PUT が並走し、それぞれの応答が `goals` 全体を
  /// 上書きするため、最後に返った1本の内容で他の値が巻き戻る。
  func update(protein: Double, fat: Double, netCarbs: Double, fiber: Double) async {
    let updated = NutritionGoalsDTO(
      targetProtein: protein, targetFat: fat, targetNetCarbs: netCarbs, targetFiber: fiber)
    do {
      goals = try await APIClient.shared.updateNutritionGoals(updated)
    } catch {
      // 失敗したら `goals` は据え置き。次に開いたとき保存前の値が出る。
      saveFailure = .saving(error)
    }
  }

  func resetToDefaults() async {
    let d = NutritionGoalsManager.defaults
    await update(
      protein: d.targetProtein, fat: d.targetFat, netCarbs: d.targetNetCarbs,
      fiber: d.targetFiber)
  }
}
