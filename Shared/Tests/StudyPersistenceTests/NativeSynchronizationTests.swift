import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

private actor SynchronizationServer {
  let gate: StudyTaskGate?
  let identityGate: StudyTaskGate?
  private(set) var identityReads = 0
  let failAfterWrite: Bool
  let pauseWrites: Bool
  let failRead: Bool
  private(set) var subjectReads = 0
  private(set) var writes = 0
  private(set) var writeBodies: [Data] = []
  private var material: [String: Any] = DownloadFixture.rows["study_materials"]!.first!
  init(
    gate: StudyTaskGate? = nil, failAfterWrite: Bool = false, pauseWrites: Bool = false,
    failRead: Bool = false, identityGate: StudyTaskGate? = nil
  ) {
    self.gate = gate
    self.identityGate = identityGate
    self.failAfterWrite = failAfterWrite
    self.pauseWrites = pauseWrites
    self.failRead = failRead
  }
  var client: WaniKaniClient { .init { try await self.respond($0) } }
  func respond(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let path = request.url!.lastPathComponent
    if path == "user" {
      identityReads += 1
      if identityReads == 1, let identityGate { await identityGate.pause() }
    }
    if path == "subjects" {
      subjectReads += 1
      if subjectReads == 1, !pauseWrites, let gate { await gate.pause() }
      if failRead || (failAfterWrite && writes > 0) { throw URLError(.notConnectedToInternet) }
    }
    if request.httpMethod != "GET" {
      writes += 1
      writeBodies.append(try #require(request.httpBody))
      if writes == 1, pauseWrites, let gate { await gate.pause() }
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      var value = body["study_material"] as! [String: Any]
      value["subject_id"] = 1
      material = DownloadFixture.resource(201, "study_material", value)
      return try DownloadFixture.response(request, object: material)
    }
    if path == "study_materials" {
      return try DownloadFixture.response(request, object: DownloadFixture.collection([material]))
    }
    return try DownloadFixture.response(request)
  }
}

struct NativeSynchronizationTests {
  private func store(pendingNote: Bool = false) async throws -> StudyStore {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    _ = try await store.applyDownload(
      download, credentialID: "credential",
      baseline: store.refreshBaseline(accountID: download.accountID))
    if pendingNote {
      let material = try #require(await store.materials(accountID: download.accountID).first)
      _ = try await store.saveMaterial(
        .init(subjectID: 1, meaningNote: "new note"), accountID: download.accountID,
        expectedRevision: material.revision)
    }
    return store
  }

  @Test func emptyReauthenticationIdentityIsRejectedBeforeAnyNetworkRead() async throws {
    let store = try await store(pendingNote: true)
    let before = try await store.generationSnapshot()
    let server = SynchronizationServer()
    await #expect(throws: StudyStoreError.self) {
      try await store.synchronize(
        .reauthenticate(accountID: ""), credentialID: "replacement", token: "fixture",
        client: await server.client)
    }
    #expect(await server.identityReads == 0)
    #expect(await server.subjectReads == 0)
    #expect(await server.writes == 0)
    #expect(try await store.generationSnapshot() == before)
  }
  @Test(arguments: [false, true])
  func directRefreshAndConstrainedReauthenticationCannotShareAnUnscopedRead(_ directFirst: Bool)
    async throws
  {
    let store = try await store(pendingNote: true)
    let note = try #require(await store.materials(accountID: "fixture-user-id").first)
    let gate = StudyTaskGate()
    let server = SynchronizationServer(gate: gate)
    let client = await server.client
    let active = Task {
      if directFirst {
        return try await store.refresh(
          credentialID: "replacement", token: "fixture", client: client)
      }
      return try await store.synchronize(
        .reauthenticate(accountID: "fixture-user-id"), credentialID: "replacement",
        token: "fixture", client: client
      ).snapshot
    }
    await gate.waitForEntry()
    let reads = await server.identityReads
    if directFirst {
      await #expect(throws: StudyUploadError.self) {
        try await store.synchronize(
          .reauthenticate(accountID: "wrong-account"), credentialID: "replacement",
          token: "fixture", client: client)
      }
    } else {
      await #expect(throws: StudyUploadError.self) {
        try await store.refresh(credentialID: "replacement", token: "fixture", client: client)
      }
    }
    #expect(await server.identityReads == reads)
    #expect(await server.subjectReads == 1)
    #expect(await server.writes == 0)
    #expect(try await store.snapshot(credentialID: "replacement") == nil)
    await gate.resume()
    #expect(try await active.value.accountID == "fixture-user-id")
    let retained = try #require(await store.materials(accountID: "fixture-user-id").first)
    #expect(
      retained.material == note.material && retained.revision == note.revision && retained.pending)
  }
  @Test func unlikeReauthenticationIdentitiesDoNotShareAFailedOrUnverifiedResult() async throws {
    let store = try await store(pendingNote: true)
    let gate = StudyTaskGate()
    let server = SynchronizationServer(identityGate: gate)
    let client = await server.client
    let rejected = try await store.synchronizationTask(
      .reauthenticate(accountID: "wrong-account"), credentialID: "replacement", token: "fixture",
      client: client)
    await gate.waitForEntry()
    let first = await store.synchronizationRun?.id
    let verified = try await store.synchronizationTask(
      .reauthenticate(accountID: "fixture-user-id"), credentialID: "replacement", token: "fixture",
      client: client)
    #expect(await store.synchronizationRun?.id != first)
    #expect(await server.identityReads == 1)
    #expect(await server.subjectReads == 0)
    await gate.resume()
    await #expect(throws: StudySignInError.accountMismatch) { try await rejected.value }
    let result = try await verified.value
    #expect(result.snapshot.accountID == "fixture-user-id" && result.upload == nil)
    #expect(await server.identityReads == 3)
    #expect(await server.subjectReads == 1)
    #expect(await server.writes == 0)
    #expect(try await store.savedWork(accountID: "fixture-user-id").materials.count == 1)
  }
  @Test func overlappingRefreshesShareOneReadWithoutSendingPendingWork() async throws {
    let store = try await store(pendingNote: true)
    let gate = StudyTaskGate()
    let server = SynchronizationServer(gate: gate)
    let client = await server.client
    let first = try await store.synchronizationTask(
      .refresh, credentialID: "credential", token: "fixture", client: client)
    await gate.waitForEntry()
    let id = await store.synchronizationRun?.id
    let second = try await store.synchronizationTask(
      .refresh, credentialID: "credential", token: "fixture", client: client)
    #expect(await store.synchronizationRun?.id == id)
    await gate.resume()
    let a = try await first.value
    let b = try await second.value
    #expect(a.snapshot.savedAt == b.snapshot.savedAt && a.upload == nil && b.upload == nil)
    #expect(await server.subjectReads == 1)
    #expect(await server.writes == 0)
    #expect(try await store.savedWork(accountID: "fixture-user-id").materials.count == 1)
  }

  @Test func explicitSendQueuesBehindAReadAndCoalescesOtherRequests() async throws {
    let store = try await store(pendingNote: true)
    let gate = StudyTaskGate()
    let server = SynchronizationServer(gate: gate)
    let client = await server.client
    let read = try await store.synchronizationTask(
      .refresh, credentialID: "credential", token: "fixture", client: client)
    await gate.waitForEntry()
    let send = try await store.synchronizationTask(
      .sendSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
      client: client)
    let id = await store.synchronizationRun?.id
    let duplicate = try await store.synchronizationTask(
      .sendSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
      client: client)
    let joinedRead = try await store.synchronizationTask(
      .refresh, credentialID: "credential", token: "fixture", client: client)
    #expect(await store.synchronizationRun?.id == id)
    #expect(await server.writes == 0)
    await gate.resume()
    #expect(try await read.value.upload == nil)
    for task in [send, duplicate, joinedRead] {
      let result = try await task.value
      #expect(result.upload?.uploadedMaterials == 1 && result.profile?.username == "test")
    }
    #expect(await server.subjectReads == 2)
    #expect(await server.writes == 1)
    #expect(try await store.savedWork(accountID: "fixture-user-id").isEmpty)
  }

  @Test func cancellingAWaitingSceneDoesNotCancelTheOwnedPass() async throws {
    let store = try await store()
    let gate = StudyTaskGate()
    let server = SynchronizationServer(gate: gate)
    let client = await server.client
    let scene = Task {
      try await store.synchronize(credentialID: "credential", token: "fixture", client: client)
    }
    await gate.waitForEntry()
    scene.cancel()
    let joined = try await store.synchronizationTask(
      .refresh, credentialID: "credential", token: "fixture", client: client)
    await gate.resume()
    #expect(try await joined.value.snapshot.accountID == "fixture-user-id")
    await #expect(throws: CancellationError.self) { try await scene.value }
    #expect(await server.subjectReads == 1)
  }

  @Test func accountTransitionDrainsReadAndQueuedSendBeforeAllowingNewWork() async throws {
    let store = try await store(pendingNote: true)
    let gate = StudyTaskGate()
    let server = SynchronizationServer(gate: gate)
    let client = await server.client
    let before = try #require(await store.snapshot(credentialID: "credential"))
    let read = try await store.synchronizationTask(
      .refresh, credentialID: "credential", token: "fixture", client: client)
    await gate.waitForEntry()
    let send = try await store.synchronizationTask(
      .sendSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
      client: client)
    let cancel = Task { await store.cancelSynchronization() }
    await gate.waitForCancellation()
    await #expect(throws: StudyUploadError.self) {
      try await store.synchronize(credentialID: "credential", token: "fixture", client: client)
    }
    await #expect(throws: StudyUploadError.self) {
      try await store.uploadPending(accountID: "fixture-user-id", token: "fixture", client: client)
    }
    await gate.resume()
    await cancel.value
    await #expect(throws: CancellationError.self) { try await read.value }
    await #expect(throws: CancellationError.self) { try await send.value }
    #expect(await server.writes == 0)
    #expect(try await store.snapshot(credentialID: "credential")?.savedAt == before.savedAt)
    #expect(try await store.savedWork(accountID: "fixture-user-id").materials.count == 1)
    let fresh = try await store.synchronize(
      credentialID: "credential", token: "fixture", client: client)
    #expect(fresh.snapshot.accountID == "fixture-user-id")
  }

  @Test func differentCredentialsAndWrongSendAccountCannotJoin() async throws {
    let store = try await store()
    let gate = StudyTaskGate()
    let server = SynchronizationServer(gate: gate)
    let client = await server.client
    let run = try await store.synchronizationTask(
      .refresh, credentialID: "credential", token: "fixture", client: client)
    await gate.waitForEntry()
    await #expect(throws: StudyUploadError.self) {
      try await store.synchronize(credentialID: "another", token: "fixture", client: client)
    }
    await #expect(throws: StudyUploadError.self) {
      try await store.synchronize(
        credentialID: "credential", token: "different-token", client: client)
    }
    await #expect(throws: StudyUploadError.self) {
      try await store.synchronize(
        .sendSavedWork(accountID: "another"), credentialID: "credential", token: "fixture",
        client: client)
    }
    await gate.resume()
    _ = try await run.value
    #expect(await server.subjectReads == 1)
    #expect(await server.writes == 0)
  }

  @Test func cancellingDuringAWritePreservesItsUncertainAttempt() async throws {
    let store = try await store(pendingNote: true)
    let gate = StudyTaskGate()
    let server = SynchronizationServer(gate: gate, pauseWrites: true)
    let client = await server.client
    let send = Task {
      try await store.synchronize(
        .sendSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
        client: client)
    }
    await gate.waitForEntry()
    let cancel = Task { await store.cancelSynchronization() }
    await gate.waitForCancellation()
    await gate.resume()
    await cancel.value
    await #expect(throws: CancellationError.self) { try await send.value }
    let pending = try #require(await store.savedWork(accountID: "fixture-user-id").materials.first)
    #expect(
      pending.attemptedRevision != nil && pending.attemptedMaterial?.meaningNote == "new note")
    let result = try await store.synchronize(
      .sendSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
      client: client)
    #expect(result.upload?.materialsNeedingAttention == 1 && result.upload?.uploadedMaterials == 0)
    #expect(await server.writes == 1)
  }

  @Test func failedPrerequisiteReadNeverStartsAQueuedWrite() async throws {
    let store = try await store(pendingNote: true)
    let gate = StudyTaskGate()
    let server = SynchronizationServer(gate: gate, failRead: true)
    let client = await server.client
    let read = try await store.synchronizationTask(
      .refresh, credentialID: "credential", token: "fixture", client: client)
    await gate.waitForEntry()
    let send = try await store.synchronizationTask(
      .sendSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
      client: client)
    await gate.resume()
    await #expect(throws: URLError.self) { try await read.value }
    await #expect(throws: URLError.self) { try await send.value }
    #expect(await server.writes == 0)
    let pending = try #require(await store.savedWork(accountID: "fixture-user-id").materials.first)
    #expect(pending.attemptedRevision == nil && pending.pending)
    _ = try await store.synchronize(
      credentialID: "credential", token: "fixture",
      client: WaniKaniClient(transport: DownloadFixture.response))
  }

  @Test func successfulUploadIsReportedAndRetainedWhenRefreshFails() async throws {
    let store = try await store(pendingNote: true)
    let server = SynchronizationServer(failAfterWrite: true)
    let client = await server.client
    do {
      _ = try await store.synchronize(
        .sendSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
        client: client)
      Issue.record("Expected the download to fail after a successful write.")
    } catch let error as StudySynchronizationFailure {
      #expect(error.upload.uploadedMaterials == 1)
      #expect((error.cause as? URLError)?.code == .notConnectedToInternet)
    }
    #expect(try await store.savedWork(accountID: "fixture-user-id").isEmpty)
    #expect(
      try await store.materials(accountID: "fixture-user-id").first?.material.meaningNote
        == "new note")
    _ = try await store.synchronize(
      .sendSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
      client: WaniKaniClient(transport: DownloadFixture.response))
    #expect(await server.writes == 1)
  }
  @Test func uploadOnlyAcknowledgesNotesWithoutDownloadingTheCatalog() async throws {
    let store = try await store(pendingNote: true)
    let server = SynchronizationServer(failRead: true)
    let result = try await store.synchronize(
      .uploadSavedWork(accountID: "fixture-user-id"), credentialID: "credential",
      token: "fixture", client: server.client)
    #expect(result.upload?.uploadedMaterials == 1)
    #expect(result.snapshot.pendingReviews == 0)
    #expect(await server.subjectReads == 0)
    #expect(await server.writes == 1)
    #expect(try await store.savedWork(accountID: "fixture-user-id").isEmpty)
  }

  @Test func snapshotsReadAcknowledgedAssignmentsRatherThanTheOldDownload() async throws {
    let store = try await store()
    let accountID = "fixture-user-id"
    let assignment = try #require(await store.assignments(accountID: accountID).first)
    let availableAt = try #require(assignment.availableAt)
    var session = try StudySession(
      items: [
        .init(
          id: 0, subjectID: 1, assignmentID: assignment.id, srsStage: assignment.srsStage,
          availableAt: availableAt, hasReading: false)
      ], seed: 1)
    while let question = session.nextQuestion() {
      _ = try session.mark(.correct, for: question, now: Int64(Date().timeIntervalSince1970))
    }
    try await store.saveSession(session, accountID: accountID, expectedRevision: nil)
    #expect(try await store.pendingReviews(accountID: accountID).count == 1)
    #expect(try await store.snapshot(credentialID: "credential")?.assignments.isEmpty == true)
    let client = WaniKaniClient { request in
      guard request.url?.lastPathComponent == "reviews" else {
        return try DownloadFixture.response(request)
      }
      var assignment = DownloadFixture.assignment
      var data = assignment["data"] as! [String: Any]
      data["srs_stage"] = 6
      data["available_at"] = "2033-05-18T03:33:20Z"
      assignment["data"] = data
      return try DownloadFixture.response(
        request,
        object: [
          "object": "review", "id": 501,
          "data": [
            "subject_id": 1, "assignment_id": 101, "incorrect_meaning_answers": 0,
            "incorrect_reading_answers": 0, "ending_srs_stage": 6,
          ],
          "resources_updated": ["assignment": assignment],
        ])
    }
    _ = try await store.uploadPending(accountID: accountID, token: "fixture", client: client)
    let saved = try #require(await store.snapshot(credentialID: "credential"))
    #expect(saved.pendingReviews == 0)
    #expect(saved.assignments.first?.srsStageNumber == 6)
    #expect(saved.assignments.first?.availableAt == 2_000_000_000)
  }

  @Test func aRefreshQueuedBehindUploadOnlyStillDownloadsTheCatalog() async throws {
    let store = try await store(pendingNote: true)
    let gate = StudyTaskGate()
    let server = SynchronizationServer(gate: gate, pauseWrites: true)
    let client = await server.client
    let send = try await store.synchronizationTask(
      .uploadSavedWork(accountID: "fixture-user-id"), credentialID: "credential",
      token: "fixture", client: client)
    await gate.waitForEntry()
    let read = try await store.synchronizationTask(
      .refresh, credentialID: "credential", token: "fixture", client: client)
    #expect(await server.subjectReads == 0)
    await gate.resume()
    #expect(try await send.value.upload?.uploadedMaterials == 1)
    #expect(try await read.value.upload == nil)
    #expect(await server.subjectReads == 1)
    #expect(await server.writes == 1)
  }

}

extension NativeSynchronizationTests {
  @Test func queuedSendReloadsAnInFlightEditAndCoalescesDuplicateRequests() async throws {
    let store = try await store(pendingNote: true)
    let gate = StudyTaskGate()
    let server = SynchronizationServer(gate: gate, pauseWrites: true)
    let client = await server.client
    let first = try await store.synchronizationTask(
      .uploadSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
      client: client)
    await gate.waitForEntry()
    let attempted = try #require(await store.materials(accountID: "fixture-user-id").first)
    let old = attempted.material
    let edited = StudyMaterial(
      subjectID: 1, meaningNote: "  In-flight edit 🐰\nSecond line",
      readingNote: "\nいち  ", meaningSynonyms: ["One, alone", "First\nonly", "一"])
    try await store.saveSubjectMaterial(
      edited, accountID: "fixture-user-id", expectedRevision: attempted.revision)
    let queued = try await store.synchronizationTask(
      .sendSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
      client: client)
    let run = await store.synchronizationRun?.id
    let duplicate = try await store.synchronizationTask(
      .sendSavedWork(accountID: "fixture-user-id"), credentialID: "credential", token: "fixture",
      client: client)
    #expect(await store.synchronizationRun?.id == run)
    #expect(await server.writes == 1)
    let during = try #require(await store.materials(accountID: "fixture-user-id").first)
    #expect(during.pending && during.material == edited && during.attemptedMaterial == old)
    await gate.resume()
    _ = try await first.value
    for task in [queued, duplicate] {
      #expect(try await task.value.upload?.uploadedMaterials == 1)
    }
    let saved = try #require(await store.materials(accountID: "fixture-user-id").first)
    #expect(saved.material == edited && !saved.pending && saved.attemptedRevision == nil)
    #expect(saved.serverID == attempted.serverID)
    let bodies = await server.writeBodies
    #expect(bodies.count == 2)
    #expect(await server.writes == 2)
    for (body, expected) in zip(bodies, [old, edited]) {
      let actual = try JSONSerialization.jsonObject(with: body) as? NSDictionary
      let expectedMaterial: [String: Any] = [
        "meaning_note": expected.meaningNote, "reading_note": expected.readingNote,
        "meaning_synonyms": expected.meaningSynonyms,
      ]
      let expectedBody = NSDictionary(dictionary: ["study_material": expectedMaterial])
      #expect(actual == expectedBody)
    }
    _ = try await store.synchronize(
      .uploadSavedWork(accountID: "fixture-user-id"),
      credentialID: "credential", token: "fixture", client: client)
    #expect(await server.writes == 2)
  }
}
