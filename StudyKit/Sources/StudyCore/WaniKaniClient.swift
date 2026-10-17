import Foundation

/// Shared native URLSession boundary. Writes are single attempts; the durable repository
/// owns acknowledgement and reconciliation before another attempt can be authorized.
public struct WaniKaniClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    public init() { transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request, delegate: RejectRedirects())
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    } }
    public init(transport: @escaping Transport) { self.transport = transport }

    public enum APIError: Error, LocalizedError {
        case unauthorized, request(Int), invalidResponse, invalidPagination, invalidPayload, rateLimited(retryAt: Date)
        public var errorDescription: String? {
            switch self {
            case .unauthorized: "WaniKani rejected this token. Check that it is valid and has not been revoked."
            case .request(let code): "WaniKani returned HTTP \(code). Your saved data has been kept."
            case .invalidResponse: "WaniKani returned data that could not be read. Your saved data has been kept."
            case .invalidPagination: "An unexpected pagination link was rejected."
            case .rateLimited: "WaniKani is limiting requests. Saved work will remain pending until requests can resume."
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
        let pages: Pages
        let data: [Resource<Value>]
    }
    private struct Assignment: Decodable, Sendable { let subjectId: Int64; let srsStage: Int; let availableAt: String? }
    private struct Statistic: Decodable, Sendable {
        let subjectId: Int64; let subjectType: String
        let meaningCorrect: Int; let meaningIncorrect: Int; let meaningCurrentStreak: Int
        let readingCorrect: Int; let readingIncorrect: Int; let readingCurrentStreak: Int
        let hidden: Bool
    }
    private struct Level: Decodable, Sendable { let level: Int32; let unlockedAt: String?; let passedAt: String?; let abandonedAt: String? }
    private struct Subject: Decodable, Sendable {
        struct Meaning: Decodable, Sendable { let meaning: String; let primary: Bool }
        struct Reading: Decodable, Sendable { let reading: String }
        let characters: String?; let meanings: [Meaning]; let readings: [Reading]?
        let level: Int; let documentUrl: URL?; let hiddenAt: String?
    }

    @concurrent public func fetch(token: String) async throws -> StudySnapshot {
        async let user = account(token: token)
        async let assignments: [Resource<Assignment>] = pages("assignments", token: token)
        async let statistics: [Resource<Statistic>] = pages("review_statistics?hidden=false", token: token)
        async let levels: [Resource<Level>] = pages("level_progressions", token: token)
        async let subjects: [Resource<Subject>] = pages("subjects?hidden=false", token: token)
        let (u, a, s, l, subjectData) = try await (user, assignments, statistics, levels, subjects)
        return try StudySnapshot(accountID: u.id, username: u.username, currentLevel: u.level,
            onVacation: u.onVacation,
            assignments: a.map { StudyAssignment(subjectID: $0.data.subjectId, srsStageNumber: $0.data.srsStage, availableAt: try timestamp($0.data.availableAt)) },
            statistics: s.map { value in
                let d = value.data
                return try StudyAnswerStatistics(subjectID: d.subjectId, type: kind(d.subjectType), meaningCorrect: d.meaningCorrect,
                    meaningIncorrect: d.meaningIncorrect, meaningCurrentStreak: d.meaningCurrentStreak,
                    readingCorrect: d.readingCorrect, readingIncorrect: d.readingIncorrect, readingCurrentStreak: d.readingCurrentStreak, hidden: d.hidden)
            },
            levels: l.map { StudyLevel(level: $0.data.level, unlockedAt: try timestamp($0.data.unlockedAt), passedAt: try timestamp($0.data.passedAt), abandonedAt: try timestamp($0.data.abandonedAt)) },
            subjects: subjectData.filter { $0.data.hiddenAt == nil }.map { value in
                guard let id = value.id, let object = value.object else { throw APIError.invalidResponse }
                return try StudySubject(id: id, characters: value.data.characters ?? "", meaning: value.data.meanings.first(where: \.primary)?.meaning ?? value.data.meanings.first?.meaning ?? "",
                    readings: value.data.readings?.map(\.reading) ?? [], kind: kind(object), level: value.data.level, documentURL: value.data.documentUrl)
            })
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
        if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: string) }
        guard let date else { throw APIError.invalidResponse }
        return Int64(date.timeIntervalSince1970)
    }
    func pages<T: Decodable & Sendable>(_ endpoint: String, token: String) async throws -> [Resource<T>] {
        var next: URL? = URL(string: "https://api.wanikani.com/v2/\(endpoint)")!
        var visited = Set<URL>(), result = [Resource<T>]()
        while let url = next {
            guard visited.insert(url).inserted, visited.count <= 100 else { throw APIError.invalidPagination }
            let page: Page<T> = try await request(url, token: token)
            result += page.data
            if let link = page.pages.nextUrl {
                guard let parsed = URL(string: link), Self.isAllowed(parsed) else { throw APIError.invalidPagination }
                next = parsed
            } else { next = nil }
        }
        return result
    }
    private static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "api.wanikani.com" && url.user == nil && url.password == nil &&
            (url.port == nil || url.port == 443) && url.path.hasPrefix("/v2/")
    }
    enum Method: String, Sendable { case get = "GET", post = "POST", put = "PUT" }

    // Transport, rate-limit waiting and JSON decoding must not occupy a UI/store actor.
    @concurrent func request<T: Decodable & Sendable>(_ url: URL, token: String, method: Method = .get, body: Data? = nil) async throws -> T {
        guard Self.isAllowed(url) else { throw APIError.invalidPagination }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.unauthorized }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method.rawValue; request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("20170710", forHTTPHeaderField: "Wanikani-Revision")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        for attempt in 0...2 {
            try Task.checkCancellation()
            let (data, response) = try await transport(request)
            try Task.checkCancellation()
            guard let responseURL = response.url, Self.isAllowed(responseURL) else { throw APIError.invalidResponse }
            if response.statusCode == 401 || response.statusCode == 403 { throw APIError.unauthorized }
            if response.statusCode == 429 {
                let now = Date()
                let retryAt = Self.retryDate(response, now: now, fallback: Double(2 << attempt))
                let delay = retryAt.timeIntervalSince(now)
                // Never automatically replay a write, or shorten the server's requested wait.
                guard method == .get, attempt < 2, delay <= 30 else { throw APIError.rateLimited(retryAt: retryAt) }
                try await Task.sleep(for: .seconds(delay)); continue
            }
            guard (200...299).contains(response.statusCode) else { throw APIError.request(response.statusCode) }
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            do { return try decoder.decode(T.self, from: data) }
            catch { throw APIError.invalidResponse }
        }
        throw APIError.invalidResponse
    }

    static func retryDate(_ response: HTTPURLResponse, now: Date, fallback: TimeInterval) -> Date {
        var candidates = [now.addingTimeInterval(1)]
        if let reset = response.value(forHTTPHeaderField: "RateLimit-Reset").flatMap(Double.init), reset.isFinite {
            candidates.append(Date(timeIntervalSince1970: reset))
        }
        if let header = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = Double(header), seconds.isFinite {
                candidates.append(now.addingTimeInterval(max(1, seconds)))
            } else {
                let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
                format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                if let date = format.date(from: header) { candidates.append(date) }
            }
        }
        return candidates.count > 1 ? candidates.max()! : now.addingTimeInterval(fallback)
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
