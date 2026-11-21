import Foundation
import Testing

@testable import BiteLog

/// 食品を作ろうとして、同じブランド名・商品名・単位の食品が既にあったときの 409 の読み取り。
struct FoodMasterExistsErrorTests {

  /// サーバーが 409 で返す本文。`existing` は一覧や作成と同じ形の食品
  private static let conflictBody = Data(
    """
    {
      "error": "A food with the same brand, name and unit already exists",
      "existing": {
        "id": "11111111-1111-1111-1111-111111111111",
        "brandName": "AI",
        "productName": "カレーライス",
        "calories": 650,
        "dietaryFiber": 3,
        "netCarbs": 90,
        "fat": 20,
        "protein": 15,
        "portionSize": 1,
        "portionUnit": "皿",
        "uniqueKey": "AI|カレーライス|皿",
        "usageCount": 0,
        "lastUsedDate": null,
        "lastNumberOfServings": 1
      }
    }
    """.utf8)

  @Test func 本文から登録済みの食品を読み取る() throws {
    let error = try FoodMasterExistsError(conflictBody: Self.conflictBody)

    #expect(error.existing.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    #expect(error.existing.calories == 650)
    #expect(error.existing.portionUnit == "皿")
  }

  @Test func 登録済みであることを伝える文面を持つ() throws {
    // 手入力フォームはエラーの説明をそのままアラートに出す。通信エラーの文面では何を直せばよいか分からない
    let error = try FoodMasterExistsError(conflictBody: Self.conflictBody)

    #expect(
      error.localizedDescription
        == NSLocalizedString(
          "A food with the same brand, name, and unit is already registered.", comment: "Food master conflict"))
  }

  @Test func 作成の本文は重なりを409で知らせるよう求める() throws {
    let json = try Self.encodedJSON(Self.dto.rejectingDuplicate())

    #expect(json["onConflict"] as? String == "reject")
  }

  @Test func 印を付けなければ本文に含めない() throws {
    // 印は作成の API だけが読む。付けない本文は今までと同じ形にしておく
    let json = try Self.encodedJSON(Self.dto)

    #expect(json["onConflict"] == nil)
  }

  private static let dto = FoodMasterCreateDTO(
    id: "11111111-1111-1111-1111-111111111111", brandName: "AI", productName: "カレーライス",
    calories: 650, dietaryFiber: 3, netCarbs: 90, fat: 20, protein: 15,
    portionSize: 1, portionUnit: "皿", uniqueKey: "AI|カレーライス|皿")

  private static func encodedJSON(_ dto: FoodMasterCreateDTO) throws -> [String: Any] {
    let data = try JSONEncoder().encode(dto)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
