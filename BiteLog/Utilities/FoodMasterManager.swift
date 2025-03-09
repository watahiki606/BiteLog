import Foundation
import SwiftData

class FoodMasterManager {

  /// FoodMasterを安全に削除するメソッド
  /// - Parameters:
  ///   - foodMaster: 削除するFoodMaster
  ///   - modelContext: SwiftDataのモデルコンテキスト
  static func safeDeleteFoodMaster(foodMaster: FoodMaster, modelContext: ModelContext) {
    // 削除するFoodMasterを参照しているLogItemを検索
    let foodMasterId = foodMaster.id
    let descriptor = FetchDescriptor<LogItem>(
      predicate: #Predicate<LogItem> { logItem in
        if let itemFoodMaster = logItem.foodMaster {
          return itemFoodMaster.id == foodMasterId
        } else {
          return false
        }
      }
    )

    do {
      // 関連するLogItemを取得
      let relatedLogs = try modelContext.fetch(descriptor)

      // 各LogItemのFoodMasterデータをバックアップ
      for log in relatedLogs {
        log.backupFoodMasterData()
        log.foodMaster = nil  // リレーションシップを切る
        log.isMasterDeleted = true
      }

      // FoodMasterを削除
      modelContext.delete(foodMaster)

      // 変更を保存
      try modelContext.save()

    } catch {
      print("Error during safe delete: \(error)")
    }
  }

  /// 削除されたFoodMasterの情報を表示するための文字列を生成
  /// - Parameter logItem: 対象のLogItem
  /// - Returns: 表示用の文字列
  static func getDeletedFoodMasterDisplayText(logItem: LogItem) -> String {
    if logItem.isMasterDeleted {
      return "\(logItem.backupBrandName ?? "") \(logItem.backupProductName ?? "") (削除済み)"
    } else {
      return "\(logItem.brandName) \(logItem.productName)"
    }
  }

  /// FoodMasterの使用頻度をデクリメントするメソッド
  /// - Parameters:
  ///   - foodMaster: 更新するFoodMaster
  ///   - modelContext: SwiftDataのモデルコンテキスト
  static func decrementUsageCount(foodMaster: FoodMaster, modelContext: ModelContext) {
    foodMaster.decrementUsage()

    do {
      try modelContext.save()
    } catch {
      print("Error decrementing usage count: \(error)")
    }
  }

  /// LogItemが削除される際にFoodMasterの使用頻度をデクリメントするメソッド
  /// - Parameters:
  ///   - logItem: 削除されるLogItem
  ///   - modelContext: SwiftDataのモデルコンテキスト
  static func decrementUsageCountForLogItemDeletion(logItem: LogItem, modelContext: ModelContext) {
    if let foodMaster = logItem.foodMaster {
      decrementUsageCount(foodMaster: foodMaster, modelContext: modelContext)
    }
  }

}
