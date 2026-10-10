import Foundation
import Testing

@testable import BiteLog

/// CoreBluetooth に触らずに確かめられる部分だけ。
/// 接続そのものは実機が要るので、ここでは登録済みかどうかの扱いを見る。
struct TanitaScaleConnectionTests {

  private static func emptyDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "TanitaScaleConnectionTests-\(UUID().uuidString)")!
    defaults.removePersistentDomain(forName: defaults.description)
    return defaults
  }

  @Test func 識別子を持っていなければ未登録() {
    let defaults = Self.emptyDefaults()

    #expect(TanitaScaleConnection.registeredIdentifier(defaults: defaults) == nil)
    #expect(!TanitaScaleConnection.isPaired(defaults: defaults))
  }

  @Test func 識別子を持っていれば登録済み() {
    let defaults = Self.emptyDefaults()
    let stored = "00000000-0000-4000-8000-000000000000"
    defaults.set(stored, forKey: TanitaScaleConnection.identifierKey)

    #expect(TanitaScaleConnection.registeredIdentifier(defaults: defaults) == stored)
    #expect(TanitaScaleConnection.isPaired(defaults: defaults))
  }

  @Test func 未登録のまま始めたら探さずに止める() {
    let connection = TanitaScaleConnection(defaults: Self.emptyDefaults())

    connection.start()

    // 知らない識別子で名乗ると体重計に Err UUID が出るだけなので、探しにも行かない
    guard case .failed = connection.state else {
      Issue.record("止まっていない: \(connection.state)")
      return
    }
  }

  @Test func 個人キーを選んでいなければ1() {
    #expect(TanitaScaleConnection.personalKey(defaults: Self.emptyDefaults()) == 1)
  }

  @Test func 選んだ個人キーを覚えている() {
    let defaults = Self.emptyDefaults()

    TanitaScaleConnection.setPersonalKey(3, defaults: defaults)

    #expect(TanitaScaleConnection.personalKey(defaults: defaults) == 3)
  }

  @Test func 範囲外の個人キーは1として扱う() {
    let defaults = Self.emptyDefaults()
    defaults.set(5, forKey: TanitaScaleConnection.personalKeyKey)

    // 体組成計が持つのは4人分。5番目の枠を読むと断られる
    #expect(TanitaScaleConnection.personalKey(defaults: defaults) == 1)
  }
}
