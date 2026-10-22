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
    started = true
    reader?.resume()
    reader = nil
    await withTaskCancellationHandler {
      await withCheckedContinuation { waiting = $0 }
    } onCancel: {
      Task { await self.sawCancellation() }
    }
  }
  private func sawCancellation() {
    cancelled = true
    cancellationReader?.resume()
    cancellationReader = nil
  }
  func cancellationObserved() async {
    if !cancelled { await withCheckedContinuation { cancellationReader = $0 } }
  }
  func entered() async { if !started { await withCheckedContinuation { reader = $0 } } }
  func resume() {
    waiting?.resume()
    waiting = nil
  }
}
private actor RefreshServer {
  var count = 0
  var userCount = 0
  let gate: RefreshGate?
  let fault: String?
  init(gate: RefreshGate? = nil, fault: String? = nil) {
    self.gate = gate
    self.fault = fault
  }
  var client: WaniKaniClient { .init { try await self.send($0) } }
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    count += 1
    let path = request.url!.lastPathComponent
    if path == "subjects", let gate { await gate.pause() }
    if fault == "failure", path == "voice_actors" { throw URLError(.notConnectedToInternet) }
    if fault == "rateLimit", path == "subjects" {
      return (
        Data(),
        HTTPURLResponse(
          url: request.url!, statusCode: 429, httpVersion: nil,
          headerFields: ["Retry-After": "3600"])!
      )
    }
    if path == "user" {
      userCount += 1
      if fault == "identity", userCount == 2 {
        var user = DownloadFixture.user
        var data = DownloadFixture.user["data"] as! [String: Any]
        data["id"] = "different-account"
        user["data"] = data
        return try DownloadFixture.response(request, object: user)
      }
    }
    return try DownloadFixture.response(request)
  }
}

struct NativeRefreshTests {
  @Test func cachedSubjectRefreshSurvivesReopenPreservesPendingWorkAndKeepsFailedWatermarks()
    async throws
  {
    let directory = URL.temporaryDirectory.appending(path: "subject-cache-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "study.store")
    let accountID = "fixture-user-id"
    let server = SubjectCacheFixture()
    let client = WaniKaniClient { try await server.respond($0) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let captured:
      (
        cursors: [String: String], catalog: Data, pending: [SavedReview], session: UUID,
        material: StudyMaterial
      )
    do {
      let store = try await StudyStore.open(at: url)
      _ = try await store.refresh(credentialID: "credential", token: "fixture", client: client)
      let saved = try #require(try await store.materials(accountID: accountID).first)
      var material = saved.material
      material.meaningNote = "Local pending note 日本語"
      _ = try await store.saveMaterial(
        material, accountID: accountID, expectedRevision: saved.revision)
      let revision = try await store.saveSession(
        session(), accountID: accountID, expectedRevision: nil)
      let pending = try await store.pendingReviews(accountID: accountID)
      let initial = try await store.catalog(accountID: accountID)
      await server.use(.changes)
      let snapshot = try await store.refresh(
        credentialID: "credential", token: "fixture", client: client)
      let catalog = try await store.catalog(accountID: accountID)
      #expect(catalog.map(\.id) == [1, 2, 3, 4, 5, 6])
      #expect(catalog.first?.japanese == "更新" && catalog.first?.hiddenAt != nil)
      #expect(
        try encoder.encode(initial.filter { $0.id != 1 })
          == encoder.encode(catalog.filter { $0.id != 1 && $0.id != 6 }))
      #expect(snapshot.subjects.map(\.id) == [2, 3, 5, 6] && snapshot.pendingReviews == 1)
      #expect(try await store.pendingReviews(accountID: accountID) == pending)
      #expect(try await store.session(accountID: accountID)?.revision == revision)
      #expect(try await store.materials(accountID: accountID).first?.material == material)
      let state = try #require(await store.accountState(accountID: accountID))
      #expect(state.cursors.values.contains(SubjectCacheFixture.changedAt))
      captured = (state.cursors, try encoder.encode(catalog), pending, revision, material)
    }
    let reopened = try await StudyStore.open(at: url)
    #expect(try await reopened.accountState(accountID: accountID)?.cursors == captured.cursors)
    await server.use(.unchanged)
    _ = try await reopened.refresh(credentialID: "credential", token: "fixture", client: client)
    let before = try #require(await reopened.accountState(accountID: accountID))
    #expect(before.cursors == captured.cursors)
    #expect(try await encoder.encode(reopened.catalog(accountID: accountID)) == captured.catalog)
    await server.use(.laterCategoryFailure)
    await #expect(throws: URLError.self) {
      try await reopened.refresh(credentialID: "credential", token: "fixture", client: client)
    }
    let after = try #require(await reopened.accountState(accountID: accountID))
    #expect(try encoder.encode(before) == encoder.encode(after))
    #expect(try await encoder.encode(reopened.catalog(accountID: accountID)) == captured.catalog)
    #expect(try await reopened.pendingReviews(accountID: accountID) == captured.pending)
    #expect(try await reopened.session(accountID: accountID)?.revision == captured.session)
    #expect(try await reopened.materials(accountID: accountID).first?.material == captured.material)
    #expect(
      await server.watermarks.prefix(3) == [
        nil, DownloadFixture.date, SubjectCacheFixture.changedAt,
      ])
  }

  private func store() async throws -> StudyStore {
    try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
  }
  private func download() async throws -> StudyDownload {
    try await WaniKaniClient(transport: DownloadFixture.response).download(token: "fixture")
  }
  private func session() throws -> StudySession {
    var session = try StudySession(items: [
      .init(id: 0, subjectID: 1, assignmentID: 101, srsStage: 5, hasReading: false)
    ])
    let next = session.nextQuestion()
    let question = try #require(next)
    _ = try session.mark(.correct, for: question, now: 100)
    return session
  }

  @Test func fullRefreshPersistsCatalogAndAllCategoriesAcrossReopen() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    do {
      let store = try await StudyStore.open(at: url)
      let snapshot = try await store.refresh(
        credentialID: "credential", token: "fixture",
        client: WaniKaniClient(transport: DownloadFixture.response))
      #expect(snapshot.subjects.count == 4 && snapshot.pendingReviews == 0)
    }
    let reopened = try await StudyStore.open(at: url)
    #expect(try await reopened.catalog(accountID: "fixture-user-id").count == 5)
    #expect(try await reopened.assignments(accountID: "fixture-user-id").first?.level == 1)
    #expect(try await reopened.materials(accountID: "fixture-user-id").first?.serverID == 201)
    let state = try #require(await reopened.accountState(accountID: "fixture-user-id"))
    #expect(
      state.profile.maxLevelGranted == 60 && state.voices.count == 1 && state.statistics.count == 1)
    #expect(
      state.levels.first?.completedAt != nil && state.audio.count == 2 && state.cursors.isEmpty)
    #expect(try await reopened.snapshot(credentialID: "credential")?.accountID == "fixture-user-id")
  }

  @Test func refreshPreservesPendingAnswersNotesAndHalfAnsweredSession() async throws {
    let store = try await store()
    let initial = try await download()
    _ = try await store.applyDownload(
      initial, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: initial.accountID))
    let original = try #require(await store.materials(accountID: initial.accountID).first)
    var note = original.material
    note.meaningNote = "edited before refresh"
    _ = try await store.saveMaterial(
      note, accountID: initial.accountID, expectedRevision: original.revision)
    let completed = try session()
    let completedRevision = try await store.saveSession(
      completed, accountID: initial.accountID, expectedRevision: nil)
    try await store.removeSession(accountID: initial.accountID, expectedRevision: completedRevision)
    var state = try StudySession(items: [.init(id: 0, subjectID: 5, assignmentID: 105, srsStage: 2)]
    )
    let next = state.nextQuestion()
    let question = try #require(next)
    _ = try state.mark(.correct, for: question, now: 101)
    #expect(state.completedIDs.isEmpty && state.items[0]?.hasAttempts == true)
    _ = try await store.saveSession(state, accountID: initial.accountID, expectedRevision: nil)
    let result = try await store.refresh(
      credentialID: "credential", token: "fixture",
      client: WaniKaniClient(transport: DownloadFixture.response))
    #expect(result.pendingReviews == 1 && result.assignments.isEmpty)
    #expect(try await store.pendingReviews(accountID: initial.accountID).count == 1)
    #expect(try await store.session(accountID: initial.accountID)?.session.items == state.items)
    #expect(
      try await store.materials(accountID: initial.accountID).first?.material.meaningNote
        == "edited before refresh")
  }

  @Test func acknowledgementDuringDownloadCannotRestoreAnOlderNote() async throws {
    let store = try await store()
    let initial = try await download()
    _ = try await store.applyDownload(
      initial, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: initial.accountID))
    let original = try #require(await store.materials(accountID: initial.accountID).first)
    var note = original.material
    note.meaningNote = "new server version"
    _ = try await store.saveMaterial(
      note, accountID: initial.accountID, expectedRevision: original.revision)
    let sent = try #require(await store.materials(accountID: initial.accountID).first)
    let gate = RefreshGate()
    let server = RefreshServer(gate: gate)
    let client = await server.client
    let refresh = Task {
      try await store.refresh(credentialID: "credential", token: "fixture", client: client)
    }
    await gate.entered()
    try await store.acknowledgeMaterial(sent)
    await gate.resume()
    _ = try await refresh.value
    let current = try #require(await store.materials(accountID: initial.accountID).first)
    #expect(
      !current.pending && current.material.meaningNote == "new server version"
        && current.revision != sent.revision)
  }

  @Test func uploadedAssignmentKeepsCatalogLevelAndWinsOverAnOlderDownload() async throws {
    let store = try await store()
    let initial = try await download()
    _ = try await store.applyDownload(
      initial, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: initial.accountID))
    let assignment = try #require(initial.assignments.first)
    var state = try StudySession(items: [assignment.sessionItem(id: 0, isLesson: false)])
    while let question = state.nextQuestion() {
      _ = try state.mark(.correct, for: question, now: 100)
    }
    _ = try await store.saveSession(state, accountID: initial.accountID, expectedRevision: nil)
    let beforeUpload = try await store.refreshBaseline(accountID: initial.accountID)
    let gate = RefreshGate()
    let server = RefreshServer(gate: gate)
    let reader = await server.client
    let refresh = Task {
      try await store.refresh(credentialID: "credential", token: "fixture", client: reader)
    }
    await gate.entered()
    let writer = WaniKaniClient { request in
      if request.httpMethod == "POST" {
        var assignment = DownloadFixture.assignment
        var data = assignment["data"] as! [String: Any]
        data["srs_stage"] = 6
        assignment["data"] = data
        return try DownloadFixture.response(
          request,
          object: [
            "id": 0, "object": "review",
            "data": [
              "assignment_id": 101, "subject_id": 1, "incorrect_meaning_answers": 0,
              "incorrect_reading_answers": 0, "ending_srs_stage": 6,
            ],
            "resources_updated": ["assignment": assignment],
          ])
      }
      return try DownloadFixture.response(request)
    }
    let report = try await store.uploadPending(
      accountID: initial.accountID, token: "fixture", client: writer)
    #expect(report.uploadedReviews == 1)
    await gate.resume()
    let snapshot = try await refresh.value
    let saved = try #require(await store.assignments(accountID: initial.accountID).first)
    #expect(saved.level == 1 && saved.srsStage == 6)
    #expect(snapshot.assignments.first?.srsStageNumber == 6 && snapshot.pendingReviews == 0)
    var empty = initial
    empty.assignments = []
    _ = try await store.applyDownload(empty, credentialID: "credential", baseline: beforeUpload)
    #expect(try await store.assignments(accountID: initial.accountID) == [saved])
    #expect(
      try await store.accountState(accountID: initial.accountID)?.progress.first {
        $0.subjectID == saved.subjectID
      }?.srsStage == 6)
    #expect(try await store.pendingReviews(accountID: initial.accountID).isEmpty)
    var fresh = initial
    fresh.assignments = [saved]
    let current = try await store.refreshBaseline(accountID: initial.accountID)
    let accepted = try await store.applyDownload(
      fresh, credentialID: "credential", baseline: current)
    #expect(try await store.assignments(accountID: initial.accountID) == [saved])
    #expect(accepted.assignments.count == 1 && accepted.assignments.first?.srsStageNumber == 6)
  }

  @Test func fullReplacementRemovesStaleRowsButRetainsPendingRecoveryContent() async throws {
    let store = try await store()
    let initial = try await download()
    _ = try await store.applyDownload(
      initial, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: initial.accountID))
    let state = try session()
    _ = try await store.saveSession(state, accountID: initial.accountID, expectedRevision: nil)
    #expect(!initial.voices.isEmpty && !initial.statistics.isEmpty && !initial.levels.isEmpty)
    #expect(initial.subjects.contains { !$0.audio.isEmpty })
    var empty = initial
    empty.subjects = []
    empty.assignments = []
    empty.materials = []
    empty.voices = []
    empty.statistics = []
    empty.levels = []
    _ = try await store.applyDownload(
      empty, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: initial.accountID))
    let catalog = try await store.catalog(accountID: initial.accountID)
    #expect(catalog.count == 1 && catalog.first?.id == 1 && catalog.first?.hiddenAt != nil)
    #expect(try await store.materials(accountID: initial.accountID).isEmpty)
    #expect(try await store.pendingReviews(accountID: initial.accountID).count == 1)
    #expect(try await store.snapshot(credentialID: "credential")?.subjects.isEmpty == true)
    let accountState = try #require(await store.accountState(accountID: initial.accountID))
    #expect(
      accountState.voices.isEmpty && accountState.statistics.isEmpty && accountState.audio.isEmpty
        && accountState.levels.isEmpty)
    #expect(accountState.cursors.isEmpty)

  }

  @Test(arguments: ["failure", "identity"])
  func failedOrChangedAccountDownloadPreservesThePriorStore(fault: String) async throws {
    let store = try await store()
    let initial = try await download()
    _ = try await store.applyDownload(
      initial, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: initial.accountID))
    let note = try #require(await store.materials(accountID: initial.accountID).first)
    let draft = StudyMaterial(
      subjectID: 1, meaningNote: "Pending during failed refresh 🐰\nLine two",
      readingNote: "Exact reading\nいち", meaningSynonyms: ["Exact", "一"])
    try await store.saveSubjectMaterial(
      draft, accountID: initial.accountID, expectedRevision: note.revision)
    let completed = try session()
    let revision = try await store.saveSession(
      completed, accountID: initial.accountID, expectedRevision: nil)
    let pending = try await store.pendingReviews(accountID: initial.accountID)
    let pendingMaterial = try #require(await store.materials(accountID: initial.accountID).first)
    let server = RefreshServer(fault: fault)
    let client = await server.client
    await #expect(throws: (any Error).self) {
      try await store.refresh(credentialID: "credential", token: "fixture", client: client)
    }
    #expect(try await store.snapshot(credentialID: "credential")?.savedAt == initial.fetchedAt)
    #expect(try await store.catalog(accountID: initial.accountID).count == 5)
    #expect(try await store.catalog(accountID: "different-account").isEmpty)
    #expect(try await store.pendingReviews(accountID: initial.accountID) == pending)
    #expect(try await store.session(accountID: initial.accountID)?.revision == revision)
    let retained = try #require(await store.materials(accountID: initial.accountID).first)
    #expect(
      retained.material == draft && retained.pending
        && retained.revision == pendingMaterial.revision)
  }

  @Test func cancellationAndOverlappingRefreshDoNotPublishLateResults() async throws {
    let store = try await store()
    let gate = RefreshGate()
    let server = RefreshServer(gate: gate)
    let client = await server.client
    let first = Task {
      try await store.refresh(credentialID: "credential", token: "fixture", client: client)
    }
    await gate.entered()
    await #expect(throws: StudyUploadError.self) {
      try await store.refresh(credentialID: "other", token: "fixture", client: client)
    }
    let transition = Task { await store.cancelSynchronization() }
    await gate.cancellationObserved()
    await gate.resume()
    await transition.value
    await #expect(throws: CancellationError.self) { try await first.value }
    #expect(try await store.snapshot(credentialID: "credential") == nil)
    #expect(try await store.catalog(accountID: "fixture-user-id").isEmpty)
  }

  @Test func refreshHonorsDurableAccountBackoffBeforeAnyFurtherRequest() async throws {
    let store = try await store()
    let initial = try await download()
    _ = try await store.applyDownload(
      initial, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: initial.accountID))
    let server = RefreshServer(fault: "rateLimit")
    let client = await server.client
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await store.refresh(credentialID: "credential", token: "fixture", client: client)
    }
    let count = await server.count
    #expect(try await store.uploadRetryDate(accountID: initial.accountID)! > Date())
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await store.refresh(credentialID: "credential", token: "fixture", client: client)
    }
    #expect(await server.count == count)
  }
}

extension NativeRefreshTests {
  @Test func pendingMaterialKeepsExactContentAndRevisionAfterStaleFullRefreshAndReopen()
    async throws
  {
    let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let edited = StudyMaterial(
      subjectID: 1, meaningNote: "  Offline\u{0000} note 🐰\nSecond line",
      readingNote: "\nいち  ", meaningSynonyms: ["One, alone", "First\nonly", "一"])
    let expectedRevision: UUID
    let expectedServerID: Int64?
    do {
      let store = try await StudyStore.open(at: url)
      let initial = try await download()
      _ = try await store.applyDownload(
        initial, credentialID: "credential",
        baseline: store.refreshBaseline(accountID: initial.accountID))
      let baseline = try await store.refreshBaseline(accountID: initial.accountID)
      let original = try await store.subjectDetails(subjectID: 1, accountID: initial.accountID)
      try await store.saveSubjectMaterial(
        edited, accountID: initial.accountID,
        expectedRevision: original.savedMaterial?.revision)
      let pending = try #require(await store.materials(accountID: initial.accountID).first)
      expectedRevision = pending.revision
      expectedServerID = pending.serverID
      _ = try await store.applyDownload(initial, credentialID: "credential", baseline: baseline)
      var empty = initial
      empty.materials = []
      _ = try await store.applyDownload(empty, credentialID: "credential", baseline: baseline)
      let saved = try #require(await store.materials(accountID: initial.accountID).first)
      #expect(saved.material == edited && saved.pending && saved.revision == expectedRevision)
    }
    let reopened = try await StudyStore.open(at: url)
    let restored = try #require(await reopened.materials(accountID: "fixture-user-id").first)
    #expect(
      restored.material == edited && restored.pending && restored.revision == expectedRevision)
    #expect(
      restored.serverID == expectedServerID && restored.attemptedRevision == nil
        && restored.issue == nil)
    try await reopened.acknowledgeMaterial(restored)
    let acknowledged = try #require(await reopened.materials(accountID: "fixture-user-id").first)
    #expect(!acknowledged.pending && acknowledged.material == edited)
    #expect(acknowledged.revision != restored.revision)
    let authoritative = StudyMaterial(
      subjectID: 1, meaningNote: "Server edit after acknowledgement",
      readingNote: "Fresh いち", meaningSynonyms: ["Fresh server synonym"])
    var fresh = try await download()
    fresh.materials = [.init(id: 991, value: authoritative)]
    let freshBaseline = try await reopened.refreshBaseline(accountID: "fixture-user-id")
    _ = try await reopened.applyDownload(
      fresh, credentialID: "credential", baseline: freshBaseline)
    let accepted = try #require(await reopened.materials(accountID: "fixture-user-id").first)
    #expect(accepted.material == authoritative && !accepted.pending && accepted.serverID == 991)
    #expect(accepted.revision != acknowledged.revision)
  }

  @Test func replacementAssignmentIDsCannotDuplicateOrResurrectPendingReviews() async throws {
    let store = try await store()
    var value = try await download()
    _ = try await store.applyDownload(
      value, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: value.accountID))
    var replacement = CatalogAssignment(id: 201, subjectID: 1, kind: .kanji)
    replacement.level = 1
    replacement.srsStage = 4
    replacement.startedAt = 1
    replacement.availableAt = 1
    value.assignments = [replacement]
    _ = try await store.applyDownload(
      value, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: value.accountID))
    #expect(try await store.assignments(accountID: value.accountID) == [replacement])
    let baseline = try await store.refreshBaseline(accountID: value.accountID)
    var session = try StudySession(
      items: [replacement.sessionItem(id: 0, isLesson: false)], seed: 1)
    while let question = session.nextQuestion() {
      _ = try session.mark(.correct, for: question, now: 100)
    }
    try await store.saveSession(session, accountID: value.accountID, expectedRevision: nil)
    let pending = try await store.pendingReviews(accountID: value.accountID)
    var obsolete = CatalogAssignment(id: 301, subjectID: 1, kind: .kanji)
    obsolete.level = 1
    obsolete.srsStage = 1
    obsolete.startedAt = 1
    obsolete.availableAt = 1
    value.assignments = [obsolete]
    let snapshot = try await store.applyDownload(
      value, credentialID: "credential", baseline: baseline)
    #expect(try await store.assignments(accountID: value.accountID) == [replacement])
    #expect(try await store.pendingReviews(accountID: value.accountID) == pending)
    #expect(pending.count == 1 && snapshot.pendingReviews == 1 && snapshot.assignments.isEmpty)
    #expect(snapshot.pendingSubjectIDs == Set(pending.map(\.subjectID)))
    #expect(try await store.accountState(accountID: value.accountID)?.progress.first?.srsStage == 4)
  }

  @Test func fullAssignmentRefreshPreservesPendingAndOtherMistakesWhilePruningObsoleteProgress()
    async throws
  {
    let store = try await store()
    var value = try await download()
    var source = NativeStoreFixture(profile: value.profile)
    source.subjects = value.subjects
    for id: Int64 in [1, 2, 3] {
      let kind = try #require(value.subjects.first { $0.id == id }).kind
      var assignment = CatalogAssignment(id: 100 + id, subjectID: id, kind: kind)
      assignment.level = 1
      assignment.srsStage = id == 1 ? 5 : 2
      assignment.startedAt = 1
      assignment.availableAt = 1
      source.assignments.append(assignment)
      source.progress.append(
        .init(
          subjectID: id, level: 1, srsStage: assignment.srsStage,
          kind: assignment.kind, lastMistakeLocalTime: "Exact local mistake \(id)",
          legacyRevision: id, lastMistakeAt: 100 + id))
    }
    let queued = StudyReviewSubmission(
      itemID: 0, subjectID: 1, assignmentID: 101, isLesson: false,
      meaningWrong: true, readingWrong: false, meaningWrongCount: 2, readingWrongCount: 0,
      createdAt: 200)
    source.pendingReviews = [.init(assignment: source.assignments[0], submission: queued)]
    try await store.seedFixture(source, accountID: value.accountID, credentialID: "credential")
    let pending = try await store.pendingReviews(accountID: value.accountID)
    var changed = CatalogAssignment(id: 202, subjectID: 2, kind: source.assignments[1].kind)
    changed.level = 1
    changed.srsStage = 4
    changed.startedAt = 1
    changed.availableAt = 1
    var stale = source.assignments[0]
    stale.srsStage = 1
    value.assignments = [stale, changed]
    let snapshot = try await store.applyDownload(
      value, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: value.accountID))
    let progress = try #require(await store.accountState(accountID: value.accountID)).progress
    #expect(progress.map(\.subjectID).sorted() == [1, 2])
    let kept = try #require(progress.first { $0.subjectID == 1 })
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    #expect(try encoder.encode(kept) == encoder.encode(source.progress[0]))
    let other = try #require(progress.first { $0.subjectID == 2 })
    #expect(
      other.srsStage == 4 && other.lastMistakeLocalTime == source.progress[1].lastMistakeLocalTime)
    #expect(
      other.lastMistakeAt == source.progress[1].lastMistakeAt
        && other.legacyRevision == source.progress[1].legacyRevision)
    #expect(try await store.pendingReviews(accountID: value.accountID) == pending)
    #expect(pending.count == 1 && pending.first?.submission == queued)
    #expect(snapshot.pendingReviews == 1 && snapshot.assignments.map(\.subjectID) == [2])
    #expect(try await store.assignments(accountID: value.accountID).map(\.id) == [202])
  }
}
