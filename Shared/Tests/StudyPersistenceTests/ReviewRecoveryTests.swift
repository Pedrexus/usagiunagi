import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

private actor ReviewRecoveryServer {
  var identity = "fixture-user-id"
  var state = "changed"
  var limited = false
  var gate: RecoveryGate?
  private(set) var requests: [URLRequest] = []
  var writes: [URLRequest] { requests.filter { $0.httpMethod != "GET" } }
  var client: WaniKaniClient { .init { try await self.respond($0) } }
  func configure(
    identity: String = "fixture-user-id", state: String = "changed", limited: Bool = false
  ) {
    self.identity = identity
    self.state = state
    self.limited = limited
  }
  func pause(_ gate: RecoveryGate) { self.gate = gate }
  func respond(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    guard request.httpMethod == "GET" else { throw URLError(.unsupportedURL) }
    if request.url!.lastPathComponent == "user" {
      return try DownloadFixture.response(
        request,
        object: [
          "object": "user",
          "data": [
            "id": identity, "username": "fixture", "level": 1,
            "current_vacation_started_at": NSNull(),
          ],
        ])
    }
    guard request.url!.lastPathComponent == "assignments" else { throw URLError(.unsupportedURL) }
    if let gate {
      self.gate = nil
      await gate.pause()
    }
    if limited {
      return (
        Data("{}".utf8),
        HTTPURLResponse(
          url: request.url!, statusCode: 429, httpVersion: nil,
          headerFields: ["Retry-After": "120"])!
      )
    }
    let row = DownloadFixture.resource(
      state == "replaced" ? 901 : 101, "assignment",
      [
        "subject_id": 1, "subject_type": "kanji", "srs_stage": state == "unchanged" ? 3 : 4,
        "started_at": "1970-01-01T00:00:01Z", "unlocked_at": "1970-01-01T00:00:01Z",
        "available_at": state == "unchanged" ? "1970-01-01T00:01:40Z" : "2099-01-01T00:00:00Z",
        "hidden": state == "hidden",
      ])
    return try DownloadFixture.response(
      request, object: DownloadFixture.collection(state == "missing" ? [] : [row]))
  }
}

struct ReviewRecoveryTests {
  private let account = "fixture-user-id"
  private func store(
    at url: URL = URL(filePath: "/unused"), lesson: Bool = false,
    otherPending: Bool = false, accountID: String = "fixture-user-id"
  ) async throws -> StudyStore {
    let store = try await StudyStore.open(at: url, inMemory: url.path == "/unused")
    var profile = StudyAccountProfile(username: "fixture")
    profile.level = 1
    profile.maxLevelGranted = 60
    var subject = CatalogSubject(id: 1, kind: .kanji)
    subject.level = 1
    subject.japanese = "一"
    subject.meanings = [.init("One", role: .primary)]
    subject.readings = [.init("いち", isPrimary: true, kind: .onyomi)]
    var second = CatalogSubject(id: 2, kind: .radical)
    second.level = 1
    second.japanese = "二"
    second.meanings = [.init("Two", role: .primary)]
    var first = CatalogAssignment(id: 101, subjectID: 1, kind: .kanji)
    first.level = 1
    first.srsStage = lesson ? 0 : 3
    first.availableAt = lesson ? nil : 100
    first.startedAt = lesson ? nil : 1
    first.unlockedAt = 1
    var other = CatalogAssignment(id: 102, subjectID: 2, kind: .radical)
    other.level = 1
    other.srsStage = 2
    other.availableAt = 100
    other.startedAt = 1
    other.unlockedAt = 1
    var source = LegacyStudyExport(schemaVersion: 15, profile: profile)
    source.subjects = [subject, second]
    source.assignments = [first, other]
    source.progress = [
      .init(
        subjectID: 1, level: 1, srsStage: first.srsStage, kind: .kanji,
        lastMistakeLocalTime: "2026-10-17T10:00:00", legacyRevision: 17)
    ]
    source.materials = [
      .init(
        serverID: 202, value: .init(subjectID: 2, meaningNote: "Unrelated note"), pending: false,
        legacyRevision: 0)
    ]
    _ = try await store.importLegacyAccount(
      source, sourceID: "recovery-fixture", verifiedAccountID: accountID,
      verifiedUsername: "fixture", credentialID: "credential")
    var items = [
      StudySessionItem(
        id: 0, subjectID: 1, assignmentID: 101, srsStage: first.srsStage,
        availableAt: first.availableAt ?? 0, isLesson: lesson, isKanji: true, hasReading: false)
    ]
    if otherPending {
      items.append(
        .init(
          id: 1, subjectID: 2, assignmentID: 102, srsStage: 2, availableAt: 100, hasReading: false))
    }
    var session = try StudySession(items: items, seed: 1)
    while let question = session.nextQuestion() {
      _ = try session.mark(.correct, for: question, now: 200)
    }
    try await store.saveSession(session, accountID: accountID, expectedRevision: nil)
    let pending = try #require(
      await store.pendingReviews(accountID: accountID).first { $0.subjectID == 1 })
    try await store.beginReviewAttempt(pending)
    return store
  }
  private func pending(_ store: StudyStore) async throws -> SavedReview {
    try #require(await store.pendingReviews(accountID: account).first { $0.subjectID == 1 })
  }
  private func compare(_ store: StudyStore, _ server: ReviewRecoveryServer) async throws
    -> StudyReviewComparison
  {
    let result = try await store.compareSavedWork(
      .review(pending(store)), credentialID: "credential", token: "fixture", client: server.client)
    guard case .review(let value) = result else {
      Issue.record("Expected a review comparison")
      throw StudyRecoveryError.changed
    }
    return value
  }

  @Test(arguments: ["unchanged", "changed", "missing", "replaced", "hidden"])
  func comparisonNeverAcknowledgesOrRetriesAnUncertainAnswer(state: String) async throws {
    let store = try await store()
    let server = ReviewRecoveryServer()
    await server.configure(state: state)
    let before = try await pending(store)
    let value = try await compare(store, server)
    #expect(value.saved == before && (value.remote == nil) == (state == "missing"))
    #expect(try await pending(store) == before)
    #expect(try await store.archivedReviews(accountID: account).isEmpty)
    #expect(await server.writes.isEmpty)
    #expect(await server.requests.count == 2)
    #expect(await server.requests.allSatisfy { $0.url?.lastPathComponent != "reviews" })
  }

  @Test(arguments: [false, true])
  func archivedReviewOrLessonSurvivesRestartWithoutBecomingASubmission(lesson: Bool) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let server = ReviewRecoveryServer()
    let original: SavedReview
    do {
      let store = try await store(at: url, lesson: lesson)
      original = try await pending(store)
      let value = try await compare(store, server)
      let archived = try await store.archiveReview(value)
      #expect(archived.saved == original && archived.subject?.characters == "一")
      #expect(
        archived.cachedAssignment?.id == 101
          && archived.cachedProgress?.lastMistakeLocalTime == "2026-10-17T10:00:00"
      )
      #expect(archived.observedAssignment == value.remote)
      await #expect(throws: StudyRecoveryError.self) { try await store.archiveReview(value) }
    }
    let reopened = try await StudyStore.open(at: url)
    let archived = try #require(await reopened.archivedReviews(accountID: account).first)
    #expect(archived.saved == original && archived.saved.submission.isLesson == lesson)
    #expect(try await reopened.pendingReviews(accountID: account).isEmpty)
    #expect(
      try await reopened.snapshot(credentialID: "credential")?.requiresAssignmentRefresh == true)
    let catalog = try await reopened.subjectCatalog(accountID: account)
    #expect(catalog.requiresAssignmentRefresh)
    #expect(catalog.items.allSatisfy { $0.status.stage == nil })
    #expect(try await reopened.assignments(accountID: account).allSatisfy { $0.subjectID != 1 })
    #expect(
      try await reopened.snapshot(credentialID: "credential")?.assignments.allSatisfy {
        $0.subjectID != 1
      } == true)
    #expect(
      try await reopened.accountState(accountID: account)?.progress.first?.lastMistakeLocalTime
        == "2026-10-17T10:00:00")
    let saved = try #require(await reopened.session(accountID: account))
    try await reopened.saveSession(
      saved.session, accountID: account, expectedRevision: saved.revision)
    #expect(try await reopened.pendingReviews(accountID: account).isEmpty)
    let report = try await reopened.uploadPending(
      accountID: account, token: "fixture", client: server.client)
    #expect(report.uploadedReviews == 0 && report.uploadedLessons == 0)
    #expect(await server.writes.isEmpty)
    let work = try await reopened.savedWork(accountID: account)
    #expect(work.isEmpty && work.archivedReviews.count == 1 && work.requiresAssignmentRefresh)
  }

  @Test func archivingDoesNotAffectOtherPendingAnswersOrNotes() async throws {
    let store = try await store(otherPending: true)
    let server = ReviewRecoveryServer()
    let other = try #require(
      await store.pendingReviews(accountID: account).first { $0.subjectID == 2 })
    let notes = try await store.materials(accountID: account)
    let compared = try await compare(store, server)
    try await store.archiveReview(compared)
    await #expect(throws: URLError.self) {
      try await store.refresh(
        credentialID: "credential", token: "fixture",
        client: WaniKaniClient { _ in throw URLError(.notConnectedToInternet) })
    }
    #expect(try await store.snapshot(credentialID: "credential")?.requiresAssignmentRefresh == true)
    #expect(try await store.pendingReviews(accountID: account) == [other])
    #expect(try await store.materials(accountID: account).map(\.material) == notes.map(\.material))
    #expect(try await store.assignments(accountID: account).map(\.subjectID) == [2])
    #expect(try await store.snapshot(credentialID: "credential")?.pendingReviews == 1)
  }

  @Test func refreshedProgressMustBeLoadedBeforeReviewingAnArchivedSubject() async throws {
    let store = try await store()
    let server = ReviewRecoveryServer()
    let compared = try await compare(store, server)
    try await store.archiveReview(compared)
    let session = try #require(await store.session(accountID: account))
    try await store.removeSession(accountID: account, expectedRevision: session.revision)
    let fresh = try await store.openReviews(
      accountID: account, now: Date(timeIntervalSince1970: 300))
    #expect(fresh.saved.session.items.values.allSatisfy { $0.subjectID != 1 })
    try await store.endReviews(accountID: account, expectedRevision: fresh.saved.revision)
    _ = try await store.refresh(
      credentialID: "credential", token: "fixture",
      client: WaniKaniClient(transport: DownloadFixture.response))
    #expect(try await store.assignments(accountID: account).contains { $0.subjectID == 1 })
    #expect(try await store.archivedReviews(accountID: account).count == 1)
    #expect(
      try await store.snapshot(credentialID: "credential")?.requiresAssignmentRefresh == false)
    #expect(try await !store.savedWork(accountID: account).requiresAssignmentRefresh)
  }

  @Test func changedAttemptMetadataInvalidatesAnOlderComparison() async throws {
    let store = try await store()
    let server = ReviewRecoveryServer()
    let compared = try await compare(store, server)
    _ = try await store.uploadPending(accountID: account, token: "fixture", client: server.client)
    let latest = try await pending(store)
    #expect(latest.revision == compared.saved.revision && latest.issue != compared.saved.issue)
    await #expect(throws: StudyRecoveryError.self) { try await store.archiveReview(compared) }
    #expect(try await pending(store) == latest)
    #expect(try await store.archivedReviews(accountID: account).isEmpty)
    #expect(try await store.assignments(accountID: account).contains { $0.subjectID == 1 })
  }

  @Test func acknowledgedAnswerCannotBeRecreatedByAnOlderComparison() async throws {
    let store = try await store()
    let server = ReviewRecoveryServer()
    let compared = try await compare(store, server)
    try await store.acknowledgeReview(compared.saved)
    await #expect(throws: StudyRecoveryError.self) { try await store.archiveReview(compared) }
    #expect(try await store.archivedReviews(accountID: account).isEmpty)
  }

  @Test func wrongAccountAndCredentialBindingCannotChangePendingWork() async throws {
    let store = try await store()
    let server = ReviewRecoveryServer()
    let original = try await pending(store)
    await server.configure(identity: "other-account")
    await #expect(throws: StudyUploadError.self) { try await compare(store, server) }
    await #expect(throws: StudyUploadError.self) {
      try await store.compareSavedWork(
        .review(original), credentialID: "other", token: "fixture", client: server.client)
    }
    #expect(try await pending(store) == original)
    #expect(try await store.archivedReviews(accountID: account).isEmpty)
    #expect(await server.writes.isEmpty)
  }

  @Test func rateLimitPreservesTheAnswerAndStopsRepeatedReads() async throws {
    let store = try await store()
    let server = ReviewRecoveryServer()
    let before = try await pending(store)
    await server.configure(limited: true)
    await #expect(throws: WaniKaniClient.APIError.self) { try await compare(store, server) }
    let count = await server.requests.count
    await #expect(throws: WaniKaniClient.APIError.self) { try await compare(store, server) }
    #expect(await server.requests.count == count)
    #expect(try await pending(store) == before)
  }

  @Test func cancellationDrainsTheReadAndInvalidatesEarlierChoices() async throws {
    let store = try await store()
    let server = ReviewRecoveryServer()
    let gate = RecoveryGate()
    let old = try await compare(store, server)
    await server.pause(gate)
    let run = Task { try await compare(store, server) }
    await gate.entered()
    let cancel = Task { await store.cancelSynchronization() }
    await gate.cancellationObserved()
    await #expect(throws: StudyUploadError.self) { try await store.archiveReview(old) }
    await gate.resume()
    await #expect(throws: CancellationError.self) { try await run.value }
    await cancel.value
    await #expect(throws: StudyRecoveryError.self) { try await store.archiveReview(old) }
    #expect(try await store.archivedReviews(accountID: account).isEmpty)
    #expect(try await pending(store).attempted)
  }

  @Test func archiveIsAccountBoundAndEncodesTheFullSavedAnswer() async throws {
    let store = try await store()
    let server = ReviewRecoveryServer()
    try await store.saveSnapshot(
      .init(
        accountID: "other", username: "other", currentLevel: 1,
        assignments: [], statistics: [], levels: [], subjects: []), credentialID: "other")
    let value = try await compare(store, server)
    let archived = try await store.archiveReview(value)
    let encoded = try JSONEncoder().encode(archived)
    let decoded = try JSONDecoder().decode(ArchivedStudyReview.self, from: encoded)
    #expect(decoded.archivedAt == archived.archivedAt && decoded.checkedAt == archived.checkedAt)
    #expect(
      decoded.saved == archived.saved && decoded.observedAssignment == archived.observedAssignment)
    #expect(
      decoded.cachedAssignment == archived.cachedAssignment
        && decoded.cachedProgress?.lastMistakeLocalTime == "2026-10-17T10:00:00")
    #expect(try await store.archivedReviews(accountID: "other").isEmpty)
    try await store.removeSnapshot(credentialID: "credential")
    await #expect(throws: StudyStoreError.self) {
      try await store.archivedReviews(accountID: account)
    }
  }

  @Test func previousSnapshotEncodingDefaultsToCompleteAssignments() throws {
    let old =
      #"{"username":"older cache","currentLevel":1,"onVacation":false,"assignments":[],"statistics":[],"levels":[],"subjects":[],"savedAt":0,"pendingReviews":0,"isSample":false}"#
    let decoded = try JSONDecoder().decode(StudySnapshot.self, from: Data(old.utf8))
    #expect(!decoded.requiresAssignmentRefresh && decoded.accountID == nil)
  }
}
