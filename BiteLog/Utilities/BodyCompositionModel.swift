import Combine
import Foundation

/// 記録の画面が体組成計を自動で探し始めてよいかを決める。
///
/// 自動で探すと、記録をつけたいだけで開いたときにも Bluetooth の接続が走る。
/// 「その日まだ測っていない今日」に1回だけ、という線を引く。
enum ScaleAutoStart {
  struct Conditions: Equatable {
    /// 見ているのが今日か。過去の日を開いて測り始めるのは筋が通らない
    var isToday: Bool
    /// この端末が体組成計に登録できているか
    var isPaired: Bool
    /// その暦日の測定がもうサーバーにあるか
    var alreadyMeasured: Bool
    /// もう探している途中か
    var isRunning: Bool
    /// その暦日について自動で1回試したか。空振りを繰り返さないための歯止め
    var attemptedToday: Bool
  }

  static func shouldStart(_ conditions: Conditions) -> Bool {
    conditions.isToday
      && conditions.isPaired
      && !conditions.alreadyMeasured
      && !conditions.isRunning
      && !conditions.attemptedToday
  }
}

/// 記録の画面に置く体組成カードの状態。
///
/// 測定を取り込む道筋は設定の奥にもあるが、毎日やることなので記録の画面から始められる。
/// 自動で探して、乗れば結果がその場に出る。乗らなければ黙って終わる。
@MainActor
final class BodyCompositionModel: ObservableObject {
  /// いま何をしているか。失敗は持たない。自動で探して空振りしたことを
  /// 画面に出すと、測るつもりが無い日に毎回エラーを見せることになる。
  enum Activity: Equatable {
    case idle
    case searching
    case waitingForStep
    case reading
  }

  /// 見ている日の測定。同じ日に複数回測ったときは最後のもの
  @Published private(set) var dayMeasurement: BodyMeasurementDTO?
  @Published private(set) var activity: Activity = .idle
  /// 体組成計を登録しているか。登録していない人にはカードを出さない
  @Published private(set) var isPaired: Bool
  /// 見ているのが今日か。過去の日に「測る」を出しても、体組成計は今の時刻を刻む
  @Published private(set) var isToday = false
  /// 手で始めたときだけ出す文面。自動のときは入れない
  @Published private(set) var manualFailure: String?

  private let connection: ScaleSession
  private let api: BodyMeasurementStore
  private let defaults: UserDefaults
  private let timeZone: TimeZone
  private var cancellables: Set<AnyCancellable> = []
  /// 自動で試した暦日。1日1回に抑える
  private var attemptedDays: Set<String> = []
  /// 手で始めたかどうか。空振りを伝えるかどうかがここで変わる
  private var startedByHand = false
  private var day: String?

  init(
    connection: ScaleSession = TanitaScaleConnection(),
    api: BodyMeasurementStore = APIClient.shared,
    defaults: UserDefaults = .standard,
    timeZone: TimeZone = .current
  ) {
    self.connection = connection
    self.api = api
    self.defaults = defaults
    self.timeZone = timeZone
    self.isPaired = TanitaScaleConnection.isPaired(defaults: defaults)

    connection.onMeasurement = { [weak self] measurement in
      Task { await self?.store(measurement) }
    }
    connection.stateStream
      .sink { [weak self] state in MainActor.assumeIsolated { self?.apply(state) } }
      .store(in: &cancellables)
  }

  /// カードを出すか。
  ///
  /// その日の測定があれば、登録していない人にも出す。
  /// 値が無いときに出す意味があるのは「これから測れる今日」だけ。
  var isVisible: Bool { dayMeasurement != nil || (isPaired && isToday) }

  /// いまから測れるか。過去の日には出さない
  var canMeasure: Bool { isPaired && isToday }

  var isRunning: Bool { activity != .idle }

  /// 見ている日が変わったときに呼ぶ。測定を取り直し、条件が揃えば自動で探し始める。
  func load(date: Date, now: Date = Date()) async {
    let day = BodyMeasurementDTO.formatDay(date, timeZone: timeZone)
    // 別の日へ移ったのに探し続けると、返ってきた結果が画面と噛み合わない
    if let previous = self.day, previous != day, isRunning { connection.stop() }
    self.day = day
    isPaired = TanitaScaleConnection.isPaired(defaults: defaults)
    isToday = day == BodyMeasurementDTO.formatDay(now, timeZone: timeZone)
    await reload(day: day)

    let conditions = ScaleAutoStart.Conditions(
      isToday: isToday,
      isPaired: isPaired,
      alreadyMeasured: dayMeasurement != nil,
      isRunning: isRunning,
      attemptedToday: attemptedDays.contains(day)
    )
    guard ScaleAutoStart.shouldStart(conditions) else { return }
    attemptedDays.insert(day)
    startedByHand = false
    connection.start(timeouts: .automatic)
  }

  /// カードの「測る」から始める。自動で空振りしたあとでも押せる
  func measureByHand() {
    guard canMeasure, !isRunning else { return }
    manualFailure = nil
    startedByHand = true
    connection.start(timeouts: .manual)
  }

  func stop() {
    connection.stop()
  }

  // MARK: - 内側

  private func reload(day: String) async {
    do {
      // 直近の数件で足りる。見ているのはその日の1件だけ
      let measurements = try await api.fetchBodyMeasurements(limit: 20)
      dayMeasurement = BodyMeasurementDTO.latestByDay(measurements)[day]
    } catch {
      // 取れなくてもカードが消えるだけ。記録の画面の本題ではないので何も言わない
    }
  }

  private func apply(_ state: TanitaScaleConnection.State) {
    switch state {
    case .scanning, .connecting, .preparing:
      activity = .searching
    case .waitingForStep:
      activity = .waitingForStep
    case .reading:
      activity = .reading
    case .idle, .finished:
      activity = .idle
    case .failed(let message):
      activity = .idle
      // 自動で探して見つからなかっただけのことをエラーとして出さない
      manualFailure = startedByHand ? message : nil
    }
  }

  private func store(_ measurement: TanitaBodyMeasurement) async {
    guard let dto = BodyMeasurementCreateDTO(measurement, timeZone: timeZone) else { return }
    do {
      try await api.createBodyMeasurement(dto)
    } catch APIError.serverError(409) {
      // 体重計は引き取り済みのぶんも送ってくる。既にある測定は数えない
    } catch {
      if startedByHand { manualFailure = error.localizedDescription }
    }
    isPaired = TanitaScaleConnection.isPaired(defaults: defaults)
    if let day { await reload(day: day) }
  }
}

/// 体組成計とのやり取り。実物は `TanitaScaleConnection` で、
/// CoreBluetooth に触らずに進行を確かめられるように切っている。
protocol ScaleSession: AnyObject {
  var stateStream: AnyPublisher<TanitaScaleConnection.State, Never> { get }
  var onMeasurement: ((TanitaBodyMeasurement) -> Void)? { get set }
  func start(timeouts: TanitaScaleConnection.Timeouts)
  func stop()
}

extension TanitaScaleConnection: ScaleSession {
  var stateStream: AnyPublisher<State, Never> { $state.eraseToAnyPublisher() }
}

/// 測定の出し入れ。実物は `APIClient` で、差し替えられるように切っている。
protocol BodyMeasurementStore {
  func fetchBodyMeasurements(limit: Int) async throws -> [BodyMeasurementDTO]
  func createBodyMeasurement(_ dto: BodyMeasurementCreateDTO) async throws
}

extension APIClient: BodyMeasurementStore {}
