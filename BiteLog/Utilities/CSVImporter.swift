import Foundation
import OSLog

enum CSVImportError: Error {
  case invalidFormat
  case invalidData(String)
  case cancelled

  var localizedDescription: String {
    switch self {
    case .invalidFormat:
      return NSLocalizedString("CSV file format is invalid", comment: "CSV import error")
    case .invalidData(let message):
      return String(
        format: NSLocalizedString("Failed to read data: %@", comment: "CSV import error"), message)
    case .cancelled:
      return NSLocalizedString("Import was cancelled", comment: "CSV import error")
    }
  }
}

class CSVImporter {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.bitelog", category: "CSVImporter")

  static func importCSV(from url: URL) async throws -> Int {
    let startTime = Date()
    logger.info("CSVインポート開始: \(url.lastPathComponent)")

    let csvText: String
    do {
      csvText = try String(contentsOf: url, encoding: .utf8)
    } catch {
      logger.error("ファイル読み込みエラー: \(error.localizedDescription)")
      throw CSVImportError.invalidData("ファイルの読み込みに失敗しました: \(error.localizedDescription)")
    }

    let result = try await APIClient.shared.importCSV(csvText: csvText)

    let elapsed = Date().timeIntervalSince(startTime)
    logger.info("CSVインポート完了: \(result.created)行, スキップ=\(result.skipped)行, FoodMaster新規=\(result.foodMastersCreated)件, 処理時間=\(String(format: "%.2f", elapsed))秒")

    return result.created
  }
}
