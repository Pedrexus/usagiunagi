import Foundation
import StudyCore
import StudyPersistence
import StudyTestSupport
import StudyUI
import Testing

@MainActor final class MemoryCredentials: StudyCredentialStore {
  var token: String?
  var failLoads = false
  var failSaves = false
  var failRemoves = false
  private(set) var saved: [String] = []
  init(_ token: String? = nil) { self.token = token }
  func load() throws -> String? {
    if failLoads { throw CocoaError(.fileReadNoPermission) }
    return token
  }
  func save(_ token: String) throws {
    if failSaves { throw CocoaError(.fileWriteNoPermission) }
    self.token = token
    saved.append(token)
  }
  func remove() throws {
    if failRemoves { throw CocoaError(.fileWriteNoPermission) }
    token = nil
  }
}

private actor ModelServer {
  let gate: StudyTaskGate?
  var failAfterWrite: Bool
  private(set) var reads = 0
  private(set) var writes = 0
  private(set) var subjectReads = 0
  private var material = DownloadFixture.rows["study_materials"]!.first!
  init(gate: StudyTaskGate? = nil, failAfterWrite: Bool = false) {
    self.gate = gate
    self.failAfterWrite = failAfterWrite
  }
  var client: WaniKaniClient { .init { try await self.respond($0) } }
  func allowReads() { failAfterWrite = false }
  private func respond(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let path = request.url!.lastPathComponent
    let other = request.value(forHTTPHeaderField: "Authorization") == "Bearer other"
    if request.value(forHTTPHeaderField: "Authorization") == "Bearer rejected" {
      return try DownloadFixture.response(
        request, object: ["error": "Rejected fixture"], status: 401)
    }
    if request.httpMethod != "GET" {
      writes += 1
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      var value = body["study_material"] as! [String: Any]
      value["subject_id"] = 1
      material = DownloadFixture.resource(201, "study_material", value)
      return try DownloadFixture.response(request, object: material)
    }
    reads += 1
    if path == "subjects" {
      subjectReads += 1
      if subjectReads == 1, let gate { await gate.pause() }
      if failAfterWrite, writes > 0 { throw URLError(.notConnectedToInternet) }
    }
    if path == "study_materials" {
      return try DownloadFixture.response(request, object: DownloadFixture.collection([material]))
    }
    if path == "user", other {
      var user = DownloadFixture.user
      var data = user["data"] as! [String: Any]
      data["id"] = "other-account"
      data["username"] = "other"
      user["data"] = data
      return try DownloadFixture.response(request, object: user)
    }
    return try DownloadFixture.response(request)
  }
}

private actor ModelRepository {
  let store: StudyStore
  var failFirst: Bool
  private(set) var opens = 0
  init(store: StudyStore, failFirst: Bool = false) {
    self.store = store
    self.failFirst = failFirst
  }
  func open() throws -> StudyStore {
    opens += 1
    if failFirst, opens == 1 { throw CocoaError(.fileReadCorruptFile) }
    return store
  }
}

@MainActor @Suite struct StudyAppModelTests {
  private let account = "fixture-user-id"
  private var credential: String { StudyAppModel.credentialID("fixture") }

  private func store(cached: Bool = false, pendingNote: Bool = false) async throws -> StudyStore {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    if cached || pendingNote {
      _ = try await store.refresh(
        credentialID: credential, token: "fixture",
        client: WaniKaniClient(transport: DownloadFixture.response))
      if pendingNote {
        let saved = try #require(await store.materials(accountID: account).first)
        _ = try await store.saveMaterial(
          .init(subjectID: 1, meaningNote: "Unsent local note"),
          accountID: account, expectedRevision: saved.revision)
      }
    }
    return store
  }

  @Test func noCredentialDoesNotOpenStorageOrUseTheNetwork() async throws {
    let cache = try await store()
    let repository = ModelRepository(store: cache)
    let server = ModelServer()
    let model = StudyAppModel(
      credentials: MemoryCredentials(), client: await server.client,
      openStore: { try await repository.open() })
    await model.restore()
    #expect(model.snapshot == nil && model.profile == nil && !model.isSyncing)
    #expect(model.maximumContentLevel == 3 && !model.contentAccessVerified)
    #expect(await repository.opens == 0)
    #expect(await server.reads == 0)
  }

  @Test func restoreUsesTheSavedAccountAndOnlyOpensTheRepositoryOnce() async throws {
    let cache = try await store(pendingNote: true)
    let repository = ModelRepository(store: cache)
    let server = ModelServer()
    let credentials = MemoryCredentials("fixture")
    let model = StudyAppModel(
      credentials: credentials, client: await server.client,
      openStore: { try await repository.open() })
    await model.restore()
    await model.restore()
    #expect(model.snapshot?.accountID == account && model.profile?.username == "test")
    #expect(model.maximumContentLevel == 60 && model.contentAccessVerified && !model.isSyncing)
    #expect(await repository.opens == 1)
    #expect(await server.reads == 0)
    #expect(credentials.saved.isEmpty)
    #expect(try await cache.savedWork(accountID: account).materials.count == 1)
  }

  @Test func connectTrimsAndSavesOnlyAfterAVerifiedDownload() async throws {
    let cache = try await store()
    let credentials = MemoryCredentials()
    let server = ModelServer()
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    try await model.connect("  fixture\n")
    #expect(credentials.token == "fixture" && credentials.saved == ["fixture"])
    #expect(model.snapshot?.accountID == account && model.profile?.username == "test")
    #expect(try await cache.snapshot(credentialID: credential)?.accountID == account)
    #expect(try await cache.snapshot(credentialID: "fixture") == nil)
    #expect(!model.isSyncing && model.error == nil)
    #expect(await server.writes == 0)
  }

  @Test func rejectedConnectionPreservesThePreviousAccountAndUnsentWork() async throws {
    let cache = try await store(pendingNote: true)
    let credentials = MemoryCredentials("fixture")
    let server = ModelServer()
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    await model.restore()
    await #expect(throws: WaniKaniClient.APIError.self) { try await model.connect("rejected") }
    #expect(model.snapshot?.accountID == account && model.profile?.username == "test")
    #expect(credentials.token == "fixture" && credentials.saved.isEmpty)
    #expect(model.error != nil && !model.isSyncing)
    #expect(try await cache.savedWork(accountID: account).materials.count == 1)
    #expect(await server.writes == 0)
  }

  @Test func credentialSaveFailureCannotPublishAnAccountSwitch() async throws {
    let cache = try await store(cached: true)
    let credentials = MemoryCredentials("fixture")
    let server = ModelServer()
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    await model.restore()
    credentials.failSaves = true
    await #expect(throws: CocoaError.self) { try await model.connect("other") }
    #expect(model.snapshot?.accountID == account && model.profile?.username == "test")
    #expect(credentials.token == "fixture" && credentials.saved.isEmpty)
    #expect(try await cache.snapshot(credentialID: credential)?.accountID == account)
  }

  @Test func switchingAccountsKeepsTheOldOutboxIsolatedForRecovery() async throws {
    let cache = try await store(pendingNote: true)
    let credentials = MemoryCredentials("fixture")
    let server = ModelServer()
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    await model.restore()
    try await model.connect("other")
    #expect(model.snapshot?.accountID == "other-account" && model.profile?.username == "other")
    #expect(credentials.token == "other")
    #expect(try await cache.snapshot(credentialID: credential) == nil)
    await #expect(throws: StudyStoreError.self) {
      _ = try await cache.savedWork(accountID: account)
    }
    #expect(try await cache.materials(accountID: account).filter(\.pending).count == 1)
    #expect(try await cache.savedWork(accountID: "other-account").isEmpty)
    try await model.connect("fixture")
    #expect(model.snapshot?.accountID == account && credentials.token == "fixture")
    #expect(
      try await cache.savedWork(accountID: account).materials.first?.material.meaningNote
        == "Unsent local note")
    #expect(await server.writes == 0)
  }

  @Test func aFailedRepositoryOpenCanBeRetried() async throws {
    let cache = try await store()
    let repository = ModelRepository(store: cache, failFirst: true)
    let server = ModelServer()
    let credentials = MemoryCredentials()
    let model = StudyAppModel(
      credentials: credentials, client: await server.client,
      openStore: { try await repository.open() })
    await #expect(throws: CocoaError.self) { try await model.connect("fixture") }
    #expect(model.error != nil && !model.isSyncing)
    try await model.connect("fixture")
    #expect(model.snapshot?.accountID == account && model.error == nil)
    #expect(await repository.opens == 2)
  }

  @Test func restoreCanRetryAfterCredentialsBecomeReadable() async throws {
    let cache = try await store(cached: true)
    let credentials = MemoryCredentials("fixture")
    credentials.failLoads = true
    let model = StudyAppModel(credentials: credentials, openStore: { cache })
    await model.restore()
    #expect(model.snapshot == nil && model.error != nil && !model.isSyncing)
    credentials.failLoads = false
    await model.restore()
    #expect(
      model.snapshot?.accountID == account && model.profile?.username == "test"
        && model.error == nil)
  }

  @Test func activeConnectionFencesOtherCredentialsRestoreAndSampleChanges() async throws {
    let cache = try await store()
    let gate = StudyTaskGate()
    let server = ModelServer(gate: gate)
    let model = StudyAppModel(
      credentials: MemoryCredentials(), client: await server.client,
      openStore: { cache })
    let first = Task { try await model.connect("fixture") }
    await gate.waitForEntry()
    #expect(model.isSyncing)
    await model.restore()
    #expect(model.error == nil)
    model.loadPreview()
    #expect(model.snapshot == nil)
    await #expect(throws: StudyUploadError.self) { try await model.connect("other") }
    await gate.resume()
    try await first.value
    #expect(model.snapshot?.accountID == account && !model.isSyncing)
    #expect(await server.subjectReads == 1)
  }

  @Test func disconnectDrainsALateResponseAndPreventsResurrection() async throws {
    let cache = try await store()
    let gate = StudyTaskGate()
    let server = ModelServer(gate: gate)
    let credentials = MemoryCredentials()
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    let connection = Task { try await model.connect("fixture") }
    await gate.waitForEntry()
    let disconnect = Task { await model.disconnect() }
    await gate.waitForCancellation()
    #expect(model.isDisconnecting && model.isSyncing)
    await #expect(throws: StudyUploadError.self) { try await model.connect("other") }
    await gate.resume()
    await disconnect.value
    await #expect(throws: CancellationError.self) { try await connection.value }
    #expect(model.snapshot == nil && model.profile == nil && model.error == nil && !model.isSyncing)
    #expect(credentials.token == nil && credentials.saved.isEmpty)
    #expect(try await cache.snapshot(credentialID: credential) == nil)
    #expect(await server.writes == 0)
  }

  @Test func closingTheSharedSignInCannotCommitNewCredentialsOrReplaceTheVisibleAccount()
    async throws
  {
    let cache = try await store(pendingNote: true)
    let credentials = MemoryCredentials("fixture")
    let gate = StudyTaskGate()
    let server = ModelServer(gate: gate)
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    await model.restore()
    let signIn = StudySignIn { try await model.connect($0) }
    signIn.token = "other"
    let attempt = Task { await signIn.submit() }
    await gate.waitForEntry()
    signIn.cancel()
    // The cache pass is app-owned and may finish for another scene; this form owns no credential commit.
    await gate.resume()
    #expect(await attempt.value == nil)
    #expect(credentials.token == "fixture" && credentials.saved.isEmpty)
    #expect(model.snapshot?.accountID == account && model.error == nil && !model.isSyncing)
    #expect(try await cache.savedWork(accountID: account).materials.count == 1)
    #expect(await server.writes == 0)
  }

  @Test func refreshAndSampleBrowsingDoNotSendOrReplaceSavedWork() async throws {
    let cache = try await store(pendingNote: true)
    let server = ModelServer()
    let credentials = MemoryCredentials("fixture")
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    await model.restore()
    credentials.failSaves = true
    await model.refresh()
    #expect(model.error == nil && credentials.saved.isEmpty)
    #expect(try await cache.savedWork(accountID: account).materials.count == 1)
    model.loadPreview()
    #expect(model.snapshot?.isSample == true && model.snapshot?.subjects.count == 357)
    await #expect(throws: StudyStoreError.self) {
      try await model.syncSavedWork(accountID: account)
    }
    #expect(credentials.token == "fixture")
    #expect(try await cache.snapshot(credentialID: credential)?.accountID == account)
    #expect(try await cache.savedWork(accountID: account).materials.count == 1)
    #expect(await server.writes == 0)
  }

  @Test func anExplicitUploadRemainsAcknowledgedWhenItsFollowingRefreshFails() async throws {
    let cache = try await store(pendingNote: true)
    let server = ModelServer(failAfterWrite: true)
    let model = StudyAppModel(
      credentials: MemoryCredentials("fixture"), client: await server.client,
      openStore: { cache })
    await model.restore()
    await #expect(throws: StudySynchronizationFailure.self) {
      try await model.syncSavedWork(accountID: account)
    }
    #expect(model.syncSummary?.contains("1 note edits") == true && !model.isSyncing)
    #expect(try await cache.savedWork(accountID: account).materials.isEmpty)
    #expect(await server.writes == 1)
    await server.allowReads()
    await model.refresh()
    #expect(model.error == nil && model.snapshot?.accountID == account)
    #expect(await server.writes == 1)
  }
  @Test func oldJSONStatisticsRestoreOfflineWithoutChangingTheSource() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "snapshot-v1.json")
    let legacy = StudySnapshot(
      username: "Cached learner", currentLevel: 5,
      assignments: [], statistics: [], levels: [], subjects: [])
    let snapshot = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy))
    let original = try JSONSerialization.data(withJSONObject: [
      "snapshot": snapshot, "credentialID": credential,
    ])
    try original.write(to: url)
    let cache = try await store()
    let server = ModelServer()
    let model = StudyAppModel(
      credentials: MemoryCredentials("fixture"), client: await server.client,
      legacySnapshotURL: url, openStore: { cache })
    await model.restore()
    #expect(model.snapshot?.username == "Cached learner" && model.snapshot?.currentLevel == 5)
    #expect(model.profile == nil && !model.contentAccessVerified && model.maximumContentLevel == 3)
    #expect(try Data(contentsOf: url) == original)
    #expect(try await cache.snapshot(credentialID: credential)?.username == "Cached learner")
    #expect(await server.reads == 0)
  }

  @Test func aFailedCredentialRemovalKeepsTheAccountAndCacheUntilRetry() async throws {
    let cache = try await store(pendingNote: true)
    let credentials = MemoryCredentials("fixture")
    let server = ModelServer()
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    await model.restore()
    credentials.failRemoves = true
    await model.disconnect()
    #expect(model.snapshot?.accountID == account && model.profile?.username == "test")
    #expect(credentials.token == "fixture" && model.error != nil && !model.isSyncing)
    #expect(try await cache.savedWork(accountID: account).materials.count == 1)
    credentials.failRemoves = false
    await model.disconnect()
    #expect(model.snapshot == nil && model.profile == nil && credentials.token == nil)
    #expect(model.error == nil && !model.isSyncing)
    #expect(try await cache.snapshot(credentialID: credential) == nil)
    #expect(try await cache.materials(accountID: account).filter(\.pending).count == 1)
    #expect(await server.reads == 0)
    #expect(await server.writes == 0)
  }

  @Test func closingOneRestoreWaiterDoesNotCancelTheOtherWindowOrServiceOwner() async throws {
    let cache = try await store(cached: true)
    let gate = StudyTaskGate()
    let opening = ServiceStoreOpening(cache, gate: gate)
    let model = StudyAppModel(
      credentials: MemoryCredentials("fixture"), openStore: { try await opening.open() })
    let first = Task { await model.restore() }
    await gate.waitForEntry()
    let other = Task { await model.restore() }
    first.cancel()
    await gate.resume()
    await first.value
    await other.value
    #expect(await opening.calls == 1)
    #expect(model.snapshot?.accountID == account && model.error == nil && !model.isSyncing)
  }
  @Test func disconnectDuringRestoreRejectsTheLateCachedAccount() async throws {
    let cache = try await store(cached: true)
    let gate = StudyTaskGate()
    let opening = ServiceStoreOpening(cache, gate: gate)
    let credentials = MemoryCredentials("fixture")
    let model = StudyAppModel(credentials: credentials, openStore: { try await opening.open() })
    let restore = Task { await model.restore() }
    await gate.waitForEntry()
    let disconnect = Task { await model.disconnect() }
    for await busy in Observations({ model.isDisconnecting }) { if busy { break } }
    await gate.resume()
    await disconnect.value
    await restore.value
    #expect(model.snapshot == nil && credentials.token == nil && model.error == nil)
    await model.restore()
    #expect(model.snapshot == nil)
  }

  @Test func savedCredentialCanReadAColdCatalogWithoutRewritingTheKeychain() async throws {
    let cache = try await store()
    let credentials = MemoryCredentials("fixture")
    credentials.failSaves = true
    let model = StudyAppModel(
      credentials: credentials,
      client: WaniKaniClient(transport: DownloadFixture.response), openStore: { cache })
    await model.refresh()
    #expect(model.snapshot?.accountID == account && model.error == nil && model.restorationComplete)
    #expect(credentials.saved.isEmpty)
  }
  @Test func endpointCannotChangeWhileAnAccountOperationIsRunning() async throws {
    let cache = try await store(cached: true, pendingNote: true)
    let gate = StudyTaskGate()
    let opening = ServiceStoreOpening(cache, gate: gate)
    let model = StudyAppModel(
      credentials: MemoryCredentials("fixture"), openStore: { try await opening.open() })
    let restoring = Task { await model.restore() }
    await gate.waitForEntry()
    #expect(throws: StudyUploadError.self) {
      try model.setAPIEndpoint(WaniKaniClient.defaultBaseURL)
    }
    await gate.resume()
    await restoring.value
    try model.setAPIEndpoint(WaniKaniClient.defaultBaseURL)
    #expect(model.snapshot?.accountID == account)
    #expect(try await cache.savedWork(accountID: account).materials.count == 1)
  }

}
