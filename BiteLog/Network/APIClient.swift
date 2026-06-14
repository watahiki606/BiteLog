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

  /// 期間範囲（"yyyy-MM-dd"、両端含む）の LogItem を取得（統計用）
  func fetchLogItems(from: String, to: String) async throws -> [LogItemDTO] {
    let resp: LogItemListResponse = try await request(path: "/api/log-items?from=\(from)&to=\(to)")
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
