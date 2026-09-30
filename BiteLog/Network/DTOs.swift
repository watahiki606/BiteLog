import Foundation

// MARK: - FoodMaster DTO

struct FoodMasterDTO: Codable, Identifiable, Hashable {
  var id: UUID
  var brandName: String
  var productName: String
  var calories: Double
  var dietaryFiber: Double
  var netCarbs: Double
  var fat: Double
  var protein: Double
  var portionSize: Double
  var portionUnit: String
  var uniqueKey: String
  var createdBy: String?
  var isMine: Bool?
  var usageCount: Int
  var lastUsedDate: Date?
  var lastNumberOfServings: Double

  var carbohydrates: Double { netCarbs + dietaryFiber }

  /// 1食分 (portionSize 分) の栄養素値。表示コンポーネントに渡すためのまとめ。
  var portionNutritionValues: NutritionValues {
    NutritionValues(
      calories: calories, netCarbs: netCarbs, dietaryFiber: dietaryFiber, fat: fat,
      protein: protein)
  }

  static func createUniqueKey(brandName: String, productName: String, portionUnit: String) -> String {
    "\(brandName)|\(productName)|\(portionUnit)"
  }
}

struct FoodMasterCreateDTO: Codable {
  var id: String
  var brandName: String
  var productName: String
  var calories: Double
  var dietaryFiber: Double
  var netCarbs: Double
  var fat: Double
  var protein: Double
  var portionSize: Double
  var portionUnit: String
  var uniqueKey: String
}

struct FoodMasterUpdateDTO: Codable {
  var brandName: String?
  var productName: String?
  var calories: Double?
  var dietaryFiber: Double?
  var netCarbs: Double?
  var fat: Double?
  var protein: Double?
  var portionSize: Double?
  var portionUnit: String?
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
struct DaySummaryDTO: Codable, Identifiable, NutritionContributing {
  var logDate: String
  var mealType: MealType
  var calories: Double
  var protein: Double
  var fat: Double
  var netCarbs: Double
  var dietaryFiber: Double

  var id: String { "\(logDate)-\(mealType.rawValue)" }

  var nutritionValues: NutritionValues {
    NutritionValues(
      calories: calories, netCarbs: netCarbs, dietaryFiber: dietaryFiber, fat: fat,
      protein: protein)
  }
}

struct DaySummaryListResponse: Codable {
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
      calories: dto.calories,
      netCarbs: dto.netCarbs,
      dietaryFiber: dto.dietaryFiber,
      fat: dto.fat,
      protein: dto.protein,
      portionSize: dto.portionSize,
      portionUnit: dto.portionUnit
    )
  }
}

// MARK: - AI Analyze DTO

struct AIAnalyzeRequest: Codable {
  var imageBase64: String
  var note: String?
}

struct AIAnalyzeResponse: Codable {
  var calories: Double
  var protein: Double
  var fat: Double
  var netCarbs: Double
  var dietaryFiber: Double
  var portionAmount: Double
  var portionUnit: String
  var confidence: String
  var productName: String
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
  /// 測定を暦日ごとに1件へまとめる。同じ日に複数回測った日は最後のものを残す。
  ///
  /// 日中の変動より「その日どうだったか」を見たいので、直近の1件で代表させる。
  /// `sourceDate` が無い行は、どの暦日のものか決められないので落とす。
  static func latestByDay(_ measurements: [BodyMeasurementDTO]) -> [String: BodyMeasurementDTO] {
    var byDay: [String: BodyMeasurementDTO] = [:]
    for measurement in measurements {
      guard let day = measurement.sourceDate else { continue }
      // ISO 8601 は桁が揃っているので、文字列の大小がそのまま時刻の前後になる
      if let existing = byDay[day], existing.measuredAt >= measurement.measuredAt { continue }
      byDay[day] = measurement
    }
    return byDay
  }

  /// 暦日の文字列。体組成の `sourceDate` と同じ形にする。
  static func formatDay(_ date: Date, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}
