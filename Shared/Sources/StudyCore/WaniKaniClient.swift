import Foundation

/// The native repository uses typed server values; URLSession supplies the production service.
public protocol WaniKaniService: Sendable {
  func account(token: String) async throws -> WaniKaniAccount
  func download(token: String) async throws -> StudyDownload
  func assignment(subjectID: Int64, token: String) async throws -> CatalogAssignment?
  func material(subjectID: Int64, token: String) async throws -> WaniKaniMaterial?
  func submit(_ answer: StudyReviewSubmission, token: String, now: Date) async throws
    -> CatalogAssignment
  func writeMaterial(_ value: StudyMaterial, serverID: Int64?, token: String) async throws
    -> WaniKaniMaterial
}
extension WaniKaniService {
  public func submit(_ answer: StudyReviewSubmission, token: String) async throws
    -> CatalogAssignment
  {
    try await submit(answer, token: token, now: .now)
  }
}

/// Shared native URLSession boundary. Writes are single attempts; the durable repository
/// owns acknowledgement and reconciliation before another attempt can be authorized.
public struct WaniKaniClient: WaniKaniService {
  public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
  public static let defaultBaseURL = URL(string: "https://api.wanikani.com/v2")!
  private let baseURL: URL
  private let transport: Transport
  public init(baseURL: URL = Self.defaultBaseURL) {
    self.baseURL = baseURL
    transport = { request in
      let (data, response) = try await URLSession.shared.data(
        for: request, delegate: RejectRedirects())
      guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
      return (data, http)
    }
  }
  public init(baseURL: URL = Self.defaultBaseURL, transport: @escaping Transport) {
    self.baseURL = baseURL
    self.transport = transport
  }

  public enum APIError: Error, LocalizedError {
    case unauthorized
    case request(Int)
    case invalidResponse, invalidPagination, invalidPayload
    case rateLimited(retryAt: Date)
    public var errorDescription: String? {
      switch self {
      case .unauthorized:
        "WaniKani rejected this token. Check that it is valid and has not been revoked."
      case .request(let code): "WaniKani returned HTTP \(code). Your saved data has been kept."
      case .invalidResponse:
        "WaniKani returned data that could not be read. Your saved data has been kept."
      case .invalidPagination: "An unexpected pagination link was rejected."
      case .rateLimited:
        "WaniKani is limiting requests. Saved work will remain pending until requests can resume."
      case .invalidPayload: "The saved submission is invalid. It has not been sent."
      }
    }
  }
  struct Resource<Value: Decodable & Sendable>: Decodable, Sendable {
    let id: Int64?
    let object: String?
    let data: Value
  }
  private struct Page<Value: Decodable & Sendable>: Decodable, Sendable {
    struct Pages: Decodable, Sendable { let nextUrl: String? }
    let object: String
    let totalCount: Int
    let pages: Pages
    let data: [Resource<Value>]
  }
  /// Statistics remains a projection of the complete native download, not a second decoder.
  public func fetch(token: String) async throws -> StudySnapshot {
    try await download(token: token).snapshot
  }
  func kind(_ value: String) throws(APIError) -> SubjectKind {
    switch value {
    case "radical": .radical
    case "kanji": .kanji
    case "vocabulary", "kana_vocabulary": .vocabulary
    default: throw APIError.invalidResponse
    }
  }
  func timestamp(_ string: String?) throws(APIError) -> Int64 {
    guard let string else { return 0 }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: string)
    if date == nil {
      formatter.formatOptions = [.withInternetDateTime]
      date = formatter.date(from: string)
    }
    guard let date else { throw APIError.invalidResponse }
    return Int64(date.timeIntervalSince1970)
  }
  func pages<T: Decodable & Sendable>(_ endpoint: String, token: String) async throws -> [Resource<
    T
  >] {
    var next: URL? = self.endpoint(endpoint)
    var visited = Set<URL>()
    var result = [Resource<T>]()
    var expectedCount: Int?
    while let url = next {
      guard visited.insert(url).inserted, visited.count <= 100 else {
        throw APIError.invalidPagination
      }
      let page: Page<T> = try await request(url, token: token)
      guard page.object == "collection", page.totalCount >= 0,
        expectedCount == nil || expectedCount == page.totalCount,
        page.data.allSatisfy({ ($0.id ?? 0) > 0 && $0.object != nil })
      else { throw APIError.invalidResponse }
      expectedCount = page.totalCount
      result += page.data
      guard result.count <= page.totalCount else { throw APIError.invalidResponse }
      if let link = page.pages.nextUrl {
        guard let parsed = URL(string: link), isAllowed(parsed), parsed.path == url.path else {
          throw APIError.invalidPagination
        }
        next = parsed
      } else {
        next = nil
      }
    }
    guard result.count == expectedCount else { throw APIError.invalidResponse }
    return result
  }
  func endpoint(_ path: String) -> URL {
    URL(
      string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        + path)!
  }
  private func isAllowed(_ url: URL) -> Bool {
    guard let scheme = baseURL.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = baseURL.host, !host.isEmpty, baseURL.user == nil, baseURL.password == nil,
      baseURL.query == nil, baseURL.fragment == nil, url.user == nil, url.password == nil,
      url.fragment == nil, url.scheme?.lowercased() == scheme,
      url.host?.lowercased() == host.lowercased(),
      (url.port ?? (scheme == "https" ? 443 : 80))
        == (baseURL.port ?? (scheme == "https" ? 443 : 80))
    else { return false }
    let path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
      return false
    }
    return url.path.hasPrefix(path.isEmpty ? "/" : "/" + path + "/")
  }
  private struct APIMessage: Decodable { let error: String? }
  enum Method: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
  }

  // Transport, rate-limit waiting and JSON decoding must not occupy a UI/store actor.
  @concurrent func request<T: Decodable & Sendable>(
    _ url: URL, token: String, method: Method = .get, body: Data? = nil
  ) async throws -> T {
    guard isAllowed(url) else { throw APIError.invalidPagination }
    guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw APIError.unauthorized
    }
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    request.httpMethod = method.rawValue
    request.httpBody = body
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("20170710", forHTTPHeaderField: "Wanikani-Revision")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if body != nil {
      request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    }
    for attempt in 0...2 {
      try Task.checkCancellation()
      let (data, response) = try await transport(request)
      try Task.checkCancellation()
      guard let responseURL = response.url, isAllowed(responseURL) else {
        throw APIError.invalidResponse
      }
      if response.statusCode == 401 || response.statusCode == 403 {
        let message = try? JSONDecoder().decode(APIMessage.self, from: data)
        if method == .get, url.path == endpoint("user").path,
          message?.error?.localizedCaseInsensitiveContains("hibernat") == true
        {
          throw StudySignInError.hibernating
        }
        throw APIError.unauthorized
      }
      if response.statusCode == 429 {
        let now = Date()
        let retryAt = Self.retryDate(response, now: now, fallback: Double(2 << attempt))
        let delay = retryAt.timeIntervalSince(now)
        // Never automatically replay a write, or shorten the server's requested wait.
        guard method == .get, attempt < 2, delay <= 30 else {
          throw APIError.rateLimited(retryAt: retryAt)
        }
        try await Task.sleep(for: .seconds(delay))
        continue
      }
      guard (200...299).contains(response.statusCode) else {
        throw APIError.request(response.statusCode)
      }
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      do { return try decoder.decode(T.self, from: data) } catch { throw APIError.invalidResponse }
    }
    throw APIError.invalidResponse
  }

  static func retryDate(_ response: HTTPURLResponse, now: Date, fallback: TimeInterval) -> Date {
    var candidates = [now.addingTimeInterval(1)]
    if let reset = response.value(forHTTPHeaderField: "RateLimit-Reset").flatMap(Double.init),
      reset.isFinite
    {
      candidates.append(Date(timeIntervalSince1970: reset))
    }
    if let header = response.value(forHTTPHeaderField: "Retry-After") {
      if let seconds = Double(header), seconds.isFinite {
        candidates.append(now.addingTimeInterval(max(1, seconds)))
      } else {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = format.date(from: header) { candidates.append(date) }
      }
    }
    return candidates.count > 1 ? candidates.max()! : now.addingTimeInterval(fallback)
  }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
