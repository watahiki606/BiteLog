import Foundation
import SwiftData

class FoodMasterManager {

  /// FoodMasterを安全に削除するメソッド
  static func safeDeleteFoodMaster(foodMaster: FoodMaster, modelContext: ModelContext) {
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
      let relatedLogs = try modelContext.fetch(descriptor)

      for log in relatedLogs {
        log.backupFoodMasterData()
        log.foodMaster = nil
        log.isMasterDeleted = true
      }

      modelContext.delete(foodMaster)
      try modelContext.save()
    } catch {
      print("Error during safe delete: \(error)")
    }
  }

  /// 削除されたFoodMasterの情報を表示するための文字列を生成
  static func getDeletedFoodMasterDisplayText(logItem: LogItem) -> String {
    if logItem.isMasterDeleted {
      return "\(logItem.brandName) \(logItem.productName) (削除済み)"
    } else {
      return "\(logItem.brandName) \(logItem.productName)"
    }
  }

  /// FoodMasterの使用頻度をデクリメントするメソッド
  static func decrementUsageCount(foodMaster: FoodMaster, modelContext: ModelContext) {
    foodMaster.decrementUsage()

    do {
      try modelContext.save()
    } catch {
      print("Error decrementing usage count: \(error)")
    }
  }

  /// LogItemが削除される際にFoodMasterの使用頻度をデクリメントするメソッド
  static func decrementUsageCountForLogItemDeletion(logItem: LogItem, modelContext: ModelContext) {
    if let foodMaster = logItem.foodMaster {
      decrementUsageCount(foodMaster: foodMaster, modelContext: modelContext)
    }
  }
}
