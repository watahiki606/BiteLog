import Foundation
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
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.bitelog", category: "CSVExporter")

  typealias ProgressHandler = (Double, Int, Int) -> Bool

  private static func escapeCSV(_ value: String) -> String {
    var result = value
    if result.contains("\"") || result.contains(",") || result.contains("\n") {
      result = result.replacingOccurrences(of: "\"", with: "\"\"")
      result = "\"\(result)\""
    }
    return result
  }

  static func exportLogItems(
    to url: URL, progressHandler: ProgressHandler? = nil
  ) async throws -> Int {
    let startTime = Date()
    logger.info("LogItemのCSVエクスポート開始")

    let logItems = try await APIClient.shared.fetchAllLogItems()
    let totalItems = logItems.count
    logger.info("エクスポート対象: LogItem \(totalItems)件")

    if let progressHandler, progressHandler(0.0, 0, totalItems) {
      return 0
    }

    let header = "date,meal_type,brand_name,product_name,calories,carbs,dietary_fiber,fat,protein,portion_amount,portion_unit"
    var csvString = header + "\n"

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    for (index, item) in logItems.enumerated() {
      if let progressHandler, index % 10 == 0 || index == totalItems - 1 {
        let progress = Double(index + 1) / Double(totalItems)
        if progressHandler(progress, index + 1, totalItems) {
          return index + 1
        }
      }

      let dateString = dateFormatter.string(from: item.timestamp)
      let carbs = item.netCarbs + item.dietaryFiber
      let row = "\(dateString),\(item.mealType.rawValue),\(escapeCSV(item.brandName)),\(escapeCSV(item.productName)),\(item.calories),\(carbs),\(item.dietaryFiber),\(item.fat),\(item.protein),\(item.numberOfServings),\(escapeCSV(item.portionUnit))"
      csvString += row + "\n"
    }

    do {
      try csvString.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      logger.error("CSVファイルへの書き込みに失敗しました: \(error.localizedDescription)")
      throw CSVExportError.dataWriteFailed
    }

    let elapsed = Date().timeIntervalSince(startTime)
    logger.info("CSVエクスポート完了: \(totalItems)件, 処理時間=\(String(format: "%.2f", elapsed))秒")
    return totalItems
  }
}
