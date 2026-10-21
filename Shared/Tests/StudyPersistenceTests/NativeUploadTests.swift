import Foundation
import StudyCore
import Testing

@testable import StudyPersistence

private actor UploadGate {
  var entered = false, cancelled = false
  var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  var cancelledWaiters: [CheckedContinuation<Void, Never>] = []
  var release: CheckedContinuation<Void, Never>?
  func pause() async {
    entered = true
    for waiter in enteredWaiters { waiter.resume() }
    enteredWaiters.removeAll()
    await withTaskCancellationHandler {
      await withCheckedContinuation { release = $0 }
    } onCancel: {
      Task { await self.observeCancellation() }
    }
  }
  func waitForEntry() async {
    if !entered { await withCheckedContinuation { enteredWaiters.append($0) } }
  }
  func waitForCancellation() async {
    if !cancelled { await withCheckedContinuation { cancelledWaiters.append($0) } }
  }
  func observeCancellation() {
    cancelled = true
    for waiter in cancelledWaiters { waiter.resume() }
    cancelledWaiters.removeAll()
  }
  func resume() {
    release?.resume()
    release = nil
  }
}

private actor UploadServer {
  var requests: [URLRequest] = []
  var account = "account-a", vacation = false
  var rejectedSubject: Int64?, reviewStatus: Int?
  var timeoutReview = false, timeoutMaterial = false
  var materialStatus: Int?
  var changedSubject: Int64?
  var lessonSubject: Int64?, missingSubject: Int64?, replacedSubject: Int64?
  var gate: UploadGate?
  var gateMethod: String?
  func configure(
    account: String = "account-a", vacation: Bool = false, rejectedSubject: Int64? = nil,
    reviewStatus: Int? = nil, timeoutReview: Bool = false, timeoutMaterial: Bool = false,
    changedSubject: Int64? = nil, lessonSubject: Int64? = nil, missingSubject: Int64? = nil,
    replacedSubject: Int64? = nil, materialStatus: Int? = nil, gate: UploadGate? = nil,
    gateMethod: String? = nil
  ) {
    self.account = account
    self.vacation = vacation
    self.rejectedSubject = rejectedSubject
    self.reviewStatus = reviewStatus
    self.timeoutReview = timeoutReview
    self.timeoutMaterial = timeoutMaterial
    self.changedSubject = changedSubject
    self.gate = gate
    self.gateMethod = gateMethod
    self.lessonSubject = lessonSubject
    self.missingSubject = missingSubject
    self.replacedSubject = replacedSubject
    self.materialStatus = materialStatus
  }
  var client: WaniKaniClient { .init { try await self.send($0) } }
  var writes: [URLRequest] { requests.filter { $0.httpMethod != "GET" } }
  private func assignment(_ subject: Int64, stage: Int = 3, available: Int = 100) -> [String: Any] {
    [
      "id": subject + (replacedSubject == subject ? 200 : 100), "object": "assignment",
      "data": [
        "subject_id": subject, "subject_type": "radical",
        "srs_stage": stage,
        "available_at": "1970-01-01T00:\(available == 100 ? "01:40" : "05:00")Z",
        "started_at": stage == 0 ? NSNull() : "1970-01-01T00:00:10Z" as Any,
        "unlocked_at": "1970-01-01T00:00:01Z", "hidden": false,
      ],
    ]
  }
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    if request.httpMethod == gateMethod, let gate {
      self.gate = nil
      await gate.pause()
    }
    let path = request.url!.path
    var status = 200
    var headers: [String: String] = [:]
    var result: [String: Any] = [:]
    if path == "/v2/user" {
      result = [
        "object": "user",
        "data": [
          "id": account, "username": "fixture", "level": 1,
          "current_vacation_started_at": vacation ? "2026-10-17T00:00:00Z" as Any : NSNull(),
        ],
      ]
    } else if request.httpMethod == "GET" {
      let id = Int64(
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!)!
      result = [
        "pages": ["next_url": NSNull()],
        "data": path == "/v2/assignments" && missingSubject != id
          ? [assignment(id, stage: lessonSubject == id ? 0 : changedSubject == id ? 5 : 3)] : [],
      ]
    } else if path.hasSuffix("/start") {
      let id = Int64(path.split(separator: "/")[2])! - 100
      result = assignment(id, stage: 1, available: 300)
    } else if path == "/v2/reviews" {
      if timeoutReview { throw URLError(.timedOut) }
      let body =
        try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: [String: Any]]
      let review = body["review"]!
      let id = (review["assignment_id"] as! NSNumber).int64Value - 100
      if rejectedSubject == id, let reviewStatus {
        status = reviewStatus
        headers = ["Retry-After": "120"]
      } else {
        result = [
          "id": 0, "object": "review",
          "data": [
            "assignment_id": id + 100, "subject_id": id,
            "incorrect_meaning_answers": review["incorrect_meaning_answers"]!,
            "incorrect_reading_answers": review["incorrect_reading_answers"]!,
            "ending_srs_stage": 4,
          ], "resources_updated": ["assignment": assignment(id, stage: 4, available: 300)],
        ]
      }
    } else {
      if timeoutMaterial { throw URLError(.timedOut) }
      let body =
        try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: [String: Any]]
      var material = body["study_material"]!
      material["subject_id"] = material["subject_id"] ?? 42
      result = ["id": 242, "object": "study_material", "data": material]
      if let materialStatus { status = materialStatus }
    }
    if let rows = result["data"] as? [[String: Any]], result["pages"] != nil {
      result["object"] = "collection"
      result["total_count"] = rows.count
    }
    return (
      try JSONSerialization.data(withJSONObject: result),
      HTTPURLResponse(
        url: request.url!, statusCode: status,
        httpVersion: nil, headerFields: headers)!
    )
  }
}

struct NativeUploadTests {
  private func store(
    at url: URL = URL(filePath: "/unused"), subjects: [Int64] = [42], note: Bool = true,
    lesson: Bool = false
  ) async throws -> StudyStore {
    let store = try await StudyStore.open(at: url, inMemory: url.path == "/unused")
    try await store.saveSnapshot(
      .init(
        accountID: "account-a", username: "fixture", currentLevel: 1,
        assignments: [], statistics: [], levels: [], subjects: []), credentialID: "credential-a")
    if !subjects.isEmpty {
      var session = try StudySession(
        items: subjects.enumerated().map { index, subject in
          .init(
            id: index, subjectID: subject, assignmentID: subject + 100, srsStage: lesson ? 0 : 3,
            availableAt: 100, isLesson: lesson, hasReading: false)
        }, seed: 1)
      while let question = session.nextQuestion() {
        _ = try session.mark(.correct, for: question, now: 200)
      }
      try await store.saveSession(session, accountID: "account-a", expectedRevision: nil)
    }
    if note {
      try await store.saveMaterial(
        .init(subjectID: 42, meaningNote: "first"), accountID: "account-a", expectedRevision: nil)
    }
    return store
  }
  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func verifiedUploadsCommitAssignmentAndExactNoteAcknowledgements() async throws {
    let store = try await store()
    let server = UploadServer()
    let report = try await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    #expect(report.uploadedReviews == 1 && report.uploadedMaterials == 1)
    #expect(try await store.pendingReviews(accountID: "account-a").isEmpty)
    #expect(try await store.assignments(accountID: "account-a").first?.srsStage == 4)
    let material = try #require(await store.materials(accountID: "account-a").first)
    #expect(!material.pending && material.serverID == 242 && material.attemptedRevision == nil)
    #expect(await server.requests.first?.url?.path == "/v2/user")
  }

  @Test func rejectedReviewDoesNotStarveOtherReviewsOrNotes() async throws {
    let store = try await store(subjects: [42, 43])
    let server = UploadServer()
    await server.configure(rejectedSubject: 42, reviewStatus: 422)
    let report = try await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    #expect(
      report.uploadedReviews == 1 && report.uploadedMaterials == 1
        && report.reviewsNeedingAttention == 1)
    let pending = try #require(await store.pendingReviews(accountID: "account-a").first)
    #expect(
      !pending.attempted && pending.issue?.reason == .rejected && pending.issue?.httpStatus == 422)
    #expect(pending.issue?.serverAssignment?.subjectID == 42)
    let writes = await server.writes.count
    _ = try await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    #expect(await server.writes.count == writes)
  }

  @Test func uncertainReviewSurvivesRestartWithoutAnotherWrite() async throws {
    let dir = try directory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "study.store")
    let server = UploadServer()
    await server.configure(timeoutReview: true)
    do {
      let store = try await store(at: url, note: false)
      await #expect(throws: URLError.self) {
        try await store.uploadPending(
          accountID: "account-a", token: "fixture", client: server.client)
      }
    }
    await server.configure()
    let reopened = try await StudyStore.open(at: url)
    let report = try await reopened.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    #expect(report.reviewsNeedingAttention == 1 && report.uploadedReviews == 0)
    #expect(
      try await reopened.pendingReviews(accountID: "account-a").first?.issue?.reason == .uncertain)
    #expect(await server.writes.count == 1)
  }

  @Test func wrongAccountCannotMarkOrSendSavedWork() async throws {
    let store = try await store()
    let server = UploadServer()
    await server.configure(account: "other-account")
    await #expect(throws: StudyUploadError.self) {
      try await store.uploadPending(accountID: "account-a", token: "wrong", client: server.client)
    }
    #expect(await server.writes.isEmpty)
    #expect(try await store.pendingReviews(accountID: "account-a").first?.attempted == false)
  }

  @Test func noteEditedDuringWriteRemainsPendingAfterOldSuccess() async throws {
    let store = try await store(subjects: [])
    let server = UploadServer()
    let gate = UploadGate()
    await server.configure(gate: gate, gateMethod: "POST")
    let client = await server.client
    let run = Task {
      try await store.uploadPending(accountID: "account-a", token: "fixture", client: client)
    }
    await gate.waitForEntry()
    let old = try #require(await store.materials(accountID: "account-a").first)
    #expect(old.attemptedRevision == old.revision && old.attemptedMaterial?.meaningNote == "first")
    try await store.saveMaterial(
      .init(subjectID: 42, meaningNote: "newer"), accountID: "account-a",
      expectedRevision: old.revision)
    await gate.resume()
    _ = try await run.value
    let newer = try #require(await store.materials(accountID: "account-a").first)
    #expect(
      newer.pending && newer.material.meaningNote == "newer" && newer.attemptedRevision == nil)
    _ = try await store.uploadPending(accountID: "account-a", token: "fixture", client: client)
    #expect(try await store.materials(accountID: "account-a").first?.pending == false)
    #expect(await server.writes.count == 2)
  }

  @Test func uncertainNoteRetainsSentRevisionEvenAfterEditingAndRestart() async throws {
    for httpTimeout in [false, true] {
      let dir = try directory()
      defer { try? FileManager.default.removeItem(at: dir) }
      let url = dir.appending(path: "study.store")
      let server = UploadServer()
      await server.configure(timeoutMaterial: !httpTimeout, materialStatus: httpTimeout ? 408 : nil)
      do {
        let store = try await store(at: url, subjects: [])
        await #expect(throws: (any Error).self) {
          try await store.uploadPending(
            accountID: "account-a", token: "fixture", client: server.client)
        }
        let old = try #require(await store.materials(accountID: "account-a").first)
        try await store.saveMaterial(
          .init(subjectID: 42, meaningNote: "newer"), accountID: "account-a",
          expectedRevision: old.revision)
      }
      await server.configure()
      let reopened = try await StudyStore.open(at: url)
      let report = try await reopened.uploadPending(
        accountID: "account-a", token: "fixture", client: server.client)
      let saved = try #require(await reopened.materials(accountID: "account-a").first)
      #expect(saved.attemptedRevision != nil && saved.attemptedMaterial?.meaningNote == "first")
      #expect(
        saved.pending && saved.material.meaningNote == "newer"
          && report.materialsNeedingAttention == 1)
      #expect(await server.writes.count == 1)
    }
  }

  @Test func cancellationFencesLateResponsesAndOverlappingUploadPasses() async throws {
    let store = try await store(note: false)
    let server = UploadServer()
    let gate = UploadGate()
    await server.configure(gate: gate, gateMethod: "POST")
    let client = await server.client
    let run = Task {
      try await store.uploadPending(accountID: "account-a", token: "fixture", client: client)
    }
    await gate.waitForEntry()
    await #expect(throws: StudyUploadError.self) {
      try await store.uploadPending(accountID: "account-a", token: "fixture", client: client)
    }
    let cancel = Task { await store.cancelSynchronization() }
    await gate.waitForCancellation()
    try await store.removeSnapshot(credentialID: "credential-a")
    try await store.saveSnapshot(
      .init(
        accountID: "account-b", username: "other", currentLevel: 5,
        assignments: [], statistics: [], levels: [], subjects: []), credentialID: "credential-b")
    await gate.resume()
    await #expect(throws: CancellationError.self) { try await run.value }
    await cancel.value
    #expect(try await store.pendingReviews(accountID: "account-a").first?.attempted == true)
    #expect(try await store.assignments(accountID: "account-a").isEmpty)
    #expect(try await store.snapshot(credentialID: "credential-b")?.currentLevel == 5)
  }

  @Test func rateLimitDeadlineSurvivesRestartAndPreventsEarlyRequests() async throws {
    let dir = try directory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "study.store")
    let server = UploadServer()
    await server.configure(rejectedSubject: 42, reviewStatus: 429)
    do {
      let store = try await store(at: url, note: false)
      await #expect(throws: WaniKaniClient.APIError.self) {
        try await store.uploadPending(
          accountID: "account-a", token: "fixture", client: server.client)
      }
      #expect(try await store.pendingReviews(accountID: "account-a").first?.attempted == false)
    }
    let count = await server.requests.count
    let reopened = try await StudyStore.open(at: url)
    #expect(try await reopened.uploadRetryDate(accountID: "account-a")! > Date())
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await reopened.uploadPending(
        accountID: "account-a", token: "fixture", client: server.client)
    }
    #expect(await server.requests.count == count)
  }

  @Test func vacationDefersReviewsWhileSavingNotes() async throws {
    let store = try await store()
    let server = UploadServer()
    await server.configure(vacation: true)
    let report = try await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    #expect(report.onVacation && report.uploadedReviews == 0 && report.uploadedMaterials == 1)
    #expect(try await store.pendingReviews(accountID: "account-a").first?.attempted == false)
  }

  @Test func changedServerAssignmentNeedsAttentionWithoutPostingReview() async throws {
    for scenario in 0...2 {
      let store = try await store(note: false)
      let server = UploadServer()
      await server.configure(
        changedSubject: scenario == 0 ? 42 : nil, missingSubject: scenario == 1 ? 42 : nil,
        replacedSubject: scenario == 2 ? 42 : nil)
      let report = try await store.uploadPending(
        accountID: "account-a", token: "fixture", client: server.client)
      #expect(report.reviewsNeedingAttention == 1 && report.uploadedReviews == 0)
      #expect(
        try await store.pendingReviews(accountID: "account-a").first?.issue?.reason
          == (scenario == 1 ? .assignmentMissing : .assignmentChanged))
      #expect(await server.writes.isEmpty)
    }
  }

  @Test func rejectedRecoveryChoicePersistsAndRechecksServerBeforeRetry() async throws {
    let dir = try directory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "study.store")
    let server = UploadServer()
    await server.configure(rejectedSubject: 42, reviewStatus: 422, materialStatus: 422)
    do {
      let store = try await store(at: url)
      _ = try await store.uploadPending(
        accountID: "account-a", token: "fixture", client: server.client)
      let work = try await store.savedWork(accountID: "account-a")
      let review = try #require(work.reviews.first)
      let material = try #require(work.materials.first)
      let requestCount = await server.requests.count
      try await store.queueRejectedReview(review)
      try await store.queueRejectedMaterial(material)
      // Queuing is local, not consent to upload.
      #expect(await server.requests.count == requestCount)
      await #expect(throws: StudyRecoveryError.self) { try await store.queueRejectedReview(review) }
      await #expect(throws: StudyRecoveryError.self) {
        try await store.queueRejectedMaterial(material)
      }
    }
    let store = try await StudyStore.open(at: url)
    let work = try await store.savedWork(accountID: "account-a")
    #expect(work.reviews.first?.issue == nil && work.materials.first?.issue == nil)
    #expect(work.reviews.first?.submission.assignmentID == 142)
    #expect(work.materials.first?.material.meaningNote == "first")
    await server.configure(changedSubject: 42)
    let report = try await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    #expect(report.uploadedReviews == 0 && report.uploadedMaterials == 1)
    #expect(
      try await store.savedWork(accountID: "account-a").reviews.first?.issue?.reason
        == .assignmentChanged)
  }

  @Test func rejectedReviewCanBeRetriedWithoutChangingItsOriginalAnswers() async throws {
    let store = try await store(note: false)
    let server = UploadServer()
    await server.configure(rejectedSubject: 42, reviewStatus: 422)
    _ = try await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    let saved = try #require(await store.savedWork(accountID: "account-a").reviews.first)
    try await store.queueRejectedReview(saved)
    #expect(
      try await store.savedWork(accountID: "account-a").reviews.first?.submission
        == saved.submission)
    await server.configure()
    let report = try await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    #expect(report.uploadedReviews == 1)
    #expect(try await store.savedWork(accountID: "account-a").isEmpty)
    let writes = await server.writes
    #expect(writes.count == 2)
    let first =
      try JSONSerialization.jsonObject(with: #require(writes.first?.httpBody)) as? NSDictionary
    let second =
      try JSONSerialization.jsonObject(with: #require(writes.last?.httpBody)) as? NSDictionary
    #expect(first == second)
  }

  @Test func recoveryNeverClearsUncertainOrChangedWork() async throws {
    for scenario in 0...3 {
      let store = try await store(note: false)
      let server = UploadServer()
      await server.configure(
        timeoutReview: scenario == 0, changedSubject: scenario == 1 ? 42 : nil,
        missingSubject: scenario == 2 ? 42 : nil, replacedSubject: scenario == 3 ? 42 : nil)
      _ = try? await store.uploadPending(
        accountID: "account-a", token: "fixture", client: server.client)
      let saved = try #require(await store.savedWork(accountID: "account-a").reviews.first)
      await #expect(throws: StudyRecoveryError.self) { try await store.queueRejectedReview(saved) }
      let retained = try #require(await store.savedWork(accountID: "account-a").reviews.first)
      #expect(retained.revision == saved.revision && retained.attempted == saved.attempted)
      #expect(retained.issue?.reason == saved.issue?.reason)
    }
    let store = try await store(subjects: [])
    let server = UploadServer()
    await server.configure(timeoutMaterial: true)
    _ = try? await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    let saved = try #require(await store.savedWork(accountID: "account-a").materials.first)
    await #expect(throws: StudyRecoveryError.self) { try await store.queueRejectedMaterial(saved) }
    #expect(
      try await store.savedWork(accountID: "account-a").materials.first?.attemptedRevision
        == saved.attemptedRevision)
  }

  @Test func recoveryRejectsStaleNoteEditsAndDisconnectedAccounts() async throws {
    let store = try await store()
    let server = UploadServer()
    await server.configure(rejectedSubject: 42, reviewStatus: 422, materialStatus: 422)
    _ = try await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    let work = try await store.savedWork(accountID: "account-a")
    let saved = try #require(work.materials.first)
    let review = try #require(work.reviews.first)
    try await store.saveMaterial(
      .init(subjectID: 42, meaningNote: "newer"), accountID: "account-a",
      expectedRevision: saved.revision)
    await #expect(throws: StudyRecoveryError.self) { try await store.queueRejectedMaterial(saved) }
    #expect(
      try await store.savedWork(accountID: "account-a").materials.first?.material.meaningNote
        == "newer")
    try await store.removeSnapshot(credentialID: "credential-a")
    await #expect(throws: StudyStoreError.self) { try await store.queueRejectedReview(review) }
    await #expect(throws: StudyStoreError.self) {
      try await store.savedWork(accountID: "account-a")
    }
    #expect(try await store.pendingReviews(accountID: "account-a").count == 1)
  }

  @Test func recoveryCannotChangeItemsDuringAnUploadPass() async throws {
    let store = try await store()
    let server = UploadServer()
    let gate = UploadGate()
    await server.configure(rejectedSubject: 42, reviewStatus: 422, materialStatus: 422)
    _ = try await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    let work = try await store.savedWork(accountID: "account-a")
    let review = try #require(work.reviews.first)
    let material = try #require(work.materials.first)
    await server.configure(gate: gate, gateMethod: "GET")
    let client = await server.client
    let run = Task {
      try await store.uploadPending(accountID: "account-a", token: "fixture", client: client)
    }
    await gate.waitForEntry()
    await #expect(throws: StudyUploadError.self) { try await store.queueRejectedReview(review) }
    await #expect(throws: StudyUploadError.self) { try await store.queueRejectedMaterial(material) }
    await gate.resume()
    _ = try await run.value
    #expect(
      try await store.savedWork(accountID: "account-a").materials.first?.issue?.reason == .rejected)
  }

  @Test func lessonUsesStartEndpointAndCommitsUpdatedAssignment() async throws {
    let store = try await store(note: false, lesson: true)
    let server = UploadServer()
    await server.configure(lessonSubject: 42)
    let report = try await store.uploadPending(
      accountID: "account-a", token: "fixture", client: server.client)
    #expect(report.uploadedLessons == 1 && report.uploadedReviews == 0)
    #expect(await server.writes.first?.url?.path == "/v2/assignments/142/start")
    #expect(try await store.pendingReviews(accountID: "account-a").isEmpty)
    #expect(try await store.assignments(accountID: "account-a").first?.srsStage == 1)
  }
}
