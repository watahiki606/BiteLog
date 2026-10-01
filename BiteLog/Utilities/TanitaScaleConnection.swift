import Combine
import CoreBluetooth
import Foundation

/// 体組成計とつないで測定データを受け取る。
///
/// 手順の進行は `TanitaSession` が持っていて、ここは CoreBluetooth との橋渡しだけをする。
/// 体重計は標準の Weight Scale Service を実装していないので、独自サービスの
/// 書き込み用キャラクタリスティックにフレームを書き、通知で応答を受ける。
///
/// 通知の購読は暗号化されたリンクでしか通らない。ボンドしていない端末からは
/// `Encryption is insufficient.` で拒否され、体重計側から切断される。
/// 体重計をペアリングモードにするには、電源が入っていない状態で通信ボタンを3秒以上長押しする。
final class TanitaScaleConnection: NSObject, ObservableObject {
  enum State: Equatable {
    case idle
    /// 体重計を探している。体重計は常時アドバタイズしていないので、起動が必要なことがある
    case scanning
    case connecting
    /// 名乗り、時計合わせ、機器情報の取得
    case preparing
    /// 乗ってもらうのを待っている
    case waitingForStep
    case reading
    case finished
    case failed(String)
  }

  static let serviceUUID = CBUUID(string: "273E5100-6B90-4779-83B8-B8BF1DADAC35")
  /// 書き込み用の候補。実機でどちらが使われるかを確かめて1本に絞る
  static let writeCharacteristicUUIDs = [
    CBUUID(string: "273E5107-6B90-4779-83B8-B8BF1DADAC35"),
    CBUUID(string: "273E5108-6B90-4779-83B8-B8BF1DADAC35"),
  ]
  /// 通知用。応答がどれで返るかは実機で確かめる
  static let notifyCharacteristicUUIDs = [
    CBUUID(string: "273E510D-6B90-4779-83B8-B8BF1DADAC35"),
    CBUUID(string: "273E510E-6B90-4779-83B8-B8BF1DADAC35"),
    CBUUID(string: "273E510F-6B90-4779-83B8-B8BF1DADAC35"),
  ]

  /// どこまで待つか。どちらの段階も、待ち続けると Bluetooth をつないだまま放置になる。
  struct Timeouts: Equatable {
    /// 体重計が見つかるまで待つ時間。常時アドバタイズしていないので、見つからないこともある
    var discovery: TimeInterval
    /// 乗って測り終わるまで待つ時間。応答はここだけ人を待つ
    var measurement: TimeInterval

    /// 設定から手で始めるとき。乗るつもりで画面を開いているので長く待つ
    static let manual = Timeouts(discovery: 30, measurement: 180)
    /// 記録の画面が自動で始めるとき。測る気が無いまま開いていることもあるので短く切る
    static let automatic = Timeouts(discovery: 15, measurement: 60)
  }

  @Published private(set) var state: State = .idle
  /// どこまで進んだかの記録。うまくいかなかったときに、どの段階で切れたかを見るために出す
  @Published private(set) var log: [String] = []
  /// 引き取った測定データ。1回の接続で本体に溜まっている分すべてが流れてくる
  var onMeasurement: ((TanitaBodyMeasurement) -> Void)?

  private var central: CBCentralManager?
  private var peripheral: CBPeripheral?
  private var writeCharacteristic: CBCharacteristic?
  private var subscribedCount = 0
  private var session: TanitaSession?
  private var assembler = TanitaFraming.Assembler()
  /// 書き込みは応答を伴わないため、送れるようになるまで自前で溜める
  private var writeQueue: [Data] = []
  private var timeoutWork: DispatchWorkItem?
  private var timeouts: Timeouts = .manual
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    super.init()
  }

  static let identifierKey = "TanitaAppIdentifier"

  /// 体重計に登録できている識別子。
  ///
  /// 体重計が受け付けたときにだけ保存し、知らないと言われたら消す。
  /// 体重計は登録先を1つしか持たないので、公式アプリで登録し直すとこちらは外れる。
  static func registeredIdentifier(defaults: UserDefaults = .standard) -> String? {
    defaults.string(forKey: identifierKey)
  }

  /// この端末が体組成計に登録できているか。未登録なら探しに行かない
  static func isPaired(defaults: UserDefaults = .standard) -> Bool {
    registeredIdentifier(defaults: defaults) != nil
  }

  /// 登録済みの識別子で名乗り、測定を引き取る
  func start(timeouts: Timeouts = .manual) {
    guard let identifier = Self.registeredIdentifier(defaults: defaults) else {
      beginLog("取り込み")
      fail("体組成計が登録されていません。設定の「体組成計」から登録してください")
      return
    }
    beginLog("取り込み")
    reset(TanitaSession(appIdentifier: identifier), timeouts: timeouts)
    central = CBCentralManager(delegate: self, queue: .main)
  }

  /// ペアリングモードの体重計に、新しく作った識別子を登録する。
  ///
  /// 識別子は端末ごとに作り、体重計が受け付けるまで保存しない。
  /// 途中で失敗したときに、通らない識別子が登録済みとして残らないようにするため。
  func register() {
    beginLog("登録")
    reset(TanitaSession(registering: UUID().uuidString), timeouts: .manual)
    central = CBCentralManager(delegate: self, queue: .main)
  }

  private func reset(_ session: TanitaSession, timeouts: Timeouts) {
    self.timeouts = timeouts
    // 前回の接続の残りを持ち越すと、2回目以降が噛み合わなくなる
    self.session = session
    assembler = TanitaFraming.Assembler()
    writeQueue = []
    writeCharacteristic = nil
    subscribedCount = 0
    peripheral = nil
    state = .scanning
  }

  func stop() {
    timeoutWork?.cancel()
    central?.stopScan()
    if let peripheral { central?.cancelPeripheralConnection(peripheral) }
    state = .idle
  }

  // MARK: - 進行

  private func perform(_ actions: [TanitaSession.Action]) {
    for action in actions {
      switch action {
      case .send(let message):
        send(message)
      case .registered:
        guard let identifier = session?.appIdentifier else { continue }
        defaults.set(identifier, forKey: Self.identifierKey)
        note("登録完了")
      case .deliver(let measurement):
        state = .reading
        onMeasurement?(measurement)
      case .finished:
        timeoutWork?.cancel()
        state = .finished
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
      case .failed(.unregisteredIdentifier(let code)):
        // ほかのアプリが登録し直した。持っていても通らないので、未登録に戻して探すのをやめる
        defaults.removeObject(forKey: Self.identifierKey)
        fail(
          String(
            format: "体組成計の登録が外れています（%02x）。設定の「体組成計」から登録し直してください", code))
      case .failed(.registrationRefused(let code)):
        fail(String(format: "体組成計が登録を受け付けませんでした（%02x）", code))
      case .failed(.rejected(let command, let status)):
        fail(String(format: "体重計が受け付けませんでした（コマンド %04x / 状態 %02x）", command, status))
      case .failed(let error):
        fail("やり取りが噛み合いませんでした: \(error)")
      }
    }
  }

  private func send(_ message: TanitaMessage) {
    if message.command == TanitaCommand.startMeasurement.rawValue {
      state = .waitingForStep
      scheduleTimeout(timeouts.measurement, "測定の応答がありませんでした。体重計に乗ってからもう一度試してください")
    }
    note(String(format: "送信 %04x (%dバイト)", message.command, message.encoded.count))
    writeQueue += TanitaFraming.frames(for: message.encoded)
    drainWriteQueue()
  }

  private func drainWriteQueue() {
    guard let peripheral, let characteristic = writeCharacteristic else { return }
    while !writeQueue.isEmpty,
      peripheral.canSendWriteWithoutResponse || characteristic.properties.contains(.write)
    {
      let frame = writeQueue.removeFirst()
      let type: CBCharacteristicWriteType =
        characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
      peripheral.writeValue(frame, for: characteristic, type: type)
      if type == .withResponse { break }
    }
  }

  /// 段階ごとの待ち時間を仕掛ける。段階は重ならないので1つで足りる。
  private func scheduleTimeout(_ seconds: TimeInterval, _ message: String) {
    timeoutWork?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.fail(message) }
    timeoutWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
  }

  /// いま何をしていたか。切断の原因を切り分けるために失敗の文面へ入れる
  private var phaseName: String {
    switch state {
    case .idle: return "待機中"
    case .scanning: return "探索中"
    case .connecting: return "接続中"
    case .preparing: return "準備中"
    case .waitingForStep: return "測定待ち"
    case .reading: return "受け取り中"
    case .finished: return "完了後"
    case .failed: return "エラー後"
    }
  }

  /// 記録は試行ごとに区切って足していく。空にすると、失敗のあとに
  /// 別のボタンを押した時点で、何が起きたかを見る手段が無くなる
  private func beginLog(_ title: String) {
    note("―― \(title) \(Date().formatted(date: .omitted, time: .standard)) ――")
  }

  private func note(_ line: String) {
    log.append(line)
    // 記録の画面は自動で待ち直すので、アプリを開いている間ずっと溜まり続けないようにする
    if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
  }

  private static let logLimit = 300

  private func fail(_ message: String) {
    note("失敗: \(message)")
    timeoutWork?.cancel()
    state = .failed(message)
    central?.stopScan()
    if let peripheral { central?.cancelPeripheralConnection(peripheral) }
  }
}

// MARK: - CBCentralManagerDelegate

extension TanitaScaleConnection: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      note("探索開始")
      state = .scanning
      central.scanForPeripherals(withServices: [Self.serviceUUID])
      // 見つからないまま探し続けると Bluetooth を使ったまま放置になる
      scheduleTimeout(timeouts.discovery, "体組成計が見つかりませんでした。電源が入っていない状態で通信ボタンを押してから、もう一度試してください")
    case .unauthorized:
      fail("Bluetooth の使用が許可されていません")
    case .poweredOff:
      fail("Bluetooth が切れています")
    default:
      break
    }
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi rssiValue: NSNumber
  ) {
    guard self.peripheral == nil else { return }
    timeoutWork?.cancel()
    note("発見: \(peripheral.name ?? "名前なし") rssi=\(rssiValue)")
    self.peripheral = peripheral
    peripheral.delegate = self
    central.stopScan()
    state = .connecting
    central.connect(peripheral)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    note("接続完了")
    state = .preparing
    peripheral.discoverServices([Self.serviceUUID])
  }

  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    fail("接続できませんでした: \(error?.localizedDescription ?? "原因不明")")
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    // 引き取り終えてこちらから切った場合は成功のまま残す。
    // 失敗してこちらから切った場合も、先に出した理由を切断の文面で上書きしない
    switch state {
    case .finished, .failed: return
    default: break
    }
    fail("通信中に切断されました（\(phaseName)）: \(error?.localizedDescription ?? "理由なし")")
  }
}

// MARK: - CBPeripheralDelegate

extension TanitaScaleConnection: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
      fail("体組成計のサービスが見つかりませんでした")
      return
    }
    peripheral.discoverCharacteristics(nil, for: service)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    let characteristics = service.characteristics ?? []
    writeCharacteristic = characteristics.first {
      Self.writeCharacteristicUUIDs.contains($0.uuid)
    }
    let notifying = characteristics.filter {
      $0.properties.contains(.notify) || $0.properties.contains(.indicate)
    }
    guard writeCharacteristic != nil, !notifying.isEmpty else {
      fail("体組成計のキャラクタリスティックが揃っていません")
      return
    }
    note(
      "特性: 書き込み=\(writeCharacteristic.map { String($0.uuid.uuidString.prefix(8)) } ?? "なし") "
        + "通知=\(notifying.map { String($0.uuid.uuidString.prefix(8)) }.joined(separator: ","))")
    subscribedCount = 0
    for characteristic in notifying {
      peripheral.setNotifyValue(true, for: characteristic)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if let error {
      // ボンドしていないと購読できない。ペアリングモードにしてもらう必要がある
      fail(
        "体組成計とのペアリングが必要です。電源が入っていない状態で通信ボタンを3秒以上長押ししてから、もう一度試してください（\(error.localizedDescription)）"
      )
      return
    }
    subscribedCount += 1
    note("購読成功 \(characteristic.uuid.uuidString.prefix(8))")
    // 購読が1本通れば応答は受け取れる。最初の1本で手順を始める
    guard subscribedCount == 1, let actions = session?.handle(.connected) else { return }
    perform(actions)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard error == nil, let frame = characteristic.value else { return }
    guard let raw = assembler.append(frame) else { return }
    do {
      if raw.count >= 4 {
        let payload = raw.dropFirst(4).dropLast()
        note(
          String(format: "受信 %02x%02x", raw[raw.startIndex + 2], raw[raw.startIndex + 3])
            + " [\(payload.map { String(format: "%02x", $0) }.joined(separator: " "))]")
      }
      let message = try TanitaMessage(decoding: raw)
      perform(session?.handle(.received(message)) ?? [])
    } catch {
      fail("応答を読めませんでした: \(error)")
    }
  }

  func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
    drainWriteQueue()
  }
}
