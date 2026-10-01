import Combine
import Foundation
import Testing

@testable import BiteLog

/// 記録の画面の体組成カードが、いつ自動で探し始めていつ黙るか。
///
/// 測定の値はすべて架空。実際の記録は使っていない。
struct ScaleAutoStartTests {

  @Test func 新しい測定が入ったら続けてもう一度待つ() {
    // 連続で数回乗ることがある。1回で終わると2回目以降が本体に溜まるだけになる
    #expect(ScaleAutoStart.shouldRearm(savedNewMeasurement: true, isToday: true))
  }

  @Test func 引き取り済みの測定が返ってきただけなら待ち直さない() {
    // 体重計は引き取り済みのぶんも送ってくる。待ち直しても何も増えない
    #expect(!ScaleAutoStart.shouldRearm(savedNewMeasurement: false, isToday: true))
  }

  @Test func 過去の日を見ているときは待ち直さない() {
    #expect(!ScaleAutoStart.shouldRearm(savedNewMeasurement: true, isToday: false))
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

    var requestedRanges: [(from: String, to: String)] = []

    func fetchBodyMeasurements(from: String, to: String) async throws -> [BodyMeasurementDTO] {
      requestedRanges.append((from, to))
      if let fetchError { throw fetchError }
      return stored.filter { ($0.sourceDate ?? "") >= from && ($0.sourceDate ?? "") <= to }
    }

    var createError: Error?
    var createAttempts = 0

    func createBodyMeasurement(_ dto: BodyMeasurementCreateDTO) async throws {
      createAttempts += 1
      if let createError { throw createError }
      created.append(dto)
    }

    var deleted: [String] = []

    func deleteBodyMeasurement(id: String) async throws {
      deleted.append(id)
      stored.removeAll { $0.id == id }
    }
  }

  private static let jst = TimeZone(identifier: "Asia/Tokyo")!
  /// 2026-01-02 07:30 JST
  private static let now = Date(timeIntervalSince1970: 1_767_306_600)

  /// 体重計から受け取った測定1件
  private static func received(weight: Double) -> TanitaBodyMeasurement {
    var measurement = TanitaBodyMeasurement()
    measurement.measuredAt = now
    measurement.weightKg = weight
    measurement.bodyFatPercent = 20.0
    return measurement
  }

  private static func measurement(
    day: String, at time: String = "00:00", weight: Double
  ) -> BodyMeasurementDTO {
    BodyMeasurementDTO(
      id: "\(day)T\(time)", sourceDate: day, measuredAt: "\(day)T\(time):00.000Z",
      weightKg: weight, bodyFatPercent: 20, muscleMassKg: nil, muscleScore: nil,
      visceralFatLevel: nil, basalMetabolismKcal: nil, metabolicAge: nil, boneMassKg: nil,
      bodyWaterPercent: nil)
  }

  private static func defaults(paired: Bool) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "BodyCompositionModelTests-\(UUID().uuidString)")!
    defaults.removePersistentDomain(forName: defaults.description)
    if paired {
      defaults.set(
        "00000000-0000-4000-8000-000000000000", forKey: TanitaScaleConnection.identifierKey)
    }
    return defaults
  }

  private static func model(
    scale: FakeScale, store: FakeStore, paired: Bool
  ) -> BodyCompositionModel {
    BodyCompositionModel(
      connection: scale, api: store, defaults: defaults(paired: paired), timeZone: jst)
  }

  /// 記録の画面が出たときの流れ。読み込むだけで、探しはしない
  private static func appear(
    _ model: BodyCompositionModel, date: Date = now, now: Date = now
  ) async {
    await model.load(date: date, now: now)
  }

  @Test func 体組成計を登録していなければカードを出さない() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: false)

    await Self.appear(model)

    #expect(!model.isVisible)
  }

  @Test func 画面を開いただけでは探しに行かない() async {
    // 記録をつけに来ただけの人の端末で Bluetooth が動くのは筋が通らない
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)

    await Self.appear(model)

    #expect(model.isVisible)
    #expect(scale.startedWith.isEmpty)
    #expect(model.activity == .idle)
  }

  @Test func 測るを押したときだけ探し始める() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)
    await Self.appear(model)

    model.measureByHand()

    #expect(scale.startedWith == [.manual])
    #expect(model.activity == .searching)
  }

  @Test func 同じ日に何度乗ってもすべてカードに出す() async {
    let scale = FakeScale()
    let store = FakeStore(stored: [
      Self.measurement(day: "2026-01-02", at: "03:00", weight: 60.9),
      Self.measurement(day: "2026-01-02", at: "12:00", weight: 61.9),
    ])
    let model = Self.model(scale: scale, store: store, paired: true)

    await Self.appear(model)

    #expect(model.summary?.measurements.count == 2)
    #expect(model.summary?.measurements.compactMap(\.weightKg) == [60.9, 61.9])
  }

  @Test func 過去の日では測るを押しても始まらない() async {
    // 体組成計は今の時刻を刻むので、過去の日に測っても意味がない
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)
    // 2026-01-01 JST
    let yesterday = Self.now.addingTimeInterval(-86400)
    await Self.appear(model, date: yesterday)

    model.measureByHand()

    #expect(scale.startedWith.isEmpty)
  }

  @Test func 別の日へ移ったら探すのをやめる() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)
    await Self.appear(model)
    model.measureByHand()
    #expect(model.activity == .searching)

    await model.load(date: Self.now.addingTimeInterval(-86400), now: Self.now)

    #expect(scale.stopCount == 1)
    #expect(model.activity == .idle)
  }

  @Test func 測っていない過去の日にはカードごと出さない() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)
    let yesterday = Self.now.addingTimeInterval(-86400)

    await Self.appear(model, date: yesterday)

    // 体組成計は今の時刻を刻むので、過去の日に「測る」を出しても押せる意味が無い
    #expect(!model.isVisible)
    #expect(!model.canMeasure)
  }

  @Test func 測った過去の日は値だけ出す() async {
    let scale = FakeScale()
    let store = FakeStore(stored: [Self.measurement(day: "2026-01-01", weight: 60.8)])
    let model = Self.model(scale: scale, store: store, paired: true)
    let yesterday = Self.now.addingTimeInterval(-86400)

    await Self.appear(model, date: yesterday)

    #expect(model.isVisible)
    #expect(!model.canMeasure)
    #expect(model.summary?.measurements.last?.weightKg == 60.8)
  }

  @Test func 食事を記録して画面が読み直されても探さない() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)

    await Self.appear(model)
    await Self.appear(model)
    await Self.appear(model)

    #expect(scale.startedWith.isEmpty)
  }

  @Test func 測定を消せる() async {
    let scale = FakeScale()
    let target = Self.measurement(day: "2026-01-02", at: "03:00", weight: 60.9)
    let store = FakeStore(stored: [
      target, Self.measurement(day: "2026-01-02", at: "12:00", weight: 61.9),
    ])
    let model = Self.model(scale: scale, store: store, paired: true)
    await Self.appear(model)

    await model.delete(target)

    #expect(store.deleted == [target.id])
    #expect(model.summary?.measurements.compactMap(\.weightKg) == [61.9])
  }

  @Test func 続けて乗るかもしれないので測定のあともう一度待つ() async {
    // 連続で数回乗ることがある。1回受け取って終わると2回目以降が本体に溜まるだけになる
    let scale = FakeScale()
    let store = FakeStore()
    let model = Self.model(scale: scale, store: store, paired: true)
    await Self.appear(model)
    model.measureByHand()

    scale.onMeasurement?(Self.received(weight: 61.2))
    try? await Self.settle { store.created.count == 1 }
    scale.subject.send(.finished)

    #expect(scale.startedWith == [.manual, .automatic])
  }

  @Test func 引き取り済みの測定が返ってきただけなら待ち直さない() async {
    // 体重計は引き取り済みのぶんも送ってくる。待ち直しても何も増えないまま繰り返す
    let scale = FakeScale()
    let store = FakeStore()
    store.createError = APIError.serverError(409)
    let model = Self.model(scale: scale, store: store, paired: true)
    await Self.appear(model)
    model.measureByHand()

    scale.onMeasurement?(Self.received(weight: 61.2))
    try? await Self.settle { store.createAttempts == 1 }
    scale.subject.send(.finished)

    #expect(scale.startedWith == [.manual])
  }

  @Test func 誰も乗らなければ待ち直さない() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)
    await Self.appear(model)
    model.measureByHand()

    scale.subject.send(.failed("体組成計が見つかりませんでした"))

    #expect(scale.startedWith == [.manual])
  }

  @Test func 傾向を出せるだけの範囲を取りに行く() async {
    let scale = FakeScale()
    let store = FakeStore()
    let model = Self.model(scale: scale, store: store, paired: true)

    await Self.appear(model)

    // 傾向は窓2つぶんを比べるので、その日の1件だけでは足りない
    #expect(store.requestedRanges.first?.to == "2026-01-02")
    #expect(store.requestedRanges.first!.from < "2026-01-02")
  }

  @Test func 自動で探して空振りしたことは画面に出さない() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)

    await Self.appear(model)
    scale.subject.send(.failed("体組成計が見つかりませんでした"))

    #expect(model.activity == .idle)
    #expect(model.manualFailure == nil)
  }

  @Test func 手で始めたときは失敗を伝える() async {
    let scale = FakeScale()
    let store = FakeStore(stored: [Self.measurement(day: "2026-01-02", weight: 61.2)])
    let model = Self.model(scale: scale, store: store, paired: true)
    await Self.appear(model)
    model.measureByHand()
    scale.subject.send(.failed("体組成計が見つかりませんでした"))

    #expect(scale.startedWith == [.manual])
    #expect(model.manualFailure == "体組成計が見つかりませんでした")
  }

  @Test func 登録が外れていたら測るを引っ込める() async {
    let scale = FakeScale()
    let defaults = Self.defaults(paired: true)
    let model = BodyCompositionModel(
      connection: scale, api: FakeStore(), defaults: defaults, timeZone: Self.jst)
    await Self.appear(model)
    model.measureByHand()

    // 公式アプリで登録し直すと、体重計はこちらの識別子を知らないと返す。
    // 接続はそこで識別子を消してから失敗を流す
    defaults.removeObject(forKey: TanitaScaleConnection.identifierKey)
    scale.subject.send(.failed("体組成計の登録が外れています"))

    #expect(!model.canMeasure)
  }

  @Test func 乗るのを待っている間はそのことが分かる() async {
    let scale = FakeScale()
    let model = Self.model(scale: scale, store: FakeStore(), paired: true)
    await Self.appear(model)
    model.measureByHand()

    scale.subject.send(.waitingForStep)
    #expect(model.activity == .waitingForStep)

    scale.subject.send(.reading)
    #expect(model.activity == .reading)
  }

  @Test func 測定を受け取ったらサーバーへ送って画面に出す() async throws {
    let scale = FakeScale()
    let store = FakeStore()
    let model = Self.model(scale: scale, store: store, paired: true)
    await Self.appear(model)
    model.measureByHand()

    // 受け取ったら保存され、取り直した結果がカードに出る
    store.stored = [Self.measurement(day: "2026-01-02", weight: 61.2)]
    var received = TanitaBodyMeasurement()
    received.measuredAt = Self.now
    received.weightKg = 61.2
    received.bodyFatPercent = 20.0
    scale.onMeasurement?(received)

    try await Self.settle { store.created.count == 1 && model.summary?.measurements.isEmpty == false }

    #expect(store.created.first?.weightKg == 61.2)
    #expect(model.summary?.measurements.last?.weightKg == 61.2)
  }

  @Test func 測定が取れなくてもカードは黙って消える() async {
    let scale = FakeScale()
    let store = FakeStore()
    store.fetchError = APIError.serverError(500)
    let model = Self.model(scale: scale, store: store, paired: false)

    await Self.appear(model)

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
