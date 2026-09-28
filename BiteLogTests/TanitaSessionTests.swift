import Foundation
import Testing

@testable import BiteLog

/// 体重計とのやり取りの進行。
///
/// 応答のバイト列は仕様どおりに組み立てた架空のもので、実機の測定記録は使っていない。
struct TanitaSessionTests {

  private static let jst = TimeZone(identifier: "Asia/Tokyo")!

  /// 2026-01-01 07:30:00 JST
  private static let fixedNow = Date(timeIntervalSince1970: 1_767_220_200)

  private static func makeSession() -> TanitaSession {
    TanitaSession(
      appIdentifier: "00000000-0000-4000-8000-000000000000",
      timeZone: jst,
      now: { fixedNow }
    )
  }

  /// 引数を1バイト返すだけの応答
  private static func response(to command: TanitaCommand, data: [UInt8] = [0x00, 0x00])
    -> TanitaSession.Event
  {
    .received(TanitaMessage(command: command.responseCommand, payload: Data(data)))
  }

  /// 架空の測定データ1件を積んだ応答
  private static func measurementResponse() -> TanitaSession.Event {
    var payload = Data([0x00, 0x01])
    payload += Data([0x60, 0x21, 0x17, 0x70])  // 体重 60.00kg
    payload += Data([0x60, 0x22, 0x00, 0xC8])  // 体脂肪率 20.0%
    return .received(
      TanitaMessage(command: TanitaCommand.readMeasurement.responseCommand, payload: payload))
  }

  private static func sentCommand(_ actions: [TanitaSession.Action]) -> UInt16? {
    for action in actions {
      if case .send(let message) = action { return message.command }
    }
    return nil
  }

  /// 測定待機の応答が返るところまで進める
  private static func advanceToMeasurement(_ session: inout TanitaSession) {
    _ = session.handle(.connected)
    _ = session.handle(response(to: .identify))
    _ = session.handle(response(to: .setClock))
    _ = session.handle(response(to: .deviceInfo))
    _ = session.handle(response(to: .readProfile))
  }

  @Test func 接続したらアプリ識別子を名乗る() {
    var session = Self.makeSession()

    let actions = session.handle(.connected)

    #expect(actions.count == 1)
    guard case .send(let message) = actions[0] else {
      Issue.record("送信していない")
      return
    }
    #expect(message.command == TanitaCommand.identify.rawValue)
    #expect(String(data: message.payload, encoding: .utf8) == session.appIdentifier)
  }

  @Test func 名乗ったら時計を合わせる() {
    var session = Self.makeSession()
    _ = session.handle(.connected)

    let actions = session.handle(Self.response(to: .identify))

    #expect(Self.sentCommand(actions) == TanitaCommand.setClock.rawValue)
  }

  @Test func 時計合わせは起点からの日数と半秒刻みの時刻を送る() {
    var session = Self.makeSession()
    _ = session.handle(.connected)

    let actions = session.handle(Self.response(to: .identify))

    guard case .send(let message) = actions[0] else {
      Issue.record("送信していない")
      return
    }
    // 0x6A32 に 2026-01-01 = 9497日、0x6A33 に 07:30:00 = 54000 × 0.5秒
    #expect(message.payload == Data([0x6A, 0x32, 0x25, 0x19, 0x6A, 0x33, 0x00, 0xD2, 0xF0]))
  }

  @Test func 時計を合わせたら機器情報を要求する() {
    var session = Self.makeSession()
    _ = session.handle(.connected)
    _ = session.handle(Self.response(to: .identify))

    let actions = session.handle(Self.response(to: .setClock))

    #expect(Self.sentCommand(actions) == TanitaCommand.deviceInfo.rawValue)
  }

  @Test func 機器情報のあとに個人データを読む() {
    var session = Self.makeSession()
    _ = session.handle(.connected)
    _ = session.handle(Self.response(to: .identify))
    _ = session.handle(Self.response(to: .setClock))

    let actions = session.handle(Self.response(to: .deviceInfo))

    #expect(Self.sentCommand(actions) == TanitaCommand.readProfile.rawValue)
  }

  @Test func 個人データを読んだら測定待機に入る() {
    var session = Self.makeSession()
    _ = session.handle(.connected)
    _ = session.handle(Self.response(to: .identify))
    _ = session.handle(Self.response(to: .setClock))
    _ = session.handle(Self.response(to: .deviceInfo))

    let actions = session.handle(Self.response(to: .readProfile))

    #expect(Self.sentCommand(actions) == TanitaCommand.startMeasurement.rawValue)
  }

  @Test func 測定が終わったら件数を要求する() {
    var session = Self.makeSession()
    Self.advanceToMeasurement(&session)

    let actions = session.handle(Self.response(to: .startMeasurement))

    #expect(Self.sentCommand(actions) == TanitaCommand.measurementCount.rawValue)
  }

  @Test func 件数が0なら何も引き取らずに終える() {
    var session = Self.makeSession()
    Self.advanceToMeasurement(&session)
    _ = session.handle(Self.response(to: .startMeasurement))

    let actions = session.handle(Self.response(to: .measurementCount, data: [0x00, 0x00]))

    #expect(Self.sentCommand(actions) == TanitaCommand.finish.rawValue)
    #expect(!actions.contains { if case .deliver = $0 { return true } else { return false } })
  }

  @Test func 測定データを受け取ったら値を渡して終える() {
    var session = Self.makeSession()
    Self.advanceToMeasurement(&session)
    _ = session.handle(Self.response(to: .startMeasurement))
    _ = session.handle(Self.response(to: .measurementCount, data: [0x00, 0x01]))

    let actions = session.handle(Self.measurementResponse())

    guard case .deliver(let measurement) = actions.first else {
      Issue.record("測定値を渡していない")
      return
    }
    #expect(measurement.weightKg == 60.0)
    #expect(measurement.bodyFatPercent == 20.0)
    #expect(Self.sentCommand(actions) == TanitaCommand.finish.rawValue)
  }

  @Test func 溜まっている件数だけ繰り返し引き取る() {
    var session = Self.makeSession()
    Self.advanceToMeasurement(&session)
    _ = session.handle(Self.response(to: .startMeasurement))
    _ = session.handle(Self.response(to: .measurementCount, data: [0x00, 0x02]))

    let first = session.handle(Self.measurementResponse())
    let second = session.handle(Self.measurementResponse())

    // 1件目の後は2件目を要求し、2件目の後で終える
    #expect(Self.sentCommand(first) == TanitaCommand.readMeasurement.rawValue)
    #expect(Self.sentCommand(second) == TanitaCommand.finish.rawValue)
    #expect(second.contains { if case .deliver = $0 { return true } else { return false } })
  }

  @Test func 終了の応答で完了にする() {
    var session = Self.makeSession()
    Self.advanceToMeasurement(&session)
    _ = session.handle(Self.response(to: .startMeasurement))
    _ = session.handle(Self.response(to: .measurementCount, data: [0x00, 0x00]))

    let actions = session.handle(Self.response(to: .finish))

    #expect(actions == [.finished])
  }

  @Test func 待っていない応答が来たら止める() {
    var session = Self.makeSession()
    _ = session.handle(.connected)

    // 名乗った直後に、頼んでいない測定データが返ってきた場合
    let actions = session.handle(Self.measurementResponse())

    #expect(
      actions == [
        .failed(
          .unexpectedResponse(
            expected: TanitaCommand.identify.responseCommand,
            actual: TanitaCommand.readMeasurement.responseCommand))
      ])
  }

  @Test func 測定データが読めなければ止める() {
    var session = Self.makeSession()
    Self.advanceToMeasurement(&session)
    _ = session.handle(Self.response(to: .startMeasurement))
    _ = session.handle(Self.response(to: .measurementCount, data: [0x00, 0x01]))

    // 知らないタグが混ざったデータ
    let broken = TanitaMessage(
      command: TanitaCommand.readMeasurement.responseCommand,
      payload: Data([0x00, 0x01, 0x60, 0x01, 0x00])
    )
    let actions = session.handle(.received(broken))

    #expect(actions == [.failed(.measurementDecodeFailed)])
  }
}
