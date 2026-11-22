import Foundation
import Testing

@testable import BiteLog

/// `shared/nutrients.json` と、そこから生成した Swift と Nutrients.strings が食い違っていないか。
///
/// JSON を直して生成し忘れると、Worker と web は新しい一覧で動き、アプリだけ古い一覧のまま出てしまう。
/// CI でテストを回していないので、PR の確認でこのテストを流して気づけるようにする。
struct NutrientDefinitionsTests {

  private struct Entry: Decodable {
    let id: String
    let column: String
    let unit: String
    let fractionDigits: Int
    let group: String
    let core: Bool
    let label: String
    let names: [String: String]
    let shortNames: [String: String]
  }

  /// アプリのバンドルに入らないリポジトリのファイルを、このテストのソースの場所から読む
  private static func entries() throws -> [Entry] {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("shared/nutrients.json")
    return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
  }

  @Test func 生成した一覧は定義ファイルと同じ並びの栄養素を持つ() throws {
    let ids = try Self.entries().map(\.id)

    #expect(NutrientID.allCases.map(\.rawValue) == ids)
  }

  @Test func 生成した一覧は定義ファイルと同じ属性を持つ() throws {
    for entry in try Self.entries() {
      let definition = try #require(NutrientID(rawValue: entry.id)).definition

      #expect(definition.column == entry.column, "\(entry.id)")
      #expect(definition.unit == entry.unit, "\(entry.id)")
      #expect(definition.fractionDigits == entry.fractionDigits, "\(entry.id)")
      #expect(definition.group.rawValue == entry.group, "\(entry.id)")
      #expect(definition.core == entry.core, "\(entry.id)")
      #expect(definition.label.rawValue == entry.label, "\(entry.id)")
    }
  }

  @Test(arguments: ["ja", "en"])
  func 表示名は定義ファイルと同じ(language: String) throws {
    let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))

    for entry in try Self.entries() {
      let name = bundle.localizedString(forKey: "\(entry.id).name", value: nil, table: "Nutrients")
      let shortName = bundle.localizedString(forKey: "\(entry.id).shortName", value: nil, table: "Nutrients")

      #expect(name == entry.names[language], "\(entry.id)")
      #expect(shortName == entry.shortNames[language], "\(entry.id)")
    }
  }

  @Test func 必須の栄養素は食品のJSONのキーとして揃っている() throws {
    // id は API の JSON のキーでもある。DTO のプロパティ名とずれると、定義から組み立てた読み書きが空振りする
    let food = FoodMasterDTO(
      id: UUID(), brandName: "", productName: "", calories: 0, dietaryFiber: 0, netCarbs: 0,
      fat: 0, protein: 0, portionSize: 1, portionUnit: "", uniqueKey: "", usageCount: 0,
      lastNumberOfServings: 1)
    let json = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(food)) as? [String: Any])

    for id in NutrientID.allCases where id.definition.core {
      #expect(json[id.rawValue] is NSNumber, "\(id.rawValue)")
    }
  }
}
