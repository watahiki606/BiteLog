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
  typealias ProgressHandler = (Double, Int, Int) -> Bool

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
    columns.append(currentColumn.trimmingCharacters(in: .whitespaces))
    return columns
  }

  static func importCSV(
    from url: URL, progressHandler: ProgressHandler? = nil
  ) async throws -> Int {
    let startTime = Date()
    logger.info("CSVインポート開始: \(url.lastPathComponent)")

    let csvString: String
    do {
      csvString = try String(contentsOf: url, encoding: .utf8)
    } catch {
      logger.error("ファイル読み込みエラー: \(error.localizedDescription)")
      throw CSVImportError.invalidData("ファイルの読み込みに失敗しました: \(error.localizedDescription)")
    }

    let rows = csvString.components(separatedBy: .newlines)
    guard !rows.isEmpty else {
      throw CSVImportError.invalidData("CSVファイルが空です")
    }

    let totalRows = rows.count - 1
    logger.info("CSVインポート: 全\(totalRows)行のデータを処理します")

    if let progressHandler, progressHandler(0.0, 0, totalRows) {
      throw CSVImportError.cancelled
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let iso8601 = ISO8601DateFormatter()

    let headers = parseCSVLine(rows[0]).map { $0.lowercased() }
    let dateIndex = headers.firstIndex(of: "date") ?? 0
    let mealTypeIndex = headers.firstIndex(of: "meal_type") ?? 1
    let brandNameIndex = headers.firstIndex(of: "brand_name") ?? 2
    let productNameIndex = headers.firstIndex(of: "product_name") ?? 3
    let caloriesIndex = headers.firstIndex(of: "calories") ?? 4
    let carbsIndex = headers.firstIndex(of: "carbs") ?? 5
    let dietaryFiberIndex = headers.firstIndex(of: "dietary_fiber")
    let fatIndex = headers.firstIndex(of: "fat") ?? 6
    let proteinIndex = headers.firstIndex(of: "protein") ?? 7
    let portionAmountIndex = headers.firstIndex(of: "portion_amount") ?? 8
    let portionUnitIndex = headers.firstIndex(of: "portion_unit") ?? 9

    // 1. 行を解析してユニーク FoodMaster を収集
    struct ParsedRow {
      var date: Date
      var mealType: MealType
      var brandName: String
      var productName: String
      var calories: Double
      var netCarbs: Double
      var dietaryFiber: Double
      var fat: Double
      var protein: Double
      var portionAmount: Double
      var portionUnit: String
      var uniqueKey: String
    }

    var parsedRows: [ParsedRow] = []
    var uniqueFoodMasters: [String: (brandName: String, productName: String, calories: Double,
                                     netCarbs: Double, dietaryFiber: Double, fat: Double,
                                     protein: Double, portionSize: Double, portionUnit: String)] = [:]

    for (index, row) in rows.dropFirst().enumerated() where !row.isEmpty {
      if let progressHandler, index % 10 == 0 {
        let progress = Double(index + 1) / Double(totalRows)
        if progressHandler(progress * 0.5, index + 1, totalRows) {
          throw CSVImportError.cancelled
        }
      }

      let columns = parseCSVLine(row)
      guard columns.count >= 9 else { continue }
      guard let date = dateFormatter.date(from: columns[dateIndex]) else { continue }
      guard let mealType = MealType(rawValue: columns[mealTypeIndex]) else { continue }

      func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: ",", with: "")
      }

      let calories = Double(clean(columns[caloriesIndex])) ?? 0
      let carbs = Double(clean(columns[carbsIndex])) ?? 0
      let fiber: Double = {
        if let fi = dietaryFiberIndex, fi < columns.count { return Double(clean(columns[fi])) ?? 0 }
        return 0
      }()
      let netCarbs = max(0, carbs - fiber)
      let fat = Double(clean(columns[fatIndex])) ?? 0
      let protein = Double(clean(columns[proteinIndex])) ?? 0
      let portionAmount = Double(clean(columns[portionAmountIndex])) ?? 1.0
      let portionUnit = columns[portionUnitIndex]
      let brandName = columns[brandNameIndex]
      let productName = columns[productNameIndex]
      let uniqueKey = FoodMasterDTO.createUniqueKey(
        brandName: brandName, productName: productName, portionUnit: portionUnit)

      if uniqueFoodMasters[uniqueKey] == nil {
        uniqueFoodMasters[uniqueKey] = (brandName, productName, calories, netCarbs, fiber,
                                        fat, protein, portionAmount, portionUnit)
      }
      parsedRows.append(ParsedRow(
        date: date, mealType: mealType, brandName: brandName, productName: productName,
        calories: calories, netCarbs: netCarbs, dietaryFiber: fiber, fat: fat, protein: protein,
        portionAmount: portionAmount, portionUnit: portionUnit, uniqueKey: uniqueKey))
    }

    // 2. FoodMaster を作成（または既存を取得）
    var foodMasterMap: [String: FoodMasterDTO] = [:]
    for (uniqueKey, fm) in uniqueFoodMasters {
      let dto = FoodMasterCreateDTO(
        id: UUID().uuidString,
        brandName: fm.brandName,
        productName: fm.productName,
        calories: fm.calories,
        dietaryFiber: fm.dietaryFiber,
        netCarbs: fm.netCarbs,
        fat: fm.fat,
        protein: fm.protein,
        portionSize: fm.portionSize,
        portionUnit: fm.portionUnit,
        uniqueKey: uniqueKey
      )
      do {
        let created = try await APIClient.shared.createFoodMaster(dto)
        foodMasterMap[uniqueKey] = created
      } catch {
        logger.error("FoodMaster作成エラー \(uniqueKey): \(error.localizedDescription)")
      }
    }

    // 3. LogItem をバッチ作成
    let chunkSize = 50
    var allLogItemDTOs: [LogItemCreateDTO] = []
    for pr in parsedRows {
      guard let fm = foodMasterMap[pr.uniqueKey] else { continue }
      let logDate = dateFormatter.string(from: pr.date)
      let dto = LogItemCreateDTO(
        id: UUID().uuidString,
        timestamp: iso8601.string(from: pr.date),
        logDate: logDate,
        mealType: pr.mealType.rawValue,
        numberOfServings: pr.portionAmount,
        foodMasterId: fm.id.uuidString,
        nutritionSnapshot: NutritionSnapshot.from(fm)
      )
      allLogItemDTOs.append(dto)
    }

    var successCount = 0
    for chunk in stride(from: 0, to: allLogItemDTOs.count, by: chunkSize).map({
      Array(allLogItemDTOs[$0..<min($0 + chunkSize, allLogItemDTOs.count)])
    }) {
      do {
        let result = try await APIClient.shared.batchCreateLogItems(chunk)
        successCount += result.created
      } catch {
        logger.error("バッチ作成エラー: \(error.localizedDescription)")
      }
    }

    let elapsed = Date().timeIntervalSince(startTime)
    logger.info("CSVインポート完了: 成功=\(successCount)行, 処理時間=\(String(format: "%.2f", elapsed))秒")
    return successCount
  }
}
