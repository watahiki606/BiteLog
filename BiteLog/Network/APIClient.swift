import Foundation

final class APIClient {
  static let shared = APIClient()

  private let baseURL: URL
  private let session: URLSession
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder

  private init() {
    guard
      let urlString = Bundle.main.object(forInfoDictionaryKey: "CLOUDFLARE_WORKER_URL") as? String,
      let url = URL(string: urlString)
    else {
      fatalError("CLOUDFLARE_WORKER_URL がInfo.plistに設定されていません")
    }
    self.baseURL = url
    self.session = URLSession.shared

    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    self.decoder = dec

    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    self.encoder = enc
  }

  // MARK: - Request

  private func request<T: Decodable>(
    path: String,
    method: String = "GET",
    body: (any Encodable)? = nil,
    isRetry: Bool = false
  ) async throws -> T {
    guard let url = URL(string: path, relativeTo: baseURL) else {
      throw APIError.invalidURL
    }

    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    if let token = await AuthManager.shared.sessionToken {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    if let body {
      req.httpBody = try encoder.encode(body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: req)
    } catch {
      throw APIError.networkError(error)
    }

    guard let http = response as? HTTPURLResponse else {
      throw APIError.networkError(URLError(.badServerResponse))
    }

    switch http.statusCode {
    case 200...299:
      break
    case 401:
      if !isRetry && !path.contains("/api/auth/") {
        let refreshed = await AuthManager.shared.refreshSession()
        if refreshed {
          return try await request(path: path, method: method, body: body, isRetry: true)
        }
      }
      await AuthManager.shared.signOut()
      throw APIError.unauthorized
    case 404:
      throw APIError.notFound
    default:
      throw APIError.serverError(http.statusCode)
    }

    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw APIError.decodingError(error)
    }
  }

  private func requestVoid(path: String, method: String, body: (any Encodable)? = nil, isRetry: Bool = false) async throws {
    guard let url = URL(string: path, relativeTo: baseURL) else {
      throw APIError.invalidURL
    }

    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    if let token = await AuthManager.shared.sessionToken {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    if let body {
      req.httpBody = try encoder.encode(body)
    }

    let (_, response): (Data, URLResponse)
    do {
      (_, response) = try await session.data(for: req)
    } catch {
      throw APIError.networkError(error)
    }

    guard let http = response as? HTTPURLResponse else { return }
    switch http.statusCode {
    case 200...299: break
    case 401:
      if !isRetry && !path.contains("/api/auth/") {
        let refreshed = await AuthManager.shared.refreshSession()
        if refreshed {
          return try await requestVoid(path: path, method: method, body: body, isRetry: true)
        }
      }
      await AuthManager.shared.signOut()
      throw APIError.unauthorized
    case 404: throw APIError.notFound
    default: throw APIError.serverError(http.statusCode)
    }
  }

  // MARK: - FoodMaster

  func fetchFoodMasters(query: String = "", limit: Int = 30, offset: Int = 0, onlyMine: Bool = false) async throws -> FoodMasterListResponse {
    let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    let mine = onlyMine ? "&onlyMine=true" : ""
    return try await request(path: "/api/food-masters?q=\(q)&limit=\(limit)&offset=\(offset)\(mine)")
  }

  func createFoodMaster(_ dto: FoodMasterCreateDTO) async throws -> FoodMasterDTO {
    return try await request(path: "/api/food-masters", method: "POST", body: dto)
  }

  func updateFoodMaster(id: UUID, _ dto: FoodMasterUpdateDTO) async throws -> FoodMasterDTO {
    return try await request(path: "/api/food-masters/\(id)", method: "PUT", body: dto)
  }

  func deleteFoodMaster(id: UUID) async throws {
    try await requestVoid(path: "/api/food-masters/\(id)", method: "DELETE")
  }

  func batchCreateFoodMasters(_ items: [FoodMasterCreateDTO]) async throws -> BatchResult {
    struct Body: Encodable { let items: [FoodMasterCreateDTO] }
    return try await request(path: "/api/food-masters/batch", method: "POST", body: Body(items: items))
  }

  func importCSV(csvText: String) async throws -> CSVImportResult {
    guard let url = URL(string: "/api/csv/import", relativeTo: baseURL) else {
      throw APIError.invalidURL
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 300
    if let token = await AuthManager.shared.sessionToken {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    req.httpBody = csvText.data(using: .utf8)

    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse else {
      throw APIError.networkError(URLError(.badServerResponse))
    }
    switch http.statusCode {
    case 200...299: break
    case 401: throw APIError.unauthorized
    default: throw APIError.serverError(http.statusCode)
    }
    return try decoder.decode(CSVImportResult.self, from: data)
  }

  // MARK: - LogItem

  func fetchLogItems(logDate: String) async throws -> [LogItemDTO] {
    let resp: LogItemListResponse = try await request(path: "/api/log-items?logDate=\(logDate)")
    return resp.items
  }

  /// 統計タブの期間集計用。日付×食事タイプごとの栄養合計をサーバ側で集計して取得する。
  /// from/to はともに "yyyy-MM-dd"（両端含む）。
  /// 日次の栄養合計と体組成平均。サーバー側でマージ済みのものを受け取る。
  func fetchDailyStatistics(from: String, to: String) async throws -> [DailyStatDTO] {
    struct Response: Decodable { let items: [DailyStatDTO] }
    let response: Response = try await request(
      path: "/api/statistics/daily?from=\(from)&to=\(to)")
    return response.items
  }

  func fetchDailySummary(from: String, to: String) async throws -> [DaySummaryDTO] {
    let resp: DaySummaryListResponse = try await request(
      path: "/api/log-items/summary?from=\(from)&to=\(to)")
    return resp.items
  }

  func createLogItem(_ dto: LogItemCreateDTO) async throws -> LogItemDTO {
    return try await request(path: "/api/log-items", method: "POST", body: dto)
  }

  func updateLogItem(id: UUID, _ dto: LogItemUpdateDTO) async throws -> LogItemDTO {
    return try await request(path: "/api/log-items/\(id)", method: "PUT", body: dto)
  }

  func deleteLogItem(id: UUID) async throws {
    try await requestVoid(path: "/api/log-items/\(id)", method: "DELETE")
  }

  func batchCreateLogItems(_ items: [LogItemCreateDTO]) async throws -> BatchResult {
    struct Body: Encodable { let items: [LogItemCreateDTO] }
    return try await request(path: "/api/log-items/batch", method: "POST", body: Body(items: items))
  }

  func deleteAllUserData() async throws {
    try await requestVoid(path: "/api/user-data", method: "DELETE")
  }

  func deleteAllDataAsAdmin() async throws {
    try await requestVoid(path: "/api/user-data/all", method: "DELETE")
  }

  // MARK: - BodyMeasurement

  /// 測定1件を登録する。同じ計測時刻の記録が既にあるとサーバーは 409 を返す。
  /// 体重計は引き取り済みのデータも送ってくることがあるので、呼ぶ側で重複として扱う。
  func createBodyMeasurement(_ dto: BodyMeasurementCreateDTO) async throws {
    try await requestVoid(path: "/api/body-measurements", method: "POST", body: dto)
  }

  /// 新しい順に測定を取る。件数で切るのは、記録の画面が見るのが直近の数日ぶんだけで、
  /// 全件だと10年ぶん 6,000 行以上が流れてくるため。
  func fetchBodyMeasurements(limit: Int) async throws -> [BodyMeasurementDTO] {
    struct Response: Decodable { let items: [BodyMeasurementDTO] }
    let response: Response = try await request(path: "/api/body-measurements?limit=\(limit)")
    return response.items
  }

  /// 期間内の測定を1回ずつ取る。
  ///
  /// 日次に集計したものではなく1回ずつ受け取るのは、同じ日に何度も乗るため。
  /// 平均に潰すと、朝と夜で1kg以上違うことが見えなくなる。
  /// 期間は計測した地域の暦日で、サーバーが `source_date` で絞る。
  func fetchBodyMeasurements(from: String, to: String) async throws -> [BodyMeasurementDTO] {
    struct Response: Decodable { let items: [BodyMeasurementDTO] }
    let response: Response = try await request(
      path: "/api/body-measurements?from=\(from)&to=\(to)&limit=5000")
    return response.items
  }

  /// 測定1件を消す。取り込みをやり直したいときや、他人が乗ったぶんが混ざったとき。
  func deleteBodyMeasurement(id: String) async throws {
    try await requestVoid(path: "/api/body-measurements/\(id)", method: "DELETE")
  }

  // MARK: - NutritionGoals

  func fetchNutritionGoals() async throws -> NutritionGoalsDTO {
    return try await request(path: "/api/nutrition-goals")
  }

  func updateNutritionGoals(_ dto: NutritionGoalsDTO) async throws -> NutritionGoalsDTO {
    return try await request(path: "/api/nutrition-goals", method: "PUT", body: dto)
  }

  // MARK: - AI

  func analyzeFoodImage(imageBase64: String, note: String? = nil) async throws -> AIAnalyzeResponse {
    return try await request(path: "/api/ai/analyze-food", method: "POST", body: AIAnalyzeRequest(imageBase64: imageBase64, note: note))
  }

  // MARK: - Auth

  func signIn(provider: String, identityToken: String) async throws -> AuthResponse {
    let body = AuthRequest(provider: provider, identityToken: identityToken)
    return try await request(path: "/api/auth/signin", method: "POST", body: body)
  }

  func refreshToken() async throws -> AuthResponse {
    return try await request(path: "/api/auth/refresh", method: "POST")
  }

  // MARK: - Export

  /// 全 LogItem を取得（CSV エクスポート用）
  func fetchAllLogItems() async throws -> [LogItemDTO] {
    var all: [LogItemDTO] = []
    var offset = 0
    let pageSize = 500
    while true {
      let resp: LogItemListResponse = try await request(
        path: "/api/log-items?limit=\(pageSize)&offset=\(offset)"
      )
      all.append(contentsOf: resp.items)
      if resp.items.count < pageSize { break }
      offset += pageSize
    }
    return all
  }
}
