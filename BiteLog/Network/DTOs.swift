import Foundation

// MARK: - FoodMaster DTO

/// 写真の解析で、料理を分けた成分表の食材と重さ。grams は1回分に含まれる、その食材の可食部の重さ
struct FoodComponent: Codable, Hashable, Identifiable {
  var foodNumber: String
  var grams: Double
  /// 成分表の食品名
  var name: String?

  var id: String { foodNumber }
}

struct FoodMasterDTO: Codable, Identifiable, Hashable {
  var id: UUID
  var brandName: String
  var productName: String
  /// portionSize 分の量に対する値
  var nutrients: NutrientAmounts
  var portionSize: Double
  var portionUnit: String
  var uniqueKey: String
  var createdBy: String?
  var isMine: Bool?
  var usageCount: Int
  var lastUsedDate: Date?
  var lastNumberOfServings: Double
  /// 値の出典。label、composition_table、ai_estimate、manual のどれか。分からなければ nil
  var nutrientSource: String?
  /// 出典の参照先。成分表の食品番号か URL
  var nutrientSourceRef: String?

  init(
    id: UUID, brandName: String, productName: String, calories: Double, dietaryFiber: Double,
    netCarbs: Double, fat: Double, protein: Double, portionSize: Double, portionUnit: String,
    uniqueKey: String, createdBy: String? = nil, isMine: Bool? = nil, usageCount: Int,
    lastUsedDate: Date? = nil, lastNumberOfServings: Double
  ) {
    self.id = id
    self.brandName = brandName
    self.productName = productName
    self.nutrients = NutrientAmounts(
      calories: calories, protein: protein, fat: fat, netCarbs: netCarbs, dietaryFiber: dietaryFiber)
    self.portionSize = portionSize
    self.portionUnit = portionUnit
    self.uniqueKey = uniqueKey
    self.createdBy = createdBy
    self.isMine = isMine
    self.usageCount = usageCount
    self.lastUsedDate = lastUsedDate
    self.lastNumberOfServings = lastNumberOfServings
  }

  var calories: Double { nutrients.core(.calories) }
  var dietaryFiber: Double { nutrients.core(.dietaryFiber) }
  var netCarbs: Double { nutrients.core(.netCarbs) }
  var fat: Double { nutrients.core(.fat) }
  var protein: Double { nutrients.core(.protein) }
  var carbohydrates: Double { netCarbs + dietaryFiber }

  /// 選んで記録するときの量。サーバーは使ったことが無い食品の前回量を 1 で返すので、
  /// そのまま使うと 100g の食品が 1g で記録される。使ったことが無ければ1食分にする。
  /// 記録の量は `lastNumberOfServings` を直接使わず、必ずこれを通す。
  var servingsToLog: Double { usageCount > 0 ? lastNumberOfServings : portionSize }

  /// 1食分 (portionSize 分) の栄養素値。表示コンポーネントに渡すためのまとめ。
  var portionNutritionValues: NutritionValues { NutritionValues(nutrients) }

  static func createUniqueKey(brandName: String, productName: String, portionUnit: String) -> String {
    "\(brandName)|\(productName)|\(portionUnit)"
  }

  private enum CodingKeys: String, CodingKey {
    case id, brandName, productName, portionSize, portionUnit, uniqueKey, createdBy, isMine
    case usageCount, lastUsedDate, lastNumberOfServings, nutrientSource, nutrientSourceRef
  }

  // 栄養素は他の項目と同じ階層に平らに並ぶ。サーバーの応答と同じ形
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    brandName = try container.decode(String.self, forKey: .brandName)
    productName = try container.decode(String.self, forKey: .productName)
    nutrients = try NutrientAmounts(fromFlat: decoder)
    portionSize = try container.decode(Double.self, forKey: .portionSize)
    portionUnit = try container.decode(String.self, forKey: .portionUnit)
    uniqueKey = try container.decode(String.self, forKey: .uniqueKey)
    createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
    isMine = try container.decodeIfPresent(Bool.self, forKey: .isMine)
    usageCount = try container.decode(Int.self, forKey: .usageCount)
    lastUsedDate = try container.decodeIfPresent(Date.self, forKey: .lastUsedDate)
    lastNumberOfServings = try container.decode(Double.self, forKey: .lastNumberOfServings)
    nutrientSource = try container.decodeIfPresent(String.self, forKey: .nutrientSource)
    nutrientSourceRef = try container.decodeIfPresent(String.self, forKey: .nutrientSourceRef)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(brandName, forKey: .brandName)
    try container.encode(productName, forKey: .productName)
    try nutrients.encodeFlat(to: encoder)
    try container.encode(portionSize, forKey: .portionSize)
    try container.encode(portionUnit, forKey: .portionUnit)
    try container.encode(uniqueKey, forKey: .uniqueKey)
    try container.encodeIfPresent(createdBy, forKey: .createdBy)
    try container.encodeIfPresent(isMine, forKey: .isMine)
    try container.encode(usageCount, forKey: .usageCount)
    try container.encodeIfPresent(lastUsedDate, forKey: .lastUsedDate)
    try container.encode(lastNumberOfServings, forKey: .lastNumberOfServings)
    try container.encodeIfPresent(nutrientSource, forKey: .nutrientSource)
    try container.encodeIfPresent(nutrientSourceRef, forKey: .nutrientSourceRef)
  }
}

struct FoodMasterCreateDTO: Encodable {
  var id: String
  var brandName: String
  var productName: String
  var nutrients: NutrientAmounts
  var portionSize: Double
  var portionUnit: String
  var uniqueKey: String
  /// "reject" なら、同じブランド名・商品名・単位の別の食品があるときサーバーは 409 を返す。
  /// 無ければ既存の食品が返る。公開中の古い版はこの印を送らないので、その動きを残している
  var onConflict: String? = nil
  /// 値の出典。label、composition_table、ai_estimate、manual のどれか
  var nutrientSource: String? = nil
  /// 出典の参照先。成分表の食品番号か URL
  var nutrientSourceRef: String? = nil

  init(
    id: String, brandName: String, productName: String, calories: Double, dietaryFiber: Double,
    netCarbs: Double, fat: Double, protein: Double, portionSize: Double, portionUnit: String,
    uniqueKey: String
  ) {
    self.id = id
    self.brandName = brandName
    self.productName = productName
    self.nutrients = NutrientAmounts(
      calories: calories, protein: protein, fat: fat, netCarbs: netCarbs, dietaryFiber: dietaryFiber)
    self.portionSize = portionSize
    self.portionUnit = portionUnit
    self.uniqueKey = uniqueKey
  }

  private enum CodingKeys: String, CodingKey {
    case id, brandName, productName, portionSize, portionUnit, uniqueKey, onConflict
    case nutrientSource, nutrientSourceRef
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(brandName, forKey: .brandName)
    try container.encode(productName, forKey: .productName)
    try nutrients.encodeFlat(to: encoder)
    try container.encode(portionSize, forKey: .portionSize)
    try container.encode(portionUnit, forKey: .portionUnit)
    try container.encode(uniqueKey, forKey: .uniqueKey)
    try container.encodeIfPresent(onConflict, forKey: .onConflict)
    try container.encodeIfPresent(nutrientSource, forKey: .nutrientSource)
    try container.encodeIfPresent(nutrientSourceRef, forKey: .nutrientSourceRef)
  }

  /// 重なりを 409 で知らせてもらう作成の本文。
  /// 既存の食品が返ると、送った値で作れたと思い込んでその値で記録してしまうため。
  func rejectingDuplicate() -> FoodMasterCreateDTO {
    var dto = self
    dto.onConflict = "reject"
    return dto
  }
}

struct FoodMasterUpdateDTO: Encodable {
  var brandName: String?
  var productName: String?
  /// 送る栄養素だけを持つ。送らなかった栄養素はサーバーで今の値のまま残る
  var nutrients: NutrientAmounts
  /// 分からないに戻す栄養素。null を送る。最初の5項目はサーバーが null を受け付けない
  var clearedNutrients: Set<NutrientID> = []
  var portionSize: Double?
  var portionUnit: String?

  init(
    brandName: String? = nil, productName: String? = nil, calories: Double? = nil,
    dietaryFiber: Double? = nil, netCarbs: Double? = nil, fat: Double? = nil, protein: Double? = nil,
    portionSize: Double? = nil, portionUnit: String? = nil
  ) {
    self.brandName = brandName
    self.productName = productName
    var nutrients = NutrientAmounts()
    nutrients[.calories] = calories
    nutrients[.dietaryFiber] = dietaryFiber
    nutrients[.netCarbs] = netCarbs
    nutrients[.fat] = fat
    nutrients[.protein] = protein
    self.nutrients = nutrients
    self.portionSize = portionSize
    self.portionUnit = portionUnit
  }

  private enum CodingKeys: String, CodingKey {
    case brandName, productName, portionSize, portionUnit
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(brandName, forKey: .brandName)
    try container.encodeIfPresent(productName, forKey: .productName)
    try nutrients.encodeFlat(to: encoder)
    try NutrientAmounts.encodeNulls(clearedNutrients, to: encoder)
    try container.encodeIfPresent(portionSize, forKey: .portionSize)
    try container.encodeIfPresent(portionUnit, forKey: .portionUnit)
  }
}

struct FoodMasterListResponse: Codable {
  var items: [FoodMasterDTO]
  var total: Int
  var hasMore: Bool
}

// MARK: - LogItem DTO

struct LogItemDTO: Codable, Identifiable {
  var id: UUID
  var timestamp: Date
  var logDate: String
  var mealType: MealType
  var numberOfServings: Double
  var isMasterDeleted: Bool
  var foodMaster: FoodMasterDTO?
  var nutritionSnapshot: NutritionSnapshot?

  var nutritionValues: NutritionValues {
    if let fm = foodMaster {
      return NutritionSnapshot.from(fm).scaled(by: numberOfServings)
    } else if let snapshot = nutritionSnapshot {
      return snapshot.scaled(by: numberOfServings)
    }
    return .zero
  }

  var calories: Double { nutritionValues.calories }
  var protein: Double { nutritionValues.protein }
  var fat: Double { nutritionValues.fat }
  var netCarbs: Double { nutritionValues.netCarbs }
  var dietaryFiber: Double { nutritionValues.dietaryFiber }
  var carbohydrates: Double { nutritionValues.carbs }

  var brandName: String { foodMaster?.brandName ?? nutritionSnapshot?.brandName ?? "" }
  var productName: String { foodMaster?.productName ?? nutritionSnapshot?.productName ?? "" }
  var portionUnit: String { foodMaster?.portionUnit ?? nutritionSnapshot?.portionUnit ?? "" }
}

struct LogItemCreateDTO: Codable {
  var id: String
  var timestamp: String
  var logDate: String
  var mealType: String
  var numberOfServings: Double
  var foodMasterId: String?
  var nutritionSnapshot: NutritionSnapshot?
}

struct LogItemUpdateDTO: Codable {
  var numberOfServings: Double?
  var mealType: String?
  var timestamp: String?
}

struct LogItemListResponse: Codable {
  var items: [LogItemDTO]
  var hasMore: Bool?
}

// MARK: - 統計集計用

/// 栄養を集計できる型の共通インターフェース。LogItemDTO（個別ログ）と
/// DaySummaryDTO（サーバ側で日付×食事タイプに集計済み）の両方が準拠する。
protocol NutritionContributing {
  var logDate: String { get }
  var mealType: MealType { get }
  var nutritionValues: NutritionValues { get }
}

extension LogItemDTO: NutritionContributing {}

/// GET /api/log-items/summary の1行（特定日・特定食事タイプの栄養合計）。
struct DaySummaryDTO: Decodable, Identifiable, NutritionContributing {
  var logDate: String
  var mealType: MealType
  var nutrients: NutrientAmounts
  /// 合計に入れた品の数と、あとから足した栄養素ごとに値の分かっていた品の数
  var totals: NutrientTotals

  var id: String { "\(logDate)-\(mealType.rawValue)" }

  var nutritionValues: NutritionValues { NutritionValues(nutrients) }

  var calories: Double { nutrients.core(.calories) }
  var protein: Double { nutrients.core(.protein) }
  var fat: Double { nutrients.core(.fat) }
  var netCarbs: Double { nutrients.core(.netCarbs) }
  var dietaryFiber: Double { nutrients.core(.dietaryFiber) }

  private enum CodingKeys: String, CodingKey {
    case logDate, mealType, itemCount, knownCounts
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    logDate = try container.decode(String.self, forKey: .logDate)
    mealType = try container.decode(MealType.self, forKey: .mealType)
    nutrients = try NutrientAmounts(fromFlat: decoder)
    totals = try NutrientTotals(
      values: NutritionValues(nutrients),
      itemCount: container.decodeIfPresent(Int.self, forKey: .itemCount) ?? 0,
      knownCounts: Self.knownCounts(container.decodeIfPresent([String: Int].self, forKey: .knownCounts)))
  }

  private static func knownCounts(_ raw: [String: Int]?) -> [NutrientID: Int] {
    var counts: [NutrientID: Int] = [:]
    for (key, count) in raw ?? [:] {
      if let id = NutrientID(rawValue: key) { counts[id] = count }
    }
    return counts
  }
}

struct DaySummaryListResponse: Decodable {
  var items: [DaySummaryDTO]
}

// MARK: - NutritionGoals DTO

struct NutritionGoalsDTO: Codable {
  var targetProtein: Double
  var targetFat: Double
  var targetNetCarbs: Double
  var targetFiber: Double

  var targetCalories: Double {
    targetProtein * 4 + targetFat * 9 + targetNetCarbs * 4 + targetFiber * 2
  }
}

// MARK: - Auth DTO

struct AuthRequest: Codable {
  var provider: String
  var identityToken: String
}

struct AuthResponse: Codable {
  var token: String
  var userId: String
  var isAdmin: Bool
}

// MARK: - Batch Result

struct BatchResult: Codable {
  var created: Int
  var skipped: Int
  var errors: Int
}

// MARK: - CSV Import Result

struct CSVImportResult: Codable {
  var created: Int
  var skipped: Int
  var foodMastersCreated: Int
}

// MARK: - NutritionSnapshot extension（FoodMasterDTOから生成）

extension NutritionSnapshot {
  static func from(_ dto: FoodMasterDTO) -> NutritionSnapshot {
    NutritionSnapshot(
      brandName: dto.brandName,
      productName: dto.productName,
      nutrients: dto.nutrients,
      portionSize: dto.portionSize,
      portionUnit: dto.portionUnit
    )
  }
}

// MARK: - AI Analyze DTO

struct AIAnalyzeRequest: Codable {
  var imageBase64: String
  var note: String?
  /// 入れたときだけ、Worker が公式の栄養成分を Web で調べる
  var menuName: String?
}

struct AIAnalyzeResponse: Decodable {
  var calories: Double
  var protein: Double
  var fat: Double
  var netCarbs: Double
  var dietaryFiber: Double
  var portionAmount: Double
  var portionUnit: String
  var confidence: String
  var productName: String
  /// menuName を送ったときだけ返る。label、official、estimate のどれか
  var basis: String?
  /// 検索で実際に見たページのうち、値を取ったもの
  var sourceUrl: String?
  /// 写真だけで解析したとき、ロゴや文字から読み取った店名とメニュー名
  var menuGuess: String?
  /// 最初の5項目のあとに足した栄養素。表示か公式の値から読めたものと、成分表で引いたもの
  var addedNutrients: NutrientAmounts
  /// 料理を分けた成分表の食材と重さ。成分表で引けなかったときは nil
  var components: [FoodComponent]?

  private enum CodingKeys: String, CodingKey {
    case calories, protein, fat, netCarbs, dietaryFiber, portionAmount, portionUnit, confidence, productName
    case basis, sourceUrl, menuGuess, components
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    calories = try c.decode(Double.self, forKey: .calories)
    protein = try c.decode(Double.self, forKey: .protein)
    fat = try c.decode(Double.self, forKey: .fat)
    netCarbs = try c.decode(Double.self, forKey: .netCarbs)
    dietaryFiber = try c.decode(Double.self, forKey: .dietaryFiber)
    portionAmount = try c.decode(Double.self, forKey: .portionAmount)
    portionUnit = try c.decode(String.self, forKey: .portionUnit)
    confidence = try c.decode(String.self, forKey: .confidence)
    productName = try c.decode(String.self, forKey: .productName)
    basis = try c.decodeIfPresent(String.self, forKey: .basis)
    sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl)
    menuGuess = try c.decodeIfPresent(String.self, forKey: .menuGuess)
    components = try c.decodeIfPresent([FoodComponent].self, forKey: .components)
    let all = try NutrientAmounts(fromFlat: decoder)
    addedNutrients = NutrientAmounts(
      Dictionary(uniqueKeysWithValues: NutrientID.allCases.filter { !$0.definition.core }.compactMap { id in
        all[id].map { (id, $0) }
      }))
  }
}

// MARK: - BodyMeasurement DTO

/// 体組成計の測定1件。サーバーの17列に合わせる。
///
/// `measurementDateRaw` / `measurementTimeRaw` / `pageUrl` は HealthPlanet の
/// ページから取り込んだときに何が表示されていたかを残す列なので、直接受信では送らない。
struct BodyMeasurementCreateDTO: Codable, Equatable {
  var sourceDate: String
  var measuredAt: String
  var measurementIndex: Int
  var itemCount: Int
  var inputMethod: String
  var weightKg: Double?
  var bodyFatPercent: Double?
  var muscleMassKg: Double?
  var muscleScore: Double?
  var visceralFatLevel: Double?
  var basalMetabolismKcal: Double?
  var metabolicAge: Int?
  var boneMassKg: Double?
  var bodyWaterPercent: Double?
}

extension BodyMeasurementCreateDTO {
  /// 体組成計から Bluetooth で直接受け取ったことを示す。
  /// CSV 取り込みの「対応機器データ」や手動入力と区別できるようにしている。
  static let bluetoothInputMethod = "体組成計から直接"

  private static let measuredAtFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return formatter
  }()

  /// 体重計から受け取った測定を、そのまま送れる形にする。
  /// 計測時刻が取れていない測定は、同一性を判定する手がかりが無いので送らない。
  init?(_ measurement: TanitaBodyMeasurement, timeZone: TimeZone = .current) {
    guard let measuredAt = measurement.measuredAt else { return nil }

    // 秒は切り捨てる。HealthPlanet のページから取り込む経路は分までしか持たないため、
    // 秒を残すと同じ測定が別の行として二重に入る
    let atMinute = Date(
      timeIntervalSince1970: (measuredAt.timeIntervalSince1970 / 60).rounded(.down) * 60)

    let sourceDateFormatter = DateFormatter()
    sourceDateFormatter.locale = Locale(identifier: "en_US_POSIX")
    sourceDateFormatter.timeZone = timeZone
    sourceDateFormatter.dateFormat = "yyyy-MM-dd"

    let values: [Double?] = [
      measurement.weightKg, measurement.bodyFatPercent, measurement.muscleMassKg,
      measurement.muscleScore.map(Double.init), measurement.visceralFatLevel,
      measurement.basalMetabolismKcal.map(Double.init),
      measurement.metabolicAge.map(Double.init), measurement.boneMassKg,
      measurement.bodyWaterPercent,
    ]

    self.init(
      sourceDate: sourceDateFormatter.string(from: atMinute),
      measuredAt: Self.measuredAtFormatter.string(from: atMinute),
      measurementIndex: 0,
      itemCount: values.compactMap { $0 }.count,
      inputMethod: Self.bluetoothInputMethod,
      weightKg: measurement.weightKg,
      bodyFatPercent: measurement.bodyFatPercent,
      muscleMassKg: measurement.muscleMassKg,
      muscleScore: measurement.muscleScore.map(Double.init),
      visceralFatLevel: measurement.visceralFatLevel,
      basalMetabolismKcal: measurement.basalMetabolismKcal.map(Double.init),
      metabolicAge: measurement.metabolicAge,
      boneMassKg: measurement.boneMassKg,
      bodyWaterPercent: measurement.bodyWaterPercent
    )
  }
}

/// サーバーが持っている測定1件。
///
/// 暦日は `measuredAt` から切り出さない。`measuredAt` は UTC で持っているので、
/// 朝に測ると前日の日付になる。測ったその地域の暦日は `sourceDate` の側にある。
///
/// `measuredAt` を文字列のまま持つのは、書き込んだ経路によって小数秒の有無が
/// 揃っていないため。`JSONDecoder` の `.iso8601` は小数秒付きを読めない。
struct BodyMeasurementDTO: Codable, Identifiable, Equatable {
  let id: String
  let sourceDate: String?
  let measuredAt: String
  let weightKg: Double?
  let bodyFatPercent: Double?
  let muscleMassKg: Double?
  let muscleScore: Double?
  let visceralFatLevel: Double?
  let basalMetabolismKcal: Double?
  let metabolicAge: Int?
  let boneMassKg: Double?
  let bodyWaterPercent: Double?
}

extension BodyMeasurementDTO {
  /// 計測時刻。
  ///
  /// 書き込んだ経路によって小数秒の有無が揃っていないので、両方を試す。
  var measuredAtDate: Date? { Self.date(fromTimestamp: measuredAt) }

  /// サーバーとやり取りする時刻の文字列を読む。小数秒の有無はどちらでもよい
  static func date(fromTimestamp timestamp: String) -> Date? {
    for formatter in timestampFormatters {
      if let date = formatter.date(from: timestamp) { return date }
    }
    return nil
  }

  private static let timestampFormatters: [DateFormatter] = {
    ["yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"].map { format in
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(identifier: "UTC")
      formatter.dateFormat = format
      return formatter
    }
  }()

  /// 暦日の文字列。体組成の `sourceDate` と同じ形にする。
  static func formatDay(_ date: Date, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}

// MARK: - 日次統計 DTO

/// `GET /api/statistics/daily` が返す1日ぶん。栄養の合計と体組成の平均が
/// サーバー側でマージ済み。
///
/// 栄養は記録の無い日を 0 で返すが、体組成は測っていない日を `nil` で返す。
/// この違いは意図したもので、0 で埋めると「その日は体重が 0 だった」になる。
struct DailyStatDTO: Decodable, Identifiable, Equatable {
  let date: String
  let nutrients: NutrientAmounts
  let weightKg: Double?
  let bodyFatPercent: Double?
  let muscleMassKg: Double?
  let muscleScore: Double?
  let visceralFatLevel: Double?
  let basalMetabolismKcal: Double?
  let metabolicAge: Double?
  let boneMassKg: Double?
  let bodyWaterPercent: Double?

  var id: String { date }

  var calories: Double { nutrients.core(.calories) }
  var protein: Double { nutrients.core(.protein) }
  var fat: Double { nutrients.core(.fat) }
  var netCarbs: Double { nutrients.core(.netCarbs) }
  var dietaryFiber: Double { nutrients.core(.dietaryFiber) }

  private enum CodingKeys: String, CodingKey {
    case date, weightKg, bodyFatPercent, muscleMassKg, muscleScore, visceralFatLevel
    case basalMetabolismKcal, metabolicAge, boneMassKg, bodyWaterPercent
  }

  // 栄養素は日付や体組成と同じ階層に平らに並ぶ
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    date = try container.decode(String.self, forKey: .date)
    nutrients = try NutrientAmounts(fromFlat: decoder)
    weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
    bodyFatPercent = try container.decodeIfPresent(Double.self, forKey: .bodyFatPercent)
    muscleMassKg = try container.decodeIfPresent(Double.self, forKey: .muscleMassKg)
    muscleScore = try container.decodeIfPresent(Double.self, forKey: .muscleScore)
    visceralFatLevel = try container.decodeIfPresent(Double.self, forKey: .visceralFatLevel)
    basalMetabolismKcal = try container.decodeIfPresent(Double.self, forKey: .basalMetabolismKcal)
    metabolicAge = try container.decodeIfPresent(Double.self, forKey: .metabolicAge)
    boneMassKg = try container.decodeIfPresent(Double.self, forKey: .boneMassKg)
    bodyWaterPercent = try container.decodeIfPresent(Double.self, forKey: .bodyWaterPercent)
  }
}
