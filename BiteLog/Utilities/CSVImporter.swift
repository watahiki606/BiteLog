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
  
  // FoodMasterの一意性を確認するためのユニークキーを生成するヘルパーメソッド
  private static func createUniqueKey(brandName: String, productName: String, calories: Double, carbs: Double, fat: Double, protein: Double, portionUnit: String) -> String {
    // 数値は小数点以下2桁に丸めて文字列化
    let caloriesStr = String(format: "%.2f", calories)
    let carbsStr = String(format: "%.2f", carbs)
    let fatStr = String(format: "%.2f", fat)
    let proteinStr = String(format: "%.2f", protein)
    
    // すべての栄養素を含めた文字列を作成
    return "\(brandName)|\(productName)|\(caloriesStr)|\(carbsStr)|\(fatStr)|\(proteinStr)|\(portionUnit)"
  }

  static func importCSV(
    from url: URL, context: ModelContext, progressHandler: ProgressHandler? = nil
  ) throws -> Int {
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
    var foodMastersToInsert: [FoodMaster] = []  // FoodMaster のバッチ挿入用配列
    var logItemsToInsert: [LogItem] = []  // LogItem のバッチ挿入用配列
    
    // 既存のFoodMasterをユニークキーでキャッシュするための辞書
    var existingFoodMasterCache: [String: FoodMaster] = [:]
    
    // 既存のFoodMasterをすべて取得してキャッシュに格納
    let fetchDescriptor = FetchDescriptor<FoodMaster>()
    if let existingFoodMasters = try? context.fetch(fetchDescriptor) {
        for foodMaster in existingFoodMasters {
            existingFoodMasterCache[foodMaster.uniqueKey] = foodMaster
        }
    }
    
    logger.info("既存のFoodMaster \(existingFoodMasterCache.count)件をキャッシュしました")

    // ヘッダーのインデックスを取得
    let headers = parseCSVLine(rows[0]).map { $0.lowercased() }
    let dateIndex = headers.firstIndex(of: "date") ?? 0
    let mealTypeIndex = headers.firstIndex(of: "meal_type") ?? 1
    let brandNameIndex = headers.firstIndex(of: "brand_name") ?? 2
    let productNameIndex = headers.firstIndex(of: "product_name") ?? 3
    let caloriesIndex = headers.firstIndex(of: "calories") ?? 4
    let carbsIndex = headers.firstIndex(of: "carbs") ?? 5
    let fatIndex = headers.firstIndex(of: "fat") ?? 6
    let proteinIndex = headers.firstIndex(of: "protein") ?? 7
    let portionAmountIndex = headers.firstIndex(of: "portion_amount") ?? 8
    let portionUnitIndex = headers.firstIndex(of: "portion_unit") ?? 9

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

        guard let date = dateFormatter.date(from: columns[dateIndex]) else {
          throw CSVImportError.invalidData("\(index + 2)行目: 日付の形式が不正です: \(columns[dateIndex])")
        }

        // 日本語と英語の両方の食事タイプをサポート
        guard let mealType = MealType(rawValue: columns[mealTypeIndex]) else {
          throw CSVImportError.invalidData("\(index + 2)行目: 無効な食事タイプです: \(columns[mealTypeIndex])")
        }

        // すべての数値カラムから引用符とカンマを除去
        let cleanedCalories = columns[caloriesIndex]
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: ",", with: "")
        let cleanedCarbs = columns[carbsIndex]
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: ",", with: "")
        let cleanedFat = columns[fatIndex]
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: ",", with: "")
        let cleanedProtein = columns[proteinIndex]
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: ",", with: "")
        let cleanedPortionAmount = columns[portionAmountIndex]
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: ",", with: "")

        let portionUnit = columns[portionUnitIndex]

        // 数値に変換
        let calories = Double(cleanedCalories) ?? 0
        let carbs = Double(cleanedCarbs) ?? 0
        let fat = Double(cleanedFat) ?? 0
        let protein = Double(cleanedProtein) ?? 0
        let portionAmount = Double(cleanedPortionAmount) ?? 0  // Double型に変換

        // CSVデータの値をログに出力（デバッグ用）
        logger.debug("CSVから読み込んだデータ: \(columns[productNameIndex]), \(columns[brandNameIndex]), calories=\(calories), carbs=\(carbs), fat=\(fat), protein=\(protein), portionUnit=\(portionUnit), portionAmount=\(portionAmount)")

        // 1portion_unitあたりの栄養価を計算（portion_amountが1になるように正規化）
        let caloriesPerUnit = portionAmount > 0 ? calories / portionAmount : calories
        let carbsPerUnit = portionAmount > 0 ? carbs / portionAmount : carbs
        let fatPerUnit = portionAmount > 0 ? fat / portionAmount : fat
        let proteinPerUnit = portionAmount > 0 ? protein / portionAmount : protein
        
        logger.debug("1\(portionUnit)あたりの栄養価: calories=\(caloriesPerUnit), carbs=\(carbsPerUnit), fat=\(fatPerUnit), protein=\(proteinPerUnit)")

        // FoodMasterの検索または作成
        var foodMaster: FoodMaster
        
        // ユニークキーを生成
        let uniqueKey = createUniqueKey(
            brandName: columns[brandNameIndex],
            productName: columns[productNameIndex],
            calories: caloriesPerUnit,
            carbs: carbsPerUnit,
            fat: fatPerUnit,
            protein: proteinPerUnit,
            portionUnit: portionUnit
        )
        
        // キャッシュから既存のFoodMasterを検索
        if let existingFoodMaster = existingFoodMasterCache[uniqueKey] {
            foodMaster = existingFoodMaster
            logger.debug("既存のFoodMasterが見つかりました: \(existingFoodMaster.productName), \(existingFoodMaster.brandName), calories=\(existingFoodMaster.calories), carbs=\(existingFoodMaster.carbohydrates), fat=\(existingFoodMaster.fat), protein=\(existingFoodMaster.protein), portionUnit=\(existingFoodMaster.portionUnit), portion=\(existingFoodMaster.portion)")
        } else {
            // 新しいFoodMasterを作成
            foodMaster = FoodMaster(
              brandName: columns[brandNameIndex],
              productName: columns[productNameIndex],
              calories: caloriesPerUnit,
              carbohydrates: carbsPerUnit,
              fat: fatPerUnit,
              protein: proteinPerUnit,
              portionUnit: portionUnit,
              portion: 1.0  // 1単位あたりに正規化
            )
            
            // キャッシュに追加
            existingFoodMasterCache[uniqueKey] = foodMaster
            foodMastersToInsert.append(foodMaster)  // バッチ挿入用配列に追加
            
            logger.debug(
              "新しいFoodMasterを作成: \(foodMaster.productName), \(foodMaster.brandName), CSV値=[calories:\(cleanedCalories), carbs:\(cleanedCarbs), fat:\(cleanedFat), protein:\(cleanedProtein), portionUnit:\(portionUnit), portionAmount:\(cleanedPortionAmount)], 設定値=[calories:\(foodMaster.calories), carbs:\(foodMaster.carbohydrates), fat:\(foodMaster.fat), protein:\(foodMaster.protein), portionUnit:\(foodMaster.portionUnit), portion:\(foodMaster.portion)]"
            )
        }

        // LogItemの作成
        let logItem = LogItem(
          timestamp: date,
          mealType: mealType,
          numberOfServings: portionAmount,  // CSVのportion_amountを使用
          foodMaster: foodMaster  // FoodMasterを関連付ける
        )
        logItemsToInsert.append(logItem)  // バッチ挿入用配列に追加
        successCount += 1
      } catch {
        errorCount += 1
        logger.error("行\(index + 2)の処理中にエラー: \(error.localizedDescription)")
      }
    }

    // バッチ挿入を実行
    if !foodMastersToInsert.isEmpty {
      for foodMaster in foodMastersToInsert {
        context.insert(foodMaster)
      }
    }
    if !logItemsToInsert.isEmpty {
      for logItem in logItemsToInsert {
        context.insert(logItem)
      }
    }

    let elapsedTime = Date().timeIntervalSince(startTime)
    logger.info(
      "CSVインポート完了: 成功=\(successCount)行, 失敗=\(errorCount)行, 処理時間=\(String(format: "%.2f", elapsedTime))秒"
    )

    // インポートされた行数を返す
    return successCount
  }
}
