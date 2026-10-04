import Foundation

enum TanitaSessionError: Error, Equatable {
  /// 待っているコマンドと違う応答が来た
  case unexpectedResponse(expected: UInt16, actual: UInt16)
  /// 体重計がエラーを返した。応答の先頭1バイトが状態で、0 以外は受け付けられていない
  case rejected(command: UInt16, status: UInt8)
  /// 名乗った識別子が体重計に登録されていない。体重計の表示は Err UUID になる
  case unregisteredIdentifier(code: UInt8)
  /// 登録を断られた。応答の2バイト目が 0 以外。名乗りの応答と同じ並びと見ている
  case registrationRefused(code: UInt8)
  case measurementDecodeFailed
  case profileDecodeFailed
}

/// 体重計との1回のやり取りの進行。
///
/// 接続したら名乗り、時計を合わせ、測定を待ち、今測ったぶんを引き取って終わる。
/// 登録のときは名乗らずに始め、読んだ個人データを書き戻してから識別子を登録し、そのまま測定へ進む。
/// 公式アプリが登録するときの手順をなぞっている。
/// CoreBluetooth に依存しないので、実機に触らずに手順を検証できる。
struct TanitaSession {
  enum Event {
    case connected
    case received(TanitaMessage)
  }

  enum Action: Equatable {
    case send(TanitaMessage)
    /// 識別子を体重計が受け付けた。以降はこの識別子で名乗れば通る
    case registered
    case deliver(TanitaBodyMeasurement)
    case finished
    case failed(TanitaSessionError)
  }

  /// 体重計に自分を名乗る識別子。公式アプリは36文字のUUID文字列を送っている。
  /// 体重計側が値を覚えている可能性があるので、端末ごとに固定したものを渡す。
  let appIdentifier: String
  /// 名乗る代わりに識別子を登録する
  let isRegistering: Bool
  let timeZone: TimeZone
  private let now: () -> Date

  private var awaiting: TanitaCommand?

  init(
    appIdentifier: String,
    timeZone: TimeZone = .current,
    now: @escaping () -> Date = Date.init
  ) {
    self.appIdentifier = appIdentifier
    self.isRegistering = false
    self.timeZone = timeZone
    self.now = now
  }

  /// ペアリングモードの体重計に `identifier` を登録する
  init(
    registering identifier: String,
    timeZone: TimeZone = .current,
    now: @escaping () -> Date = Date.init
  ) {
    self.appIdentifier = identifier
    self.isRegistering = true
    self.timeZone = timeZone
    self.now = now
  }

  mutating func handle(_ event: Event) -> [Action] {
    switch event {
    case .connected:
      // ペアリングモードの体重計はまだこの識別子を知らないので、名乗っても通らない
      guard isRegistering else {
        return [send(.identify, TanitaMessage(.identify, text: appIdentifier))]
      }
      return [setClock()]

    case .received(let message):
      guard let expected = awaiting?.responseCommand, message.command == expected else {
        return [
          .failed(
            .unexpectedResponse(expected: awaiting?.responseCommand ?? 0, actual: message.command))
        ]
      }
      // 応答の先頭1バイトは状態。0 以外はこちらの要求が通っていない
      if let status = message.payload.first, status != 0 {
        return [.failed(.rejected(command: message.command, status: status))]
      }
      return advance(message)
    }
  }

  private mutating func advance(_ message: TanitaMessage) -> [Action] {
    switch awaiting {
    case .identify:
      // 名乗りの応答は2バイト。登録済みなら 00 00 で、2バイト目が 0 以外だと
      // その識別子を知らないという意味になる（体重計の表示は Err UUID）
      if let code = message.payload.dropFirst().first, code != 0 {
        return [.failed(.unregisteredIdentifier(code: code))]
      }
      return [setClock()]

    case .setClock:
      return [send(.deviceInfo, TanitaMessage(.deviceInfo))]

    case .deviceInfo:
      return [send(.readProfile, TanitaMessage(.readProfile))]

    case .readProfile:
      // 測定のときは個人データの書き込みを飛ばしている。身長や生年月日は体重計が既に持っており、
      // 飛ばしても測定まで通った
      guard isRegistering else { return [startMeasurement()] }
      // 登録のときは公式アプリと同じく書き込んでから識別子を送る。値を変えたいわけではないので、
      // 読んだものをそのまま書き戻す。値を BiteLog から決めるのは #155
      guard let stored = try? TanitaField.parse(Data(message.payload.dropFirst())) else {
        return [.failed(.profileDecodeFailed)]
      }
      let fields = Self.profileForRegistration(stored, clock: TanitaField.clock(at: now(), timeZone: timeZone))
      let payload = fields.reduce(into: Data([0x00])) { $0.append($1.encoded) }
      return [send(.writeProfile, TanitaMessage(command: TanitaCommand.writeProfile.rawValue, payload: payload))]

    case .writeProfile:
      return [send(.register, TanitaMessage(.register, text: appIdentifier))]

    case .register:
      if let code = message.payload.dropFirst().first, code != 0 {
        return [.failed(.registrationRefused(code: code))]
      }
      // 公式アプリも登録の直後にそのまま測定へ進んでいる
      return [.registered, startMeasurement()]

    case .startMeasurement:
      // ここまでの応答は速いが、これだけは人が乗って測り終わるまで返ってこない
      return [send(.measurementCount, TanitaMessage(.measurementCount))]

    case .measurementCount:
      // 引き取るのは今測った1件だけ。番号は新しいほうから数え、01 が今測ったものになる。
      // 残りは体重計だけで測ったもので、日付も時刻も 0 になっている。何日の測定か分からず、
      // 読むと状態 05 が返ったあと体重計が Err を出して終了に応えなくなり、次も同じところで止まる。
      // 終了を送れば、読んでいないものも体重計の中では送信済みになる
      guard message.payload.last ?? 0 > 0 else { return [send(.finish, TanitaMessage(.finish))] }
      return [send(.readMeasurement, TanitaMessage(.readMeasurement, argument: 1))]

    case .readMeasurement:
      guard
        let measurement = try? TanitaBodyMeasurement(
          measurementPayload: message.payload, timeZone: timeZone)
      else {
        return [.failed(.measurementDecodeFailed)]
      }
      return [.deliver(measurement), send(.finish, TanitaMessage(.finish))]

    case .finish:
      awaiting = nil
      return [.finished]

    default:
      return [.failed(.unexpectedResponse(expected: 0, actual: message.command))]
    }
  }

  /// 体重計から読んだ個人データを、公式アプリが登録のときに書く形へ組み直す。
  ///
  /// - 日付と時刻は書き込む時点のものに差し替える
  /// - 呼び名は `6A3D`（5バイト）のほかに `7E22`（長さ10 + 10バイト）にも入れる
  /// - 末尾に `7E2F 01 01` を足す。ふだんの測定では `01 00` で、意味は確定していない
  static func profileForRegistration(_ stored: [TanitaField], clock: [TanitaField]) -> [TanitaField] {
    var fields: [TanitaField] = []
    for field in stored {
      switch field.tag {
      case TanitaTag.date:
        fields += clock.filter { $0.tag == TanitaTag.date }
      case TanitaTag.time:
        fields += clock.filter { $0.tag == TanitaTag.time }
      case TanitaTag.nickname:
        fields.append(field)
        var name = Data(field.value.prefix { $0 != 0 }.prefix(10))
        name.append(Data(repeating: 0, count: 10 - name.count))
        fields.append(TanitaField(tag: TanitaTag.longNickname, value: Data([0x0A]) + name))
      default:
        fields.append(field)
      }
    }
    fields.append(TanitaField(tag: TanitaTag.profileFlags, value: Data([0x01, 0x01])))
    return fields
  }

  private mutating func setClock() -> Action {
    let clock = TanitaField.clock(at: now(), timeZone: timeZone)
    return send(.setClock, TanitaMessage(.setClock, fields: clock))
  }

  private mutating func startMeasurement() -> Action {
    send(.startMeasurement, TanitaMessage(.startMeasurement))
  }

  private mutating func send(_ command: TanitaCommand, _ message: TanitaMessage) -> Action {
    awaiting = command
    return .send(message)
  }
}
