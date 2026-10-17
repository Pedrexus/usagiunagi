import Foundation
import StudyCore
import StudyTestSupport
import Testing
@testable import StudyPersistence

private actor RefreshGate {
    private var started = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var reader: CheckedContinuation<Void, Never>?
    private var cancelled = false
    private var cancellationReader: CheckedContinuation<Void, Never>?
    func pause() async {
        started = true; reader?.resume(); reader = nil
        await withTaskCancellationHandler { await withCheckedContinuation { waiting = $0 } } onCancel: {
            Task { await self.sawCancellation() }
        }
    }
    private func sawCancellation() { cancelled = true; cancellationReader?.resume(); cancellationReader = nil }
    func cancellationObserved() async { if !cancelled { await withCheckedContinuation { cancellationReader = $0 } } }
    func entered() async { if !started { await withCheckedContinuation { reader = $0 } } }
    func resume() { waiting?.resume(); waiting = nil }
}
private actor RefreshServer {
    var count = 0
    var userCount = 0
    let gate: RefreshGate?
    let fault: String?
    init(gate: RefreshGate? = nil, fault: String? = nil) { self.gate = gate; self.fault = fault }
    var client: WaniKaniClient { .init { try await self.send($0) } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        let path = request.url!.lastPathComponent
        if path == "subjects", let gate { await gate.pause() }
        if fault == "failure", path == "voice_actors" { throw URLError(.notConnectedToInternet) }
        if fault == "rateLimit", path == "subjects" {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "3600"])!)
        }
        if path == "user" {
            userCount += 1
            if fault == "identity", userCount == 2 {
                var user = DownloadFixture.user, data = DownloadFixture.user["data"] as! [String: Any]
                data["id"] = "different-account"; user["data"] = data
                return try DownloadFixture.response(request, object: user)
            }
        }
        return try DownloadFixture.response(request)
    }
}

struct NativeRefreshTests {
    private func store() async throws -> StudyStore {
        try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    }
    private func download() async throws -> StudyDownload {
        try await WaniKaniClient(transport: DownloadFixture.response).download(token: "fixture")
    }
    private func session() throws -> StudySession {
        var session = try StudySession(items: [.init(id: 0, subjectID: 1, assignmentID: 101, srsStage: 5, hasReading: false)])
        let next = session.nextQuestion(), question = try #require(next)
        _ = try session.mark(.correct, for: question, now: 100)
        return session
    }

    @Test func fullRefreshPersistsCatalogAndAllCategoriesAcrossReopen() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "study.store")
        do {
            let store = try await StudyStore.open(at: url)
            let snapshot = try await store.refresh(credentialID: "credential", token: "fixture", client: .init(transport: DownloadFixture.response))
            #expect(snapshot.subjects.count == 4 && snapshot.pendingReviews == 0)
        }
        let reopened = try await StudyStore.open(at: url)
        #expect(try await reopened.catalog(accountID: "fixture-user-id").count == 5)
        #expect(try await reopened.assignments(accountID: "fixture-user-id").first?.level == 1)
        #expect(try await reopened.materials(accountID: "fixture-user-id").first?.serverID == 201)
        let state = try #require(await reopened.accountState(accountID: "fixture-user-id"))
        #expect(state.profile.maxLevelGranted == 60 && state.voices.count == 1 && state.statistics.count == 1)
        #expect(state.levels.first?.completedAt != nil && state.audio.count == 2 && state.cursors.isEmpty)
        #expect(try await reopened.snapshot(credentialID: "credential")?.accountID == "fixture-user-id")
    }

    @Test func refreshPreservesPendingAnswersNotesAndHalfAnsweredSession() async throws {
        let store = try await store(), initial = try await download()
        _ = try await store.applyDownload(initial, credentialID: "credential", baseline: store.refreshBaseline(accountID: initial.accountID))
        let original = try #require(await store.materials(accountID: initial.accountID).first)
        var note = original.material; note.meaningNote = "edited before refresh"
        _ = try await store.saveMaterial(note, accountID: initial.accountID, expectedRevision: original.revision)
        let completed = try session()
        let completedRevision = try await store.saveSession(completed, accountID: initial.accountID, expectedRevision: nil)
        try await store.removeSession(accountID: initial.accountID, expectedRevision: completedRevision)
        var state = try StudySession(items: [.init(id: 0, subjectID: 5, assignmentID: 105, srsStage: 2)])
        let next = state.nextQuestion(), question = try #require(next)
        _ = try state.mark(.correct, for: question, now: 101)
        #expect(state.completedIDs.isEmpty && state.items[0]?.hasAttempts == true)
        _ = try await store.saveSession(state, accountID: initial.accountID, expectedRevision: nil)
        let result = try await store.refresh(credentialID: "credential", token: "fixture", client: .init(transport: DownloadFixture.response))
        #expect(result.pendingReviews == 1 && result.assignments.isEmpty)
        #expect(try await store.pendingReviews(accountID: initial.accountID).count == 1)
        #expect(try await store.session(accountID: initial.accountID)?.session.items == state.items)
        #expect(try await store.materials(accountID: initial.accountID).first?.material.meaningNote == "edited before refresh")
    }

    @Test func acknowledgementDuringDownloadCannotRestoreAnOlderNote() async throws {
        let store = try await store(), initial = try await download()
        _ = try await store.applyDownload(initial, credentialID: "credential", baseline: store.refreshBaseline(accountID: initial.accountID))
        let original = try #require(await store.materials(accountID: initial.accountID).first)
        var note = original.material; note.meaningNote = "new server version"
        _ = try await store.saveMaterial(note, accountID: initial.accountID, expectedRevision: original.revision)
        let sent = try #require(await store.materials(accountID: initial.accountID).first)
        let gate = RefreshGate(), server = RefreshServer(gate: gate)
        let client = await server.client
        let refresh = Task { try await store.refresh(credentialID: "credential", token: "fixture", client: client) }
        await gate.entered()
        try await store.acknowledgeMaterial(sent)
        await gate.resume(); _ = try await refresh.value
        let current = try #require(await store.materials(accountID: initial.accountID).first)
        #expect(!current.pending && current.material.meaningNote == "new server version" && current.revision != sent.revision)
    }

    @Test func uploadedAssignmentKeepsCatalogLevelAndWinsOverAnOlderDownload() async throws {
        let store = try await store(), initial = try await download()
        _ = try await store.applyDownload(initial, credentialID: "credential", baseline: store.refreshBaseline(accountID: initial.accountID))
        let assignment = try #require(initial.assignments.first)
        var state = try StudySession(items: [assignment.sessionItem(id: 0, isLesson: false)])
        while let question = state.nextQuestion() { _ = try state.mark(.correct, for: question, now: 100) }
        _ = try await store.saveSession(state, accountID: initial.accountID, expectedRevision: nil)
        let gate = RefreshGate(), server = RefreshServer(gate: gate), reader = await server.client
        let refresh = Task { try await store.refresh(credentialID: "credential", token: "fixture", client: reader) }
        await gate.entered()
        let writer = WaniKaniClient { request in
            if request.httpMethod == "POST" {
                var assignment = DownloadFixture.assignment, data = assignment["data"] as! [String: Any]
                data["srs_stage"] = 6; assignment["data"] = data
                return try DownloadFixture.response(request, object: ["id": 0, "object": "review",
                    "data": ["assignment_id": 101, "subject_id": 1, "incorrect_meaning_answers": 0,
                             "incorrect_reading_answers": 0, "ending_srs_stage": 6],
                    "resources_updated": ["assignment": assignment]])
            }
            return try DownloadFixture.response(request)
        }
        let report = try await store.uploadPending(accountID: initial.accountID, token: "fixture", client: writer)
        #expect(report.uploadedReviews == 1)
        await gate.resume(); let snapshot = try await refresh.value
        let saved = try #require(await store.assignments(accountID: initial.accountID).first)
        #expect(saved.level == 1 && saved.srsStage == 6)
        #expect(snapshot.assignments.first?.srsStageNumber == 6 && snapshot.pendingReviews == 0)
    }

    @Test func fullReplacementRemovesStaleRowsButRetainsPendingRecoveryContent() async throws {
        let store = try await store(), initial = try await download()
        _ = try await store.applyDownload(initial, credentialID: "credential", baseline: store.refreshBaseline(accountID: initial.accountID))
        let state = try session()
        _ = try await store.saveSession(state, accountID: initial.accountID, expectedRevision: nil)
        var empty = initial; empty.subjects = []; empty.assignments = []; empty.materials = []
        _ = try await store.applyDownload(empty, credentialID: "credential", baseline: store.refreshBaseline(accountID: initial.accountID))
        let catalog = try await store.catalog(accountID: initial.accountID)
        #expect(catalog.count == 1 && catalog.first?.id == 1 && catalog.first?.hiddenAt != nil)
        #expect(try await store.materials(accountID: initial.accountID).isEmpty)
        #expect(try await store.pendingReviews(accountID: initial.accountID).count == 1)
        #expect(try await store.snapshot(credentialID: "credential")?.subjects.isEmpty == true)
    }

    @Test(arguments: ["failure", "identity"])
    func failedOrChangedAccountDownloadPreservesThePriorStore(fault: String) async throws {
        let store = try await store(), initial = try await download()
        _ = try await store.applyDownload(initial, credentialID: "credential", baseline: store.refreshBaseline(accountID: initial.accountID))
        let server = RefreshServer(fault: fault), client = await server.client
        await #expect(throws: (any Error).self) { try await store.refresh(credentialID: "credential", token: "fixture", client: client) }
        #expect(try await store.snapshot(credentialID: "credential")?.savedAt == initial.fetchedAt)
        #expect(try await store.catalog(accountID: initial.accountID).count == 5)
        #expect(try await store.catalog(accountID: "different-account").isEmpty)
    }

    @Test func cancellationAndOverlappingRefreshDoNotPublishLateResults() async throws {
        let store = try await store(), gate = RefreshGate(), server = RefreshServer(gate: gate)
        let client = await server.client
        let first = Task { try await store.refresh(credentialID: "credential", token: "fixture", client: client) }
        await gate.entered()
        await #expect(throws: StudyUploadError.self) { try await store.refresh(credentialID: "other", token: "fixture", client: client) }
        let transition = Task { await store.cancelSynchronization() }
        await gate.cancellationObserved()
        await gate.resume()
        await transition.value
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await store.snapshot(credentialID: "credential") == nil)
        #expect(try await store.catalog(accountID: "fixture-user-id").isEmpty)
    }

    @Test func refreshHonorsDurableAccountBackoffBeforeAnyFurtherRequest() async throws {
        let store = try await store(), initial = try await download()
        _ = try await store.applyDownload(initial, credentialID: "credential", baseline: store.refreshBaseline(accountID: initial.accountID))
        let server = RefreshServer(fault: "rateLimit"), client = await server.client
        await #expect(throws: WaniKaniClient.APIError.self) { try await store.refresh(credentialID: "credential", token: "fixture", client: client) }
        let count = await server.count
        #expect(try await store.uploadRetryDate(accountID: initial.accountID)! > Date())
        await #expect(throws: WaniKaniClient.APIError.self) { try await store.refresh(credentialID: "credential", token: "fixture", client: client) }
        #expect(await server.count == count)
    }
}
