import Foundation
import SwiftData
import OSLog

enum CSVExportError: Error {
  case dataWriteFailed
  case fileCreationFailed
  
  var localizedDescription: String {
    switch self {
    case .dataWriteFailed:
      return NSLocalizedString("Failed to write data to CSV file", comment: "CSV export error")
    case .fileCreationFailed:
      return NSLocalizedString("Failed to create CSV file", comment: "CSV export error")
    }
  }
}

class CSVExporter {
  // ロガーの設定
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.bitelog", category: "CSVExporter")
  
  // 進捗状況を報告するためのコールバック
  typealias ProgressHandler = (Double, Int, Int) -> Bool  // 進捗率, 現在の行, 全行数, キャンセルならtrue
  
  // CSVラインをエスケープするヘルパーメソッド
  private static func escapeCSV(_ value: String) -> String {
    var result = value
    // 数値や日付に変換できない場合はエスケープ処理が必要
    if result.contains("\"") || result.contains(",") || result.contains("\n") {
      result = result.replacingOccurrences(of: "\"", with: "\"\"")
      result = "\"\(result)\""
    }
    return result
  }
  
  // LogItemをCSVファイルにエクスポート
  static func exportLogItems(to url: URL, context: ModelContext, progressHandler: ProgressHandler? = nil) throws -> Int {
    let startTime = Date()
    logger.info("LogItemのCSVエクスポート開始")
    
    // すべてのLogItemを取得
    let fetchDescriptor = FetchDescriptor<LogItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
    guard let logItems = try? context.fetch(fetchDescriptor) else {
      logger.error("LogItemの取得に失敗しました")
      throw CSVExportError.dataWriteFailed
    }
    
    let totalItems = logItems.count
    logger.info("エクスポート対象: LogItem \(totalItems)件")
    
    // 進捗状況の初期報告
    if let progressHandler = progressHandler {
      if progressHandler(0.0, 0, totalItems) {
        logger.notice("ユーザーによりエクスポートがキャンセルされました")
        return 0
      }
    }
    
    // CSVヘッダー
    let header = "date,meal_type,brand_name,product_name,calories,carbs,dietary_fiber,fat,protein,portion_amount,portion_unit"
    var csvString = header + "\n"
    
    // 日付フォーマッタ
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    
    // LogItemをCSV形式に変換
    for (index, item) in logItems.enumerated() {
      // 進捗状況の報告（10アイテムごと）
      if let progressHandler = progressHandler, index % 10 == 0 || index == totalItems - 1 {
        let progress = Double(index + 1) / Double(totalItems)
        if progressHandler(progress, index + 1, totalItems) {
          logger.notice("ユーザーによりエクスポートがキャンセルされました (\(index + 1)/\(totalItems)件処理後)")
          return index + 1
        }
      }
      
      let dateString = dateFormatter.string(from: item.timestamp)
      let mealTypeString = item.mealType.rawValue
      
      let brandName = escapeCSV(item.brandName)
      let productName = escapeCSV(item.productName)
      
      // 炭水化物 = 糖質 + 食物繊維
      let carbs = item.sugar + item.dietaryFiber
      
      // portion_amountとしてnumberOfServingsを使用
      let portionAmount = item.numberOfServings
      
      let row = "\(dateString),\(mealTypeString),\(brandName),\(productName),\(item.calories),\(carbs),\(item.dietaryFiber),\(item.fat),\(item.protein),\(portionAmount),\(escapeCSV(item.portionUnit))"
      csvString += row + "\n"
    }
    
    // CSVファイルに書き込み
    do {
      try csvString.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      logger.error("CSVファイルへの書き込みに失敗しました: \(error.localizedDescription)")
      throw CSVExportError.dataWriteFailed
    }
    
    let elapsedTime = Date().timeIntervalSince(startTime)
    logger.info("LogItemのCSVエクスポート完了: \(totalItems)件, 処理時間=\(String(format: "%.2f", elapsedTime))秒")
    
    return totalItems
  }
}