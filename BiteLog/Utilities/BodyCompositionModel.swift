import Combine
import Foundation

/// 測定を受け取ったあと、続けてもう一度待つかを決める。
///
/// 画面を開いただけでは探さない。記録をつけに来ただけの人の端末で Bluetooth が
/// 動くのは筋が通らないし、いつ探しているのかが本人にも分からない。
/// 探し始めるのは「測る」を押したときだけ。
enum ScaleAutoStart {
  /// 体重計には連続で数回乗ることがある。1回受け取って終わると、2回目以降は
  /// つながないまま測ることになり、日時の無い測定として本体に残るだけで取り込めない。
  /// 押したのは1回でも、乗り終わるまでは待つ。
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
/// 乗れば結果がその場で開く。乗らなければ黙って終わる。
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

  /// カードに出すもの。見ている日の測定と、1件を開いたときに比べる相手を探す範囲
  @Published private(set) var summary: BodyCardSummary.Summary?
  @Published private(set) var activity: Activity = .idle
  /// 体組成計を登録しているか。登録していない人にはカードを出さない
  @Published private(set) var isPaired: Bool
  /// 見ているのが今日か。過去の日に「測る」を出しても、体組成計は今の時刻を刻む
  @Published private(set) var isToday = false
  /// 手で始めたときだけ出す文面。自動のときは入れない
  @Published private(set) var manualFailure: String?
  /// 測り終えたばかりの1件。入ると測定のシートがその1件を見せる。
  ///
  /// 開いている間も続けて乗るのを待つ。もう一度乗れば、開いたまま新しい1件に切り替わる。
  /// 倒すのは `dismissMeasurementSheet()` だけ。
  @Published private(set) var newResult: BodyMeasurementDTO?
  /// 測定のシートを出しているか。測り始めから結果を見終えるまでを1枚で見せる。
  ///
  /// 立つのは「測る」を押したときと、結果が入ったとき。倒れるのは
  /// `dismissMeasurementSheet()` と、見せるものが無くなったとき。
  @Published private(set) var isMeasurementSheetPresented = false

  private let connection: ScaleSession
  private let api: BodyMeasurementStore
  private let defaults: UserDefaults
  private let timeZone: TimeZone
  private let calendar: Calendar
  private var cancellables: Set<AnyCancellable> = []
  /// 新しい測定を保存して取り直した。引き取りが終わったら、結果を開いてもう一度待つ
  private var pendingRearm = false
  /// いま測っている途中か。「測る」で立ち、やめたときに倒れる。
  ///
  /// 保存は通信を待つので、やめたあとに終わることがある。画面を離れてやめたのに、
  /// 離れた先で結果が開いたり、Bluetooth がまた動き出したりしないようにする。
  private var isMeasuring = false
  /// 最後に保存できた測定の時刻。取り直した中から、開く1件を見つける
  private var lastSavedAt: Date?
  /// 手で始めたかどうか。空振りを伝えるかどうかがここで変わる
  private var startedByHand = false
  /// 受け取って保存している最中の件数。
  ///
  /// 体重計は測り終えてから応答する。終わりの合図は保存より先に届くので、
  /// 数えておかないと、保存が終わるまでの間が「何もしていない」に見える。
  private var savesInFlight = 0
  /// 保存中に終わりの合図が来て、状態を `.reading` のまま保っているか
  private var finishedWhileSaving = false
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
      MainActor.assumeIsolated { self?.receive(measurement) }
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

  /// シートの中央に出す段階。測っている間は進み具合、手で始めて失敗したときは失敗
  var stage: MeasurementStage? {
    if let stage = MeasurementStage(activity: activity) { return stage }
    return manualFailure == nil ? nil : .failed
  }

  /// 見ている日が変わったときに呼ぶ。測定を取り直すだけで、探しはしない。
  func load(date: Date, now: Date = Date()) async {
    let day = BodyMeasurementDTO.formatDay(date, timeZone: timeZone)
    // 別の日へ移ったのに探し続けると、返ってきた結果が画面と噛み合わない
    if let previous = self.day, previous != day, isRunning { stop() }
    self.day = day
    isPaired = TanitaScaleConnection.isPaired(defaults: defaults)
    isToday = day == BodyMeasurementDTO.formatDay(now, timeZone: timeZone)
    await reload(day: day)
  }

  /// カードの「測る」や追加ボタンの長押しから始める。自動で空振りしたあとでも押せる。
  ///
  /// 既に測っている最中なら、始め直さずにシートを開き直すだけ。
  func measureByHand() {
    guard canMeasure else { return }
    isMeasurementSheetPresented = true
    guard !isRunning else { return }
    manualFailure = nil
    startedByHand = true
    isMeasuring = true
    connection.start(timeouts: .manual)
  }

  func stop() {
    isMeasuring = false
    pendingRearm = false
    connection.stop()
    closeSheetIfNothingToShow()
  }

  /// シートを閉じる。接続は止めない。続けて乗れば、また開く。
  /// 進み具合はカードの下段に残る。
  func dismissMeasurementSheet() {
    isMeasurementSheetPresented = false
    newResult = nil
  }

  /// 1件を開いたときに比べる相手。前の日の同じ頃に測った回
  func reference(for measurement: BodyMeasurementDTO) -> BodyMeasurementDTO? {
    BodyMeasurementDetail.reference(
      for: measurement, among: summary?.recent ?? [], calendar: calendar)
  }

  /// 測定1件を消す。取り込みをやり直したいときや、他人が乗ったぶんが混ざったとき。
  ///
  /// 消えたように見えて消えていない状態を残さない。失敗したら画面に伝えて、
  /// 行はサーバーの中身で引き直す。
  func delete(_ measurement: BodyMeasurementDTO) async {
    do {
      try await api.deleteBodyMeasurement(id: measurement.id)
    } catch {
      manualFailure = error.localizedDescription
    }
    if let day { await reload(day: day) }
  }

  // MARK: - 内側

  /// 見ている日を末尾にした直近の範囲を取る。
  ///
  /// その日の1件だけでは足りない。前の日の同じ頃との差と、測っていない日に出す
  /// 「前回は何日前か」のために少し遡る。
  private func reload(day: String) async {
    let from = BodyCardSummary.offsetDay(
      day, by: -(BodyCardSummary.lookbackDays - 1), calendar: calendar)
    do {
      let measurements = try await api.fetchBodyMeasurements(from: from, to: day)
      summary = BodyCardSummary.make(measurements, day: day, calendar: calendar)
    } catch {
      // 取れなくてもカードが消えるだけ。記録の画面の本題ではないので何も言わない
    }
  }

  private func apply(_ state: TanitaScaleConnection.State) {
    finishedWhileSaving = false
    switch state {
    case .scanning, .connecting, .preparing:
      activity = .searching
    case .waitingForStep:
      activity = .waitingForStep
    case .reading:
      activity = .reading
    case .finished where isMeasuring && savesInFlight > 0:
      // 保存が終わるまでは受け取り中のまま見せる。落とすと、シートが閉じたり段階がちらついたりする
      activity = .reading
      finishedWhileSaving = true
    case .idle, .finished:
      activity = .idle
      followUpNewMeasurement()
    case .failed(let message):
      activity = .idle
      // 自動で探して見つからなかっただけのことをエラーとして出さない
      manualFailure = startedByHand ? message : nil
      // 保存まで済んでから切れたなら、結果は開く。待ち直しはしない
      if pendingRearm { openSavedResult() }
      pendingRearm = false
      // 登録が外れていると分かったら、接続が識別子を消している。測る導線を引っ込める
      isPaired = TanitaScaleConnection.isPaired(defaults: defaults)
    }
    closeSheetIfNothingToShow()
  }

  /// 測る途中でなくなり、結果も失敗も無いなら、シートを閉じる。
  /// 別の日へ移ったときや、受け取ったのが引き取り済みの測定だけだったときに当たる。
  private func closeSheetIfNothingToShow() {
    guard isMeasurementSheetPresented, newResult == nil, stage == nil else { return }
    isMeasurementSheetPresented = false
  }

  /// 新しい測定が入ったら、その1件を開き、続けて乗るかもしれないのでもう一度待ちに入る。
  ///
  /// 引き取りが終わったあとと、保存して取り直したあとの両方から呼ぶ。どちらが先になるかは
  /// 通信と通信の速さ次第で決まらない。印を1つ持たせて、後に揃ったほうで動かす。
  /// 開くのを引き取りの終わりまで待つのは、開いた時点で次の待ち受けに入れるようにするため。
  private func followUpNewMeasurement() {
    guard pendingRearm, !isRunning else { return }
    pendingRearm = false
    openSavedResult()
    guard ScaleAutoStart.shouldRearm(savedNewMeasurement: true, isToday: isToday) else {
      isMeasuring = false
      return
    }
    startedByHand = false
    connection.start(timeouts: .automatic)
  }

  private func openSavedResult() {
    guard let lastSavedAt,
      let saved = summary?.recent.last(where: { $0.isMeasured(at: lastSavedAt) })
    else { return }
    newResult = saved
    isMeasurementSheetPresented = true
  }

  /// 受け取った測定を保存する。保存が終わるまで、状態を `.reading` に保つ。
  private func receive(_ measurement: TanitaBodyMeasurement) {
    savesInFlight += 1
    Task {
      await store(measurement)
      savesInFlight -= 1
      if savesInFlight == 0, finishedWhileSaving {
        finishedWhileSaving = false
        activity = .idle
      }
      followUpNewMeasurement()
      closeSheetIfNothingToShow()
    }
  }

  private func store(_ measurement: TanitaBodyMeasurement) async {
    guard let dto = BodyMeasurementCreateDTO(measurement, timeZone: timeZone) else { return }
    var savedNew = false
    do {
      try await api.createBodyMeasurement(dto)
      savedNew = true
    } catch APIError.conflict {
      // 体重計は引き取り済みのぶんも送ってくる。既にある測定は数えない
    } catch {
      if startedByHand { manualFailure = error.localizedDescription }
    }
    isPaired = TanitaScaleConnection.isPaired(defaults: defaults)
    if let day { await reload(day: day) }
    // 取り直してから印を立てる。先に立てると、開く1件がまだ手元に無いまま動いてしまう
    if savedNew, isMeasuring {
      // 受け取った時刻ではなく送った時刻で探す。送るときに秒を切り捨てている
      lastSavedAt = BodyMeasurementDTO.date(fromTimestamp: dto.measuredAt)
      pendingRearm = true
    }
  }
}

extension BodyMeasurementDTO {
  /// 送った時刻と同じ測定か。
  ///
  /// サーバーから返る時刻は、書き込んだ経路によって小数秒の有無が違う。秒まで合えば同じとみなす。
  func isMeasured(at date: Date) -> Bool {
    guard let measuredAtDate else { return false }
    return abs(measuredAtDate.timeIntervalSince(date)) < 1
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
  func deleteBodyMeasurement(id: String) async throws
}

extension APIClient: BodyMeasurementStore {}
