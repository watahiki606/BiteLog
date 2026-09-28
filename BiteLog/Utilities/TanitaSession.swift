import Foundation

enum TanitaSessionError: Error, Equatable {
  /// 待っているコマンドと違う応答が来た
  case unexpectedResponse(expected: UInt16, actual: UInt16)
  case measurementDecodeFailed
}

/// 体重計との1回のやり取りの進行。
///
/// 接続したら名乗り、時計を合わせ、測定を待ち、溜まっているデータを引き取って終わる。
/// CoreBluetooth に依存しないので、実機に触らずに手順を検証できる。
struct TanitaSession {
  enum Event {
    case connected
    case received(TanitaMessage)
  }

  enum Action: Equatable {
    case send(TanitaMessage)
    case deliver(TanitaBodyMeasurement)
    case finished
    case failed(TanitaSessionError)
  }

  /// 体重計に自分を名乗る識別子。公式アプリは36文字のUUID文字列を送っている。
  /// 体重計側が値を覚えている可能性があるので、端末ごとに固定したものを渡す。
  let appIdentifier: String
  let timeZone: TimeZone
  private let now: () -> Date

  private var awaiting: TanitaCommand?
  /// 体重計が持っている未送信データの件数
  private var storedCount = 0
  private var receivedCount = 0

  init(
    appIdentifier: String,
    timeZone: TimeZone = .current,
    now: @escaping () -> Date = Date.init
  ) {
    self.appIdentifier = appIdentifier
    self.timeZone = timeZone
    self.now = now
  }

  mutating func handle(_ event: Event) -> [Action] {
    switch event {
    case .connected:
      return [send(.identify, TanitaMessage(.identify, text: appIdentifier))]

    case .received(let message):
      guard let expected = awaiting?.responseCommand, message.command == expected else {
        return [
          .failed(
            .unexpectedResponse(expected: awaiting?.responseCommand ?? 0, actual: message.command))
        ]
      }
      return advance(message)
    }
  }

  private mutating func advance(_ message: TanitaMessage) -> [Action] {
    switch awaiting {
    case .identify:
      let clock = TanitaField.clock(at: now(), timeZone: timeZone)
      return [send(.setClock, TanitaMessage(.setClock, fields: clock))]

    case .setClock:
      return [send(.deviceInfo, TanitaMessage(.deviceInfo))]

    case .deviceInfo:
      return [send(.readProfile, TanitaMessage(.readProfile))]

    case .readProfile:
      // 個人データの書き込みは飛ばしている。身長や生年月日は体重計が既に持っており、
      // こちらから上書きする理由が無い。これで測定に進めるかは実機で確かめる
      return [send(.startMeasurement, TanitaMessage(.startMeasurement))]

    case .startMeasurement:
      // ここまでの応答は速いが、これだけは人が乗って測り終わるまで返ってこない
      return [send(.measurementCount, TanitaMessage(.measurementCount))]

    case .measurementCount:
      storedCount = Int(message.payload.last ?? 0)
      guard storedCount > 0 else { return [send(.finish, TanitaMessage(.finish))] }
      return [send(.readMeasurement, TanitaMessage(.readMeasurement, argument: 1))]

    case .readMeasurement:
      guard
        let measurement = try? TanitaBodyMeasurement(
          measurementPayload: message.payload, timeZone: timeZone)
      else {
        return [.failed(.measurementDecodeFailed)]
      }
      receivedCount += 1
      guard receivedCount < storedCount else {
        return [.deliver(measurement), send(.finish, TanitaMessage(.finish))]
      }
      return [
        .deliver(measurement),
        send(.readMeasurement, TanitaMessage(.readMeasurement, argument: UInt8(receivedCount + 1))),
      ]

    case .finish:
      awaiting = nil
      return [.finished]

    default:
      return [.failed(.unexpectedResponse(expected: 0, actual: message.command))]
    }
  }

  private mutating func send(_ command: TanitaCommand, _ message: TanitaMessage) -> Action {
    awaiting = command
    return .send(message)
  }
}
