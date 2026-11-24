import Foundation
import Testing

@testable import BiteLog

/// 統計で栄養素を押したときの説明と出典
struct NutrientInfoTests {

  /// 言語ごとの NutrientInfo.strings の中身
  private static func table(_ language: String) throws -> [String: String] {
    let bundle = Bundle(for: BundleToken.self)
    let url = try #require(
      bundle.url(forResource: "NutrientInfo", withExtension: "strings", subdirectory: nil, localization: language)
        ?? Bundle.main.url(forResource: "NutrientInfo", withExtension: "strings", subdirectory: nil, localization: language))
    return try #require(NSDictionary(contentsOf: url) as? [String: String])
  }

  private static let ids = NutrientID.allCases.map(\.rawValue) + ["carbohydrate"]
  private static let fields = ["role", "shortage", "excess", "foods"]

  @Test(arguments: ["ja", "en"]) func どの栄養素にもはたらきと出典がある(language: String) throws {
    let table = try Self.table(language)
    for id in Self.ids {
      #expect(table["\(id).role"] != nil, "\(language) \(id)")
      #expect(!(NutrientInfo.sources[id] ?? []).isEmpty, "\(id)")
    }
  }

  @Test func 日本語と英語で同じ欄がそろう() throws {
    #expect(Set(try Self.table("ja").keys) == Set(try Self.table("en").keys))
  }

  @Test func 表の鍵は知っている栄養素と欄だけ() throws {
    for key in try Self.table("ja").keys {
      let parts = key.split(separator: ".").map(String.init)
      #expect(parts.count == 2 && Self.ids.contains(parts[0]) && Self.fields.contains(parts[1]), "\(key)")
    }
  }

  @Test func 日本語の説明に括弧を使わない() throws {
    for (key, text) in try Self.table("ja") {
      #expect(!text.contains("（") && !text.contains("("), "\(key)")
    }
  }

  @Test func 表に無い欄は出さない() {
    let info = NutrientInfo(NutrientID.calories)
    #expect(info.role != nil)
    #expect(info.shortage == nil)
    #expect(info.foods == nil)
  }

  @Test func 炭水化物は定義に無いので別の鍵で引く() {
    #expect(NutrientInfo(Nutrient.carbs).id == "carbohydrate")
    #expect(NutrientInfo(Nutrient.fiber).id == "dietaryFiber")
  }
}

private final class BundleToken {}
