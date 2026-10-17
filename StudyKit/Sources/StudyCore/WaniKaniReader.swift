import Foundation

/// Reads complete account snapshots. Deliberately has no review/lesson write endpoint.
/// Existing iOS review uploads continue to use the durable legacy queue until it is migrated.
public struct WaniKaniReader: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    public init(transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReaderError.invalidResponse }
        return (data, http)
    }) { self.transport = transport }

    public enum ReaderError: Error, LocalizedError {
        case unauthorized, request(Int), invalidResponse, invalidPagination, rateLimited
        public var errorDescription: String? {
            switch self {
            case .unauthorized: "WaniKani rejected this token. Check that it is valid and has not been revoked."
            case .request(let code): "WaniKani returned HTTP \(code). Your saved snapshot has been kept."
            case .invalidResponse: "WaniKani returned data that could not be read. Your saved snapshot has been kept."
            case .invalidPagination: "An unexpected pagination link was rejected."
            case .rateLimited: "WaniKani is limiting requests. Please try again later."
            }
        }
    }
    private struct Resource<Value: Decodable & Sendable>: Decodable, Sendable {
        let id: Int64?
        let object: String?
        let data: Value
    }
    private struct Page<Value: Decodable & Sendable>: Decodable, Sendable {
        struct Pages: Decodable, Sendable { let nextUrl: String? }
        let pages: Pages
        let data: [Resource<Value>]
    }
    private struct User: Decodable, Sendable { let username: String; let level: Int; let vacationStartedAt: String? }
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

    public func fetch(token: String) async throws -> StudySnapshot {
        async let user: Resource<User> = request(URL(string: "https://api.wanikani.com/v2/user")!, token: token)
        async let assignments: [Resource<Assignment>] = pages("assignments", token: token)
        async let statistics: [Resource<Statistic>] = pages("review_statistics?hidden=false", token: token)
        async let levels: [Resource<Level>] = pages("level_progressions", token: token)
        async let subjects: [Resource<Subject>] = pages("subjects?hidden=false", token: token)
        let (u, a, s, l, subjectData) = try await (user, assignments, statistics, levels, subjects)
        return try StudySnapshot(username: u.data.username, currentLevel: u.data.level,
            onVacation: u.data.vacationStartedAt != nil,
            assignments: a.map { StudyAssignment(subjectID: $0.data.subjectId, srsStageNumber: $0.data.srsStage, availableAt: try timestamp($0.data.availableAt)) },
            statistics: s.map { value in
                let d = value.data
                return StudyAnswerStatistics(subjectID: d.subjectId, type: kind(d.subjectType), meaningCorrect: d.meaningCorrect,
                    meaningIncorrect: d.meaningIncorrect, meaningCurrentStreak: d.meaningCurrentStreak,
                    readingCorrect: d.readingCorrect, readingIncorrect: d.readingIncorrect, readingCurrentStreak: d.readingCurrentStreak, hidden: d.hidden)
            },
            levels: l.map { StudyLevel(level: $0.data.level, unlockedAt: try timestamp($0.data.unlockedAt), passedAt: try timestamp($0.data.passedAt), abandonedAt: try timestamp($0.data.abandonedAt)) },
            subjects: subjectData.filter { $0.data.hiddenAt == nil }.map { value in
                guard let id = value.id, let object = value.object else { throw ReaderError.invalidResponse }
                return StudySubject(id: id, characters: value.data.characters ?? "", meaning: value.data.meanings.first(where: \.primary)?.meaning ?? value.data.meanings.first?.meaning ?? "",
                    readings: value.data.readings?.map(\.reading) ?? [], kind: kind(object), level: value.data.level, documentURL: value.data.documentUrl)
            })
    }
    private func kind(_ value: String) -> SubjectKind { value == "radical" ? .radical : value == "kanji" ? .kanji : .vocabulary }
    private func timestamp(_ string: String?) throws -> Int64 {
        guard let string else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: string)
        if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: string) }
        guard let date else { throw ReaderError.invalidResponse }
        return Int64(date.timeIntervalSince1970)
    }
    private func pages<T: Decodable & Sendable>(_ endpoint: String, token: String) async throws -> [Resource<T>] {
        var next: URL? = URL(string: "https://api.wanikani.com/v2/\(endpoint)")!
        var visited = Set<URL>(), result = [Resource<T>]()
        while let url = next {
            guard visited.insert(url).inserted, visited.count <= 100 else { throw ReaderError.invalidPagination }
            let page: Page<T> = try await request(url, token: token)
            result += page.data
            if let link = page.pages.nextUrl {
                guard let parsed = URL(string: link), Self.isAllowed(parsed) else { throw ReaderError.invalidPagination }
                next = parsed
            } else { next = nil }
        }
        return result
    }
    private static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "api.wanikani.com" && url.user == nil && url.password == nil &&
            (url.port == nil || url.port == 443) && url.path.hasPrefix("/v2/")
    }
    private func request<T: Decodable & Sendable>(_ url: URL, token: String) async throws -> T {
        guard Self.isAllowed(url) else { throw ReaderError.invalidPagination }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("20170710", forHTTPHeaderField: "Wanikani-Revision")
        for attempt in 0...2 {
            try Task.checkCancellation()
            let (data, response) = try await transport(request)
            if response.statusCode == 401 || response.statusCode == 403 { throw ReaderError.unauthorized }
            if response.statusCode == 429 {
                guard attempt < 2 else { throw ReaderError.rateLimited }
                let delay = min(30, max(1, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(2 << attempt)))
                try await Task.sleep(for: .seconds(delay)); continue
            }
            guard (200...299).contains(response.statusCode) else { throw ReaderError.request(response.statusCode) }
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        }
        throw ReaderError.rateLimited
    }
}

/// An atomic snapshot cache, isolated from the legacy iOS review database.
public actor StudySnapshotCache {
    private struct Stored: Codable { let snapshot: StudySnapshot; let credentialID: String? }
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load(credentialID: String? = nil) throws -> StudySnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: url))
        return stored.credentialID == credentialID ? stored.snapshot : nil
    }
    public func save(_ snapshot: StudySnapshot, credentialID: String? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Stored(snapshot: snapshot, credentialID: credentialID)).write(to: url, options: .atomic)
    }
    public func remove() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
