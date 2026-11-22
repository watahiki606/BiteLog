import Foundation
import Testing

/// ソースで使っている文言に、日本語の訳が揃っているか。
///
/// 訳が無いキーは、日本語の画面でも英語のキーがそのまま出る。画面を開くまで気づけないので、ソースから拾って確かめる。
struct JapaneseLocalizationTests {

  /// 日本語でも同じ表記でよいもの
  private static let sameInJapanese: Set<String> = ["0", "g", "kcal"]

  @Test func ソースで使う文言はすべて日本語の訳を持つ() throws {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("BiteLog")
    let path = try #require(Bundle.main.path(forResource: "ja", ofType: "lproj"))
    let japanese = try #require(Bundle(path: path))
    let pattern = try Regex(#"NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)""#)

    var keys = Set<String>()
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    for case let url as URL in files where url.pathExtension == "swift" {
      let source = try String(contentsOf: url, encoding: .utf8)
      for match in source.matches(of: pattern) {
        if let key = match.output[1].substring { keys.insert(String(key)) }
      }
    }
    #expect(!keys.isEmpty)

    let missing = keys.subtracting(Self.sameInJapanese).filter { key in
      // Swift のリテラルのエスケープを戻してから引く
      let unescaped = key.replacingOccurrences(of: #"\""#, with: "\"")
      return japanese.localizedString(forKey: unescaped, value: "\u{0}missing", table: nil) == "\u{0}missing"
    }
    #expect(missing.isEmpty, "日本語の訳が無い: \(missing.sorted())")
  }
}
