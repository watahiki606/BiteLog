import Combine
import Foundation
import Testing

@testable import BiteLog

/// 記録の画面の体組成カードが、いつ自動で探し始めていつ黙るか。
///
/// 測定の値はすべて架空。実際の記録は使っていない。
struct ScaleAutoStartTests {

  /// 揃っている状態。個々の条件を1つずつ崩して確かめる
  private static func ready() -> ScaleAutoStart.Conditions {
    ScaleAutoStart.Conditions(
      isToday: true, isPaired: true, alreadyMeasured: false, isRunning: false,
      attemptedToday: false)
  }

  @Test func 今日でまだ測っていなければ自動で探す() {
    #expect(ScaleAutoStart.shouldStart(Self.ready()))
  }

  @Test func 過去の日を開いたときは探さない() {
    var conditions = Self.ready()
    conditions.isToday = false
    #expect(!ScaleAutoStart.shouldStart(conditions))
  }

  @Test func 体組成計を登録していなければ探さない() {
    var conditions = Self.ready()
    conditions.isPaired = false
    #expect(!ScaleAutoStart.shouldStart(conditions))
  }

  @Test func その日もう測っていれば探さない() {
    var conditions = Self.ready()
    conditions.alreadyMeasured = true
    #expect(!ScaleAutoStart.shouldStart(conditions))
  }

  @Test func すでに探している途中なら重ねて始めない() {
    var conditions = Self.ready()
    conditions.isRunning = true
    #expect(!ScaleAutoStart.shouldStart(conditions))
  }

  @Test func 同じ日に自動で二度目は探さない() {
    var conditions = Self.ready()
    conditions.attemptedToday = true
    #expect(!ScaleAutoStart.shouldStart(conditions))
  }
}

/// 暦日ごとの代表値の選び方。
struct BodyMeasurementDTODayTests {

  private static func measurement(
    id: String, day: String?, at measuredAt: String, weight: Double
  ) -> BodyMeasurementDTO {
    BodyMeasurementDTO(
      id: id, sourceDate: day, measuredAt: measuredAt, weightKg: weight, bodyFatPercent: nil,
      muscleMassKg: nil, muscleScore: nil, visceralFatLevel: nil, basalMetabolismKcal: nil,
      metabolicAge: nil, boneMassKg: nil, bodyWaterPercent: nil)
  }

  @Test func 同じ日に複数回測ったら最後のものを残す() {
    let byDay = BodyMeasurementDTO.latestByDay([
      Self.measurement(id: "a", day: "2026-01-02", at: "2026-01-01T22:00:00.000Z", weight: 60),
      Self.measurement(id: "b", day: "2026-01-02", at: "2026-01-02T12:00:00.000Z", weight: 61),
    ])

    #expect(byDay["2026-01-02"]?.id == "b")
  }

  @Test func 渡す順番で結果が変わらない() {
    let items = [
      Self.measurement(id: "a", day: "2026-01-02", at: "2026-01-02T12:00:00.000Z", weight: 61),
      Self.measurement(id: "b", day: "2026-01-02", at: "2026-01-01T22:00:00.000Z", weight: 60),
    ]

    #expect(BodyMeasurementDTO.latestByDay(items)["2026-01-02"]?.id == "a")
    #expect(BodyMeasurementDTO.latestByDay(items.reversed())["2026-01-02"]?.id == "a")
  }

  @Test func 小数秒の有無が混ざっていても前後を見分ける() {
    // 体組成計から直接入れた行は小数秒付き、手で入れた行は無しになりうる
    let byDay = BodyMeasurementDTO.latestByDay([
      Self.measurement(id: "written-by-hand", day: "2026-01-02", at: "2026-01-02T07:00:00Z", weight: 60),
      Self.measurement(id: "from-scale", day: "2026-01-02", at: "2026-01-02T08:00:00.000Z", weight: 61),
    ])

    #expect(byDay["2026-01-02"]?.id == "from-scale")
  }

  @Test func 暦日が分からない行は落とす() {
    let byDay = BodyMeasurementDTO.latestByDay([
      Self.measurement(id: "a", day: nil, at: "2026-01-02T12:00:00.000Z", weight: 60)
    ])

    #expect(byDay.isEmpty)
  }

  @Test func 暦日は測った地域の日付にする() {
    // 2026-01-02 07:30 JST。UTC では前日の 22:30 なので、UTC で切ると1日ずれる
    let morning = Date(timeIntervalSince1970: 1_767_306_600)

    #expect(
      BodyMeasurementDTO.formatDay(morning, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        == "2026-01-02")
  }
}

/// カードの状態。CoreBluetooth には触らず、体組成計の役を差し替えて確かめる。
@MainActor
struct BodyCompositionModelTests {

  /// 体組成計の役。状態を好きなところへ動かせる
  private final class FakeScale: ScaleSession {
    let subject = CurrentValueSubject<TanitaScaleConnection.State, Never>(.idle)
    var stateStream: AnyPublisher<TanitaScaleConnection.State, Never> {
      subject.eraseToAnyPublisher()
    }
    var onMeasurement: ((TanitaBodyMeasurement) -> Void)?
    var startedWith: [TanitaScaleConnection.Timeouts] = []
    var stopCount = 0

    func start(timeouts: TanitaScaleConnection.Timeouts) {
      startedWith.append(timeouts)
      subject.send(.scanning)
    }

    func stop() {
      stopCount += 1
      subject.send(.idle)
    }
  }

  private final class FakeStore: BodyMeasurementStore {
    var stored: [BodyMeasurementDTO]
    var created: [BodyMeasurementCreateDTO] = []
    var fetchError: Error?

    init(stored: [BodyMeasurementDTO] = []) { self.stored = stored }

    func fetchBodyMeasurements(limit: Int) async throws -> [BodyMeasurementDTO] {
      if let fetchError { throw fetchError }
      return stored
    }

    func createBodyMeasurement(_ dto: BodyMeasurementCreateDTO) async throws {
      created.append(dto)
    }
  }

  private static let jst = TimeZone(identifier: "Asia/Tokyo")!
  /// 2026-01-02 07:30 JST
  private static let now = Date(timeIntervalSince1970: 1_767_306_600)

  private static func measurement(day: String, weight: Double) -> BodyMeasurementDTO {
    BodyMeasurementDTO(
      id: UUID().uuidString, sourceDate: day, measuredAt: "\(day)T00:00:00.000Z",
      weightKg: weight, bodyFatPercent: 20, muscleMassKg: nil, muscleScore: nil,
      visceralFatLevel: nil, basalMetabolismKcal: nil, metabolicAge: nil, boneMassKg: nil,
      bodyWaterPercent: nil)
  }

  private static func defaults(paired: Bool) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "BodyCompositionModelTests-\(UUID().uuidString)")!
    defaults.removePersistentDomain(forName: defaults.description)
    defaults.set(paired, forKey: TanitaScaleConnection.pairedKey)
    return defaults
  }

  private static func model(
    scale: FakeScale, store: FakeStore, paired: Bool
  ) -> BodyCompositionModel {
    BodyCompositionModel(
      connection: scale, api: store, defaults: defaults(paired: paired), timeZone: jst)
  }

  @Test func 体組成計を登録していなければカードを出さず探しもしない() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: false)

    await model.load(date: Self.now, now: Self.now)

    #expect(!model.isVisible)
    #expect(scale.startedWith.isEmpty)
  }

  @Test func 登録済みでその日まだ測っていなければ自動で探し始める() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)

    await model.load(date: Self.now, now: Self.now)

    #expect(model.isVisible)
    #expect(scale.startedWith == [.automatic])
    #expect(model.activity == .searching)
  }

  @Test func その日もう測っていれば探さずに値だけ出す() async {
    let scale = FakeScale()
    let store = FakeStore(stored: [Self.measurement(day: "2026-01-02", weight: 61.2)])
    let model = Self.model(scale: scale, store: store, paired: true)

    await model.load(date: Self.now, now: Self.now)

    #expect(model.dayMeasurement?.weightKg == 61.2)
    #expect(scale.startedWith.isEmpty)
  }

  @Test func 過去の日を開いたときは探さない() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)
    // 2026-01-01 JST
    let yesterday = Self.now.addingTimeInterval(-86400)

    await model.load(date: yesterday, now: Self.now)

    #expect(scale.startedWith.isEmpty)
  }

  @Test func 別の日へ移ったら探すのをやめる() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)
    await model.load(date: Self.now, now: Self.now)
    #expect(model.activity == .searching)

    await model.load(date: Self.now.addingTimeInterval(-86400), now: Self.now)

    #expect(scale.stopCount == 1)
    #expect(model.activity == .idle)
  }

  @Test func 測っていない過去の日にはカードごと出さない() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)
    let yesterday = Self.now.addingTimeInterval(-86400)

    await model.load(date: yesterday, now: Self.now)

    // 体組成計は今の時刻を刻むので、過去の日に「測る」を出しても押せる意味が無い
    #expect(!model.isVisible)
    #expect(!model.canMeasure)
  }

  @Test func 測った過去の日は値だけ出す() async {
    let scale = FakeScale()
    let store = FakeStore(stored: [Self.measurement(day: "2026-01-01", weight: 60.8)])
    let model = Self.model(scale: scale, store: store, paired: true)
    let yesterday = Self.now.addingTimeInterval(-86400)

    await model.load(date: yesterday, now: Self.now)

    #expect(model.isVisible)
    #expect(!model.canMeasure)
    #expect(model.dayMeasurement?.weightKg == 60.8)
  }

  @Test func 同じ日に開き直しても自動では一度しか探さない() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)

    await model.load(date: Self.now, now: Self.now)
    scale.stop()
    await model.load(date: Self.now, now: Self.now)

    #expect(scale.startedWith == [.automatic])
  }

  @Test func 自動で探して空振りしたことは画面に出さない() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)

    await model.load(date: Self.now, now: Self.now)
    scale.subject.send(.failed("体組成計が見つかりませんでした"))

    #expect(model.activity == .idle)
    #expect(model.manualFailure == nil)
  }

  @Test func 手で始めたときは失敗を伝える() async {
    let scale = FakeScale()
    let store = FakeStore(stored: [Self.measurement(day: "2026-01-02", weight: 61.2)])
    let model = Self.model(scale: scale, store: store, paired: true)
    // その日はもう測っているので自動では探さない。そこから手で始める
    await model.load(date: Self.now, now: Self.now)
    model.measureByHand()
    scale.subject.send(.failed("体組成計が見つかりませんでした"))

    #expect(scale.startedWith == [.manual])
    #expect(model.manualFailure == "体組成計が見つかりませんでした")
  }

  @Test func 乗るのを待っている間はそのことが分かる() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)
    await model.load(date: Self.now, now: Self.now)

    scale.subject.send(.waitingForStep)
    #expect(model.activity == .waitingForStep)

    scale.subject.send(.reading)
    #expect(model.activity == .reading)
  }

  @Test func 測定を受け取ったらサーバーへ送って画面に出す() async throws {
    let scale = FakeScale()
    let store = FakeStore()
    let model = Self.model(scale: scale, store: store, paired: true)
    await model.load(date: Self.now, now: Self.now)

    // 受け取ったら保存され、取り直した結果がカードに出る
    store.stored = [Self.measurement(day: "2026-01-02", weight: 61.2)]
    var received = TanitaBodyMeasurement()
    received.measuredAt = Self.now
    received.weightKg = 61.2
    received.bodyFatPercent = 20.0
    scale.onMeasurement?(received)

    try await Self.settle { store.created.count == 1 && model.dayMeasurement != nil }

    #expect(store.created.first?.weightKg == 61.2)
    #expect(model.dayMeasurement?.weightKg == 61.2)
  }

  @Test func 測定が取れなくてもカードは黙って消える() async {
    let scale = FakeScale()
    let store = FakeStore()
    store.fetchError = APIError.serverError(500)
    let model = Self.model(scale: scale, store: store, paired: false)

    await model.load(date: Self.now, now: Self.now)

    #expect(!model.isVisible)
    #expect(model.manualFailure == nil)
  }

  /// `onMeasurement` は `Task` を作って抜けるので、結果が揃うまで待つ
  private static func settle(
    _ condition: @MainActor () -> Bool, attempts: Int = 100
  ) async throws {
    for _ in 0..<attempts {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("待っていた状態にならなかった")
  }
}
