import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

private actor MaterialReadGate {
  private var started = false, cancelled = false
  private var entry: CheckedContinuation<Void, Never>?
  private var cancellation: CheckedContinuation<Void, Never>?
  private var release: CheckedContinuation<Void, Never>?
  func pause() async {
    started = true
    entry?.resume()
    entry = nil
    await withTaskCancellationHandler {
      await withCheckedContinuation { release = $0 }
    } onCancel: {
      Task { await self.sawCancellation() }
    }
  }
  private func sawCancellation() {
    cancelled = true
    cancellation?.resume()
    cancellation = nil
  }
  func entered() async { if !started { await withCheckedContinuation { entry = $0 } } }
  func cancellationObserved() async {
    if !cancelled { await withCheckedContinuation { cancellation = $0 } }
  }
  func resume() {
    release?.resume()
    release = nil
  }
}

private actor MaterialRecoveryServer {
  var remote: StudyMaterial? = .init(
    subjectID: 1, meaningNote: "Remote note", meaningSynonyms: ["Server"])
  var remoteID: Int64 = 201
  var identity = "account"
  var timeoutWrite = false, limitRead = false
  var gate: MaterialReadGate?
  var gateWrites = false
  private(set) var requests: [URLRequest] = []
  var writes: [URLRequest] { requests.filter { $0.httpMethod != "GET" } }
  var client: WaniKaniClient { .init { try await self.respond($0) } }
  func configure(remote: StudyMaterial?, id: Int64 = 201) {
    self.remote = remote
    remoteID = id
  }
  func fault(identity: String = "account", timeoutWrite: Bool = false, limitRead: Bool = false) {
    self.identity = identity
    self.timeoutWrite = timeoutWrite
    self.limitRead = limitRead
  }
  func pause(_ gate: MaterialReadGate, writes: Bool = false) {
    self.gate = gate
    gateWrites = writes
  }
  func respond(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
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
    let reading = request.httpMethod == "GET"
    if let gate, reading != gateWrites {
      self.gate = nil
      await gate.pause()
    }
    if reading, limitRead {
      return (
        Data("{}".utf8),
        HTTPURLResponse(
          url: request.url!, statusCode: 429, httpVersion: nil,
          headerFields: ["Retry-After": "120"])!
      )
    }
    if !reading {
      let body =
        try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: [String: Any]]
      let value = body["study_material"]!
      remote = .init(
        subjectID: 1, meaningNote: value["meaning_note"] as! String,
        readingNote: value["reading_note"] as! String,
        meaningSynonyms: value["meaning_synonyms"] as! [String])
      if timeoutWrite { throw URLError(.timedOut) }
    }
    let resource = remote.map { value in
      DownloadFixture.resource(
        Int(remoteID), "study_material",
        [
          "subject_id": value.subjectID, "meaning_note": value.meaningNote,
          "reading_note": value.readingNote, "meaning_synonyms": value.meaningSynonyms,
        ])
    }
    return try DownloadFixture.response(
      request,
      object: reading
        ? DownloadFixture.collection(resource.map { [$0] } ?? []) : resource!)
  }
}

struct MaterialRecoveryTests {
  private let local = StudyMaterial(
    subjectID: 1, meaningNote: "  Local 🐰\nsecond line  ",
    readingNote: "いち", meaningSynonyms: ["One, alone", "一"])
  private func store(at url: URL = URL(filePath: "/unused")) async throws -> StudyStore {
    let store = try await StudyStore.open(at: url, inMemory: url.path == "/unused")
    try await store.saveSnapshot(
      .init(
        accountID: "account", username: "fixture", currentLevel: 1,
        assignments: [], statistics: [], levels: [], subjects: []), credentialID: "credential")
    try await store.saveMaterial(local, accountID: "account", expectedRevision: nil)
    return store
  }
  private func pending(_ store: StudyStore) async throws -> SavedStudyMaterial {
    try #require(await store.materials(accountID: "account").first)
  }
  private func comparison(_ store: StudyStore, _ server: MaterialRecoveryServer) async throws
    -> StudyMaterialComparison
  {
    try await store.compareMaterial(
      pending(store), credentialID: "credential", token: "fixture", client: server.client)
  }

  @Test func unknownEarlierWriteCanBeComparedAndExplicitlyAdoptedWithoutAnotherWrite() async throws
  {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let server = MaterialRecoveryServer()
    do {
      let store = try await store(at: url)
      await server.fault(timeoutWrite: true)
      await #expect(throws: URLError.self) {
        try await store.uploadPending(accountID: "account", token: "fixture", client: server.client)
      }
      let attempted = try await pending(store)
      let newer = StudyMaterial(subjectID: 1, meaningNote: "Newer unsent edit")
      try await store.saveMaterial(
        newer, accountID: "account", expectedRevision: attempted.revision)
      await server.fault()
      let compared = try await comparison(store, server)
      #expect(compared.saved.material == newer && compared.saved.attemptedMaterial == local)
      #expect(compared.remote?.value == local && compared.saved.attemptedRevision != nil)
      #expect(await server.writes.count == 1)
      try await store.resolveMaterial(compared, choice: .useServer)
    }
    let reopened = try await StudyStore.open(at: url)
    let saved = try await pending(reopened)
    #expect(!saved.pending && saved.material == local && saved.serverID == 201)
    #expect(saved.issue == nil && saved.attemptedMaterial == nil && saved.attemptedRevision == nil)
    _ = try await reopened.uploadPending(
      accountID: "account", token: "fixture", client: server.client)
    #expect(await server.writes.count == 1)
  }

  @Test(arguments: [false, true])
  func keptEditStaysLocalUntilExplicitSyncAndSurvivesRestart(missing: Bool) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let server = MaterialRecoveryServer()
    if missing { await server.configure(remote: nil) }
    do {
      let store = try await store(at: url)
      let compared = try await comparison(store, server)
      #expect((compared.remote == nil) == missing)
      try await store.resolveMaterial(compared, choice: .keepLocal)
      #expect(await server.writes.isEmpty)
      #expect(try await pending(store).pending)
    }
    let reopened = try await StudyStore.open(at: url)
    let report = try await reopened.uploadPending(
      accountID: "account", token: "fixture", client: server.client)
    #expect(report.uploadedMaterials == 1)
    #expect(try await pending(reopened).material == local)
    #expect(try await pending(reopened).pending == false)
    #expect(await server.writes.first?.httpMethod == (missing ? "POST" : "PUT"))
  }

  @Test(arguments: ["content", "identity", "creation", "deletion"])
  func changedServerStateRequiresAnotherDecision(change: String) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let server = MaterialRecoveryServer()
    if change == "creation" { await server.configure(remote: nil) }
    let compared: StudyMaterialComparison
    do {
      let original = try await store(at: url)
      compared = try await comparison(original, server)
      try await original.resolveMaterial(compared, choice: .keepLocal)
    }
    let store = try await StudyStore.open(at: url)
    let remote =
      change == "identity"
      ? compared.remote!.value : StudyMaterial(subjectID: 1, meaningNote: "Changed elsewhere")
    await server.configure(
      remote: change == "deletion" ? nil : remote, id: change == "identity" ? 202 : 201)
    let report = try await store.uploadPending(
      accountID: "account", token: "fixture", client: server.client)
    #expect(report.uploadedMaterials == 0 && report.materialsNeedingAttention == 1)
    let saved = try await pending(store)
    #expect(saved.material == local && saved.pending && saved.issue?.reason == .materialChanged)
    #expect(saved.attemptedRevision == nil && saved.attemptedMaterial == nil)
    #expect(await server.writes.isEmpty)
    _ = try await store.uploadPending(accountID: "account", token: "fixture", client: server.client)
    #expect(await server.writes.isEmpty)
    let latest = try await comparison(store, server)
    try await store.resolveMaterial(latest, choice: .keepLocal)
    let retried = try await store.uploadPending(
      accountID: "account", token: "fixture", client: server.client)
    #expect(retried.uploadedMaterials == 1 && retried.materialsNeedingAttention == 0)
  }

  @Test func comparisonCannotClearANewerUncertainAttemptWithoutAContentEdit() async throws {
    let store = try await store()
    let server = MaterialRecoveryServer()
    let old = try await comparison(store, server)
    await server.fault(timeoutWrite: true)
    await #expect(throws: URLError.self) {
      try await store.uploadPending(accountID: "account", token: "fixture", client: server.client)
    }
    let attempted = try await pending(store)
    #expect(attempted.revision == old.saved.revision && attempted.attemptedRevision != nil)
    for choice in [StudyMaterialResolution.useServer, .keepLocal] {
      await #expect(throws: StudyRecoveryError.self) {
        try await store.resolveMaterial(old, choice: choice)
      }
    }
    #expect(try await pending(store).attemptedRevision == attempted.attemptedRevision)
    #expect(try await pending(store).pending)
    #expect(await server.writes.count == 1)
  }

  @Test func staleComparisonCannotReplaceANewerLocalEditOrAnotherWindowsChoice() async throws {
    let store = try await store()
    let server = MaterialRecoveryServer()
    let old = try await comparison(store, server)
    let newer = StudyMaterial(subjectID: 1, meaningNote: "New draft")
    try await store.saveMaterial(newer, accountID: "account", expectedRevision: old.saved.revision)
    for choice in [StudyMaterialResolution.useServer, .keepLocal] {
      await #expect(throws: StudyRecoveryError.self) {
        try await store.resolveMaterial(old, choice: choice)
      }
    }
    #expect(try await pending(store).material == newer)
    let first = try await comparison(store, server)
    let second = try await comparison(store, server)
    try await store.resolveMaterial(first, choice: .keepLocal)
    await #expect(throws: StudyRecoveryError.self) {
      try await store.resolveMaterial(second, choice: .useServer)
    }
    #expect(try await pending(store).material == newer)
    #expect(await server.writes.isEmpty)
  }

  @Test func accountMismatchAndRateLimitCannotReleaseAnUncertainAttempt() async throws {
    let store = try await store()
    let server = MaterialRecoveryServer()
    await server.fault(timeoutWrite: true)
    await #expect(throws: URLError.self) {
      try await store.uploadPending(accountID: "account", token: "fixture", client: server.client)
    }
    let before = try await pending(store)
    await server.fault(identity: "other")
    await #expect(throws: StudyUploadError.self) { try await comparison(store, server) }
    await #expect(throws: StudyUploadError.self) {
      try await store.compareMaterial(
        before, credentialID: "other", token: "fixture", client: server.client)
    }
    await server.fault(limitRead: true)
    await #expect(throws: WaniKaniClient.APIError.self) { try await comparison(store, server) }
    let requestCount = await server.requests.count
    await #expect(throws: WaniKaniClient.APIError.self) { try await comparison(store, server) }
    #expect(await server.requests.count == requestCount)
    #expect(try await store.uploadRetryDate(accountID: "account") != nil)
    let after = try await pending(store)
    #expect(
      after.attemptedRevision == before.attemptedRevision
        && after.attemptedMaterial == before.attemptedMaterial)
    #expect(after.issue?.reason == .uncertain && after.pending)
    #expect(await server.writes.count == 1)
  }

  @Test func concurrentEditDuringReadPreventsPublishingAnObsoleteComparison() async throws {
    let store = try await store()
    let server = MaterialRecoveryServer()
    let gate = MaterialReadGate()
    await server.pause(gate)
    let run = Task { try await comparison(store, server) }
    await gate.entered()
    let before = try await pending(store)
    let newer = StudyMaterial(subjectID: 1, meaningNote: "Edited during GET")
    try await store.saveMaterial(newer, accountID: "account", expectedRevision: before.revision)
    await gate.resume()
    await #expect(throws: StudyRecoveryError.self) { try await run.value }
    #expect(try await pending(store).material == newer)
    #expect(await server.writes.isEmpty)
  }

  @Test func disconnectCancellationDrainsComparisonAndFencesOlderChoices() async throws {
    let store = try await store()
    let server = MaterialRecoveryServer()
    let gate = MaterialReadGate()
    let old = try await comparison(store, server)
    await server.pause(gate)
    let run = Task { try await comparison(store, server) }
    await gate.entered()
    let cancel = Task { await store.cancelSynchronization() }
    await gate.cancellationObserved()
    await #expect(throws: StudyUploadError.self) {
      try await store.uploadPending(accountID: "account", token: "fixture", client: server.client)
    }
    await #expect(throws: StudyUploadError.self) {
      try await store.refresh(credentialID: "credential", token: "fixture", client: server.client)
    }
    await #expect(throws: StudyUploadError.self) {
      try await store.synchronize(
        credentialID: "credential", token: "fixture", client: server.client)
    }
    await gate.resume()
    await #expect(throws: CancellationError.self) { try await run.value }
    await cancel.value
    await #expect(throws: StudyRecoveryError.self) {
      try await store.resolveMaterial(old, choice: .keepLocal)
    }
    #expect(try await pending(store).pending)
    #expect(await server.writes.isEmpty)
  }

  @Test func rateLimitObservedDuringALocalEditStillPausesTheAccount() async throws {
    let store = try await store()
    let server = MaterialRecoveryServer()
    let gate = MaterialReadGate()
    await server.fault(limitRead: true)
    await server.pause(gate)
    let run = Task { try await comparison(store, server) }
    await gate.entered()
    let before = try await pending(store)
    let newer = StudyMaterial(subjectID: 1, meaningNote: "Changed while limited")
    try await store.saveMaterial(newer, accountID: "account", expectedRevision: before.revision)
    await gate.resume()
    await #expect(throws: WaniKaniClient.APIError.self) { try await run.value }
    #expect(try await store.uploadRetryDate(accountID: "account") != nil)
    #expect(try await pending(store).material == newer)
    #expect(await server.writes.isEmpty)
  }

  @Test func choosingAMissingServerVersionOnlyClearsTheLocalPendingEdit() async throws {
    let store = try await store()
    let server = MaterialRecoveryServer()
    await server.configure(remote: nil)
    let compared = try await comparison(store, server)
    try await store.resolveMaterial(compared, choice: .useServer)
    let saved = try await pending(store)
    #expect(!saved.pending && saved.material == StudyMaterial(subjectID: 1))
    #expect(saved.serverID == nil && saved.attemptedRevision == nil && saved.issue == nil)
    _ = try await store.uploadPending(accountID: "account", token: "fixture", client: server.client)
    #expect(await server.writes.isEmpty)
  }

  @Test func confirmedOlderWriteAdvancesTheBaselineForANewerLocalEdit() async throws {
    let store = try await store()
    let server = MaterialRecoveryServer()
    let gate = MaterialReadGate()
    let compared = try await comparison(store, server)
    try await store.resolveMaterial(compared, choice: .keepLocal)
    await server.pause(gate, writes: true)
    let run = Task {
      try await store.uploadPending(accountID: "account", token: "fixture", client: server.client)
    }
    await gate.entered()
    let before = try await pending(store)
    let newer = StudyMaterial(subjectID: 1, meaningNote: "Newer than confirmed write")
    try await store.saveMaterial(newer, accountID: "account", expectedRevision: before.revision)
    await gate.resume()
    _ = try await run.value
    #expect(try await pending(store).pending)
    let report = try await store.uploadPending(
      accountID: "account", token: "fixture", client: server.client)
    #expect(report.uploadedMaterials == 1 && report.materialsNeedingAttention == 0)
    #expect(try await pending(store).material == newer)
    #expect(await server.writes.count == 2)
  }
}
