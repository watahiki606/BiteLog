import Combine
import Foundation

/// 記録の画面が体組成計を自動で探し始めてよいかを決める。
///
/// 探すのは2つの場面だけ。アプリを開いて記録の画面が出たときと、
/// 新しい測定が入った直後。時計で間隔を計ったりはしない。
enum ScaleAutoStart {
  struct Conditions: Equatable {
    /// 見ているのが今日か。過去の日を開いて測り始めるのは筋が通らない
    var isToday: Bool
    /// この端末が体組成計に登録できているか
    var isPaired: Bool
    /// もう探している途中か
    var isRunning: Bool
    /// アプリが前面に戻ってから、もう自動で試したか。
    /// タブを行き来するたびに探し始めないための歯止め
    var attemptedSinceForeground: Bool
  }

  static func shouldStart(_ conditions: Conditions) -> Bool {
    conditions.isToday
      && conditions.isPaired
      && !conditions.isRunning
      && !conditions.attemptedSinceForeground
  }

  /// 測定を受け取ったあと、続けてもう一度待つか。
  ///
  /// 体重計には連続で数回乗ることがある。1回受け取って終わると、2回目以降は
  /// 本体に溜まるだけでその場に出てこない。乗ったらすぐ結果が出る形にならない。
  ///
  /// 待ち直すのは新しく保存できたときだけ。体重計は引き取り済みのぶんも送ってくるので、
  /// 同じ測定が返ってくるだけのときに待ち直しても、何も増えないまま繰り返す。
  static func shouldRearm(savedNewMeasurement: Bool, isToday: Bool) -> Bool {
    savedNewMeasurement && isToday
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

  /// カードに出すもの。見ている日の測定と、前日との差と、ならした傾向
  @Published private(set) var summary: BodyCardSummary.Summary?
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
  private let calendar: Calendar
  private var cancellables: Set<AnyCancellable> = []
  /// アプリが前面に戻ってから自動で試したか
  private var attemptedSinceForeground = false
  /// 新しい測定を保存できた。引き取りが終わったら、続けてもう一度待つ
  private var pendingRearm = false
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
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    self.calendar = calendar
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
  /// 体組成を持っている人には、見ている日に測っていなくても出す。前回の値を出せる。
  /// 1件も持っていない人には、これから測れる今日だけ出す。
  var isVisible: Bool { (summary?.hasAnyData ?? false) || (isPaired && isToday) }

  /// いまから測れるか。過去の日には出さない
  var canMeasure: Bool { isPaired && isToday }

  /// カードの下段に出すものがあるか。
  ///
  /// 過去の日を開くと測る導線が消える。それでも行を作ると、区切り線の下に
  /// 何も無い高さだけが残る。
  var showsAction: Bool { canMeasure || isRunning || manualFailure != nil }

  var isRunning: Bool { activity != .idle }

  /// 見ている日が変わったときに呼ぶ。測定を取り直すだけで、探しはしない。
  ///
  /// 記録を1つ足すたびにこの画面は読み直される。そこで探し始めると、
  /// 食事をつけるたびに Bluetooth の接続が走る。
  func load(date: Date, now: Date = Date()) async {
    let day = BodyMeasurementDTO.formatDay(date, timeZone: timeZone)
    if let previous = self.day, previous != day {
      // 別の日へ移ったのに探し続けると、返ってきた結果が画面と噛み合わない
      if isRunning { connection.stop() }
      attemptedSinceForeground = false
    }
    self.day = day
    isPaired = TanitaScaleConnection.isPaired(defaults: defaults)
    isToday = day == BodyMeasurementDTO.formatDay(now, timeZone: timeZone)
    await reload(day: day)
  }

  /// 記録の画面が出たときに呼ぶ。条件が揃えば自動で探し始める。
  func autoMeasureIfNeeded() {
    let conditions = ScaleAutoStart.Conditions(
      isToday: isToday, isPaired: isPaired, isRunning: isRunning,
      attemptedSinceForeground: attemptedSinceForeground)
    guard ScaleAutoStart.shouldStart(conditions) else { return }
    attemptedSinceForeground = true
    startedByHand = false
    connection.start(timeouts: .automatic)
  }

  /// アプリが前面に戻ったときに呼ぶ。もう一度だけ探す。
  ///
  /// 測ろうとして開いたのかどうかは分からないが、開いたことだけが分かる手がかり。
  /// 朝に乗って夜にまた乗る使い方は、たいていアプリを開き直す。
  func foregrounded() {
    attemptedSinceForeground = false
    autoMeasureIfNeeded()
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

  /// 見ている日を末尾にした直近の範囲を取る。
  ///
  /// その日の1件だけでは足りない。前日との差と、ならした傾向のために
  /// 傾向の窓2つぶんと、前回いつ測ったかを見に行くだけの余裕が要る。
  private func reload(day: String) async {
    let span = BodyCardSummary.trendWindowDays * 2 + 14
    let from = BodyCardSummary.offsetDay(day, by: -(span - 1), calendar: calendar)
    do {
      let measurements = try await api.fetchBodyMeasurements(from: from, to: day)
      summary = BodyCardSummary.make(measurements, day: day, calendar: calendar)
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
      rearmIfNeeded()
    case .failed(let message):
      activity = .idle
      // 自動で探して見つからなかっただけのことをエラーとして出さない
      manualFailure = startedByHand ? message : nil
      pendingRearm = false
    }
  }

  /// 続けて乗るかもしれないので、もう一度待ちに入る。
  ///
  /// 引き取りが終わったあとと、保存が終わったあとの両方から呼ぶ。どちらが先になるかは
  /// 通信と通信の速さ次第で決まらない。印を1つ持たせて、先に揃ったほうで動かす。
  private func rearmIfNeeded() {
    guard ScaleAutoStart.shouldRearm(savedNewMeasurement: pendingRearm, isToday: isToday),
      !isRunning
    else { return }
    pendingRearm = false
    startedByHand = false
    connection.start(timeouts: .automatic)
  }

  private func store(_ measurement: TanitaBodyMeasurement) async {
    guard let dto = BodyMeasurementCreateDTO(measurement, timeZone: timeZone) else { return }
    do {
      try await api.createBodyMeasurement(dto)
      // 新しく入ったので、続けて乗るかもしれない
      pendingRearm = true
    } catch APIError.serverError(409) {
      // 体重計は引き取り済みのぶんも送ってくる。既にある測定は数えない
    } catch {
      if startedByHand { manualFailure = error.localizedDescription }
    }
    isPaired = TanitaScaleConnection.isPaired(defaults: defaults)
    if let day { await reload(day: day) }
    rearmIfNeeded()
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
  func fetchBodyMeasurements(from: String, to: String) async throws -> [BodyMeasurementDTO]
  func createBodyMeasurement(_ dto: BodyMeasurementCreateDTO) async throws
}

extension APIClient: BodyMeasurementStore {}
