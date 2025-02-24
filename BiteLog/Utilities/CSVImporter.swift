import Foundation
import SwiftData

enum CSVImportError: Error {
  case invalidFormat
  case invalidData(String)

  var localizedDescription: String {
    switch self {
    case .invalidFormat:
      return "CSVファイルのフォーマットが正しくありません"
    case .invalidData(let message):
      return "データの読み込みに失敗しました: \(message)"
    }
  }
}

class CSVImporter {
  static func importCSV(from url: URL, context: ModelContext) throws {
    let csvString: String
    do {
      print("CSVファイルの読み込みを開始します: \(url.path)")
      csvString = try String(contentsOf: url, encoding: .utf8)
    } catch {
      print("ファイル読み込みエラー: \(error)")
      throw CSVImportError.invalidData("ファイルの読み込みに失敗しました: \(error.localizedDescription)")
    }

    let rows = csvString.components(separatedBy: .newlines)
    guard !rows.isEmpty else {
      throw CSVImportError.invalidData("CSVファイルが空です")
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    // 2行目以降のデータを処理
    for (index, row) in rows.dropFirst().enumerated() where !row.isEmpty {
      let columns = parseCSVLine(row)
      guard columns.count == 9 else {
        throw CSVImportError.invalidData("\(index + 2)行目: カラム数が不正です (\(columns.count)列)")
      }

      guard let date = dateFormatter.date(from: columns[0]) else {
        throw CSVImportError.invalidData("\(index + 2)行目: 日付の形式が不正です: \(columns[0])")
      }

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

      let item = Item(
        brandName: columns[2],
        productName: columns[3],
        portion: columns[4],
        calories: calories,
        protein: protein,
        fat: fat,
        carbohydrates: carbs,
        mealType: mealType,
        timestamp: date
      )

      context.insert(item)
    }
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
