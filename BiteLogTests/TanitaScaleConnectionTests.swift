import Foundation
import Testing

@testable import BiteLog

/// CoreBluetooth に触らずに確かめられる部分だけ。
/// 接続そのものは実機が要るので、ここでは識別子の扱いを見る。
struct TanitaScaleConnectionTests {

  private static func emptyDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "TanitaScaleConnectionTests-\(UUID().uuidString)")!
    defaults.removePersistentDomain(forName: defaults.description)
    return defaults
  }

  @Test func 識別子は最初に作って以降は使い回す() {
    let defaults = Self.emptyDefaults()

    let first = TanitaScaleConnection.storedAppIdentifier(defaults: defaults, key: "id")
    let second = TanitaScaleConnection.storedAppIdentifier(defaults: defaults, key: "id")

    // 体重計側が識別子を覚えている可能性があるので、接続ごとに変えてはいけない
    #expect(first == second)
    #expect(UUID(uuidString: first) != nil)
  }

  @Test func 保存済みの識別子があればそれを返す() {
    let defaults = Self.emptyDefaults()
    let stored = "00000000-0000-4000-8000-000000000000"
    defaults.set(stored, forKey: "id")

    #expect(TanitaScaleConnection.storedAppIdentifier(defaults: defaults, key: "id") == stored)
  }
}
