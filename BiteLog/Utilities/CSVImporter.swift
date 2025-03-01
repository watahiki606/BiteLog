import Foundation
import OSLog
import SwiftData

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
  // ロガーの設定
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.bitelog", category: "CSVImporter")
  // 進捗状況を報告するためのコールバック
  typealias ProgressHandler = (Double, Int, Int) -> Bool  // 進捗率, 現在の行, 全行数, キャンセルならtrue

  static func importCSV(
    from url: URL, context: ModelContext, progressHandler: ProgressHandler? = nil
  ) throws {
    let startTime = Date()
    logger.info("CSVインポート開始: \(url.lastPathComponent)")

    let csvString: String
    do {
      logger.debug("CSVファイルの読み込み: \(url.path)")
      csvString = try String(contentsOf: url, encoding: .utf8)
      let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
      logger.info(
        "ファイル読み込み完了: サイズ \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))"
      )
    } catch {
      logger.error("ファイル読み込みエラー: \(error.localizedDescription)")
      throw CSVImportError.invalidData("ファイルの読み込みに失敗しました: \(error.localizedDescription)")
    }

    let rows = csvString.components(separatedBy: .newlines)
    guard !rows.isEmpty else {
      logger.error("CSVファイルが空です")
      throw CSVImportError.invalidData("CSVファイルが空です")
    }

    let totalRows = rows.count - 1  // ヘッダー行を除く
    logger.info("CSVインポート: 全\(totalRows)行のデータを処理します")

    // 進捗状況の初期報告
    if let progressHandler = progressHandler {
      if progressHandler(0.0, 0, totalRows) {
        logger.notice("ユーザーによりインポートがキャンセルされました")
        throw CSVImportError.cancelled
      }
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    var successCount = 0
    var errorCount = 0
    var lastLoggedProgress: Int = 0

    // 2行目以降のデータを処理
    for (index, row) in rows.dropFirst().enumerated() where !row.isEmpty {
      // 進捗状況の報告（10行ごと）
      if let progressHandler = progressHandler, index % 10 == 0 || index == totalRows - 1 {
        let progress = Double(index + 1) / Double(totalRows)

        // 進捗ログは10%ごとに出力（頻繁すぎるログを避けるため）
        let progressPercent = Int(progress * 100)
        if progressPercent / 10 > lastLoggedProgress / 10 {
          logger.info("インポート進捗: \(progressPercent)% (\(index + 1)/\(totalRows)行)")
          lastLoggedProgress = progressPercent
        }

        if progressHandler(progress, index + 1, totalRows) {
          logger.notice("ユーザーによりインポート処理がキャンセルされました (\(index + 1)/\(totalRows)行の処理後)")
          throw CSVImportError.cancelled
        }
      }

      do {
        let columns = parseCSVLine(row)
        guard columns.count >= 9 else {
          throw CSVImportError.invalidData("\(index + 2)行目: カラム数が不正です (\(columns.count)列)")
        }

        guard let date = dateFormatter.date(from: columns[0]) else {
          throw CSVImportError.invalidData("\(index + 2)行目: 日付の形式が不正です: \(columns[0])")
        }

        // 日本語と英語の両方の食事タイプをサポート
        guard let mealType = MealType(rawValue: columns[1]) else {
          throw CSVImportError.invalidData("\(index + 2)行目: 無効な食事タイプです: \(columns[1])")
        }

        // すべての数値カラムから引用符とカンマを除去
        let cleanedCalories = columns[5]
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: ",", with: "")
        let cleanedCarbs = columns[6]
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: ",", with: "")
        let cleanedFat = columns[7]
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: ",", with: "")
        let cleanedProtein = columns[8]
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: ",", with: "")

        guard let calories = Double(cleanedCalories),
          let carbs = Double(cleanedCarbs),
          let fat = Double(cleanedFat),
          let protein = Double(cleanedProtein)
        else {
          print(
            "数値変換エラー - カロリー: \(cleanedCalories), 炭水化物: \(cleanedCarbs), 脂質: \(cleanedFat), タンパク質: \(cleanedProtein)"
          )
          throw CSVImportError.invalidData("\(index + 2)行目: 栄養価の数値が不正です")
        }

        // オプションで食事量を取得（10列目があれば）
        var numberOfServings = 1.0
        if columns.count > 9 {
          let cleanedServings = columns[9]
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: ",", with: "")
          if let servingsValue = Double(cleanedServings) {
            numberOfServings = servingsValue
          }
        }

        let item = Item(
          brandName: columns[2],
          productName: columns[3],
          portion: columns[4],
          calories: calories,
          protein: protein,
          fat: fat,
          carbohydrates: carbs,
          mealType: mealType,
          timestamp: date,
          numberOfServings: numberOfServings
        )

        context.insert(item)
        successCount += 1
      } catch {
        errorCount += 1
        logger.error("行\(index + 2)の処理中にエラー: \(error.localizedDescription)")
      }
    }

    let elapsedTime = Date().timeIntervalSince(startTime)
    logger.info(
      "CSVインポート完了: 成功=\(successCount)行, 失敗=\(errorCount)行, 処理時間=\(String(format: "%.2f", elapsedTime))秒"
    )
  }

  // CSVライン解析用のヘルパーメソッド
  private static func parseCSVLine(_ line: String) -> [String] {
    var columns: [String] = []
    var currentColumn = ""
    var insideQuotes = false

    for char in line {
      switch char {
      case "\"":
        insideQuotes.toggle()
      case ",":
        if !insideQuotes {
          columns.append(currentColumn.trimmingCharacters(in: .whitespaces))
          currentColumn = ""
        } else {
          currentColumn.append(char)
        }
      default:
        currentColumn.append(char)
      }
    }

    // 最後のカラムを追加
    columns.append(currentColumn.trimmingCharacters(in: .whitespaces))

    return columns
  }
}
