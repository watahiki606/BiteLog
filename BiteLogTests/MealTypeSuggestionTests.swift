import Foundation
import Testing

@testable import BiteLog

struct MealTypeSuggestionTests {
  private let calendar = Calendar(identifier: .gregorian)

  private func at(hour: Int, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: hour, minute: minute))!
  }

  @Test(arguments: [
    (4, MealType.breakfast), (9, .breakfast),
    (10, .lunch), (14, .lunch),
    (15, .snack), (16, .snack),
    (17, .dinner), (23, .dinner), (0, .dinner), (3, .dinner),
  ])
  func 時刻にいちばん近い食事を選ぶ(hour: Int, expected: MealType) {
    #expect(MealType.suggested(at: at(hour: hour), calendar: calendar) == expected)
  }

  @Test func 境界の直前は前の食事のまま() {
    #expect(MealType.suggested(at: at(hour: 9, minute: 59), calendar: calendar) == .breakfast)
  }
}

struct MealTypeDecodingTests {
  private func decode(_ raw: String) throws -> MealType {
    try JSONDecoder().decode(MealType.self, from: Data("\"\(raw)\"".utf8))
  }

  @Test func 廃止したその他は間食として読む() throws {
    #expect(try decode("Other") == .snack)
  }

  @Test func 知らない値は読めないことを伝える() {
    #expect(throws: DecodingError.self) { try decode("Brunch") }
  }

  @Test func 選択肢にその他は出さない() {
    #expect(MealType.allCases == [.breakfast, .lunch, .dinner, .snack])
  }
}
