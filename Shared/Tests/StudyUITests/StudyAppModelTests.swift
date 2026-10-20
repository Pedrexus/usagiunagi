import Foundation
import StudyCore
import StudyTestSupport
import StudyUI
import Testing

@testable import StudyPersistence

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
  enum AuthenticationFault: CaseIterable, Equatable, Sendable {
    case unauthorized, hibernating
    var error: any Error {
      switch self {
      case .unauthorized: WaniKaniClient.APIError.unauthorized
      case .hibernating: StudySignInError.hibernating
      }
    }
  }
  private var authenticationFault: AuthenticationFault?
  private var authenticationFailsAfterWrite = false
  func expire(_ fault: AuthenticationFault?, afterWrite: Bool = false) {
    authenticationFault = fault
    authenticationFailsAfterWrite = afterWrite
  }
  let gate: StudyTaskGate?
  var failAfterWrite: Bool
  private(set) var reads = 0
  private(set) var writes = 0
  private(set) var subjectReads = 0
  private var material = DownloadFixture.rows["study_materials"]!.first!
  private var user = DownloadFixture.user
  func changeProfile(username: String, level: Int) {
    var data = user["data"] as! [String: Any]
    data["username"] = username
    data["level"] = level
    user["data"] = data
  }
  init(gate: StudyTaskGate? = nil, failAfterWrite: Bool = false) {
    self.gate = gate
    self.failAfterWrite = failAfterWrite
  }
  var client: WaniKaniClient { .init { try await self.respond($0) } }
  func allowReads() { failAfterWrite = false }
  private func respond(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let path = request.url!.lastPathComponent
    let other = request.value(forHTTPHeaderField: "Authorization") == "Bearer other"
    if let authenticationFault, request.httpMethod == "GET",
      request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture",
      !authenticationFailsAfterWrite || (writes > 0 && path == "subjects")
    {
      reads += 1
      throw authenticationFault.error
    }
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
    if path == "user" {
      var user = user
      var data = user["data"] as! [String: Any]
      if other {
        data["id"] = "other-account"
        data["username"] = "other"
      }
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
    #expect(model.accountIssue == nil && model.reauthenticationContext == nil)
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

  @Test(arguments: [false, true])
  func cancelledRefreshWaiterStillPublishesTheCommittedAccountAtomically(_ explicitAccount: Bool)
    async throws
  {
    let cache = try await store(pendingNote: true)
    let credentials = MemoryCredentials("fixture")
    let gate = StudyTaskGate()
    let server = ModelServer(gate: gate)
    await server.changeProfile(username: "refreshed", level: 13)
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    await model.restore()
    let previousRevision = model.dataRevision
    let previousSnapshot = try #require(model.snapshot)
    let previousProfile = model.profile
    let note = try #require(await cache.materials(accountID: account).first)
    let request = Task {
      if explicitAccount {
        try await model.refresh(accountID: account)
      } else {
        await model.refresh()
      }
    }
    await gate.waitForEntry()
    #expect(model.isSyncing && model.snapshot?.username == previousSnapshot.username)
    #expect(model.profile == previousProfile && model.dataRevision == previousRevision)
    request.cancel()
    await gate.resume()
    if explicitAccount {
      await #expect(throws: CancellationError.self) { try await request.value }
    } else {
      try await request.value
    }
    let committed = try #require(await cache.snapshot(credentialID: credential))
    let committedProfile = try #require(await cache.accountState(accountID: account)).profile
    #expect(committed.username == "refreshed" && committed.currentLevel == 13)
    #expect(model.snapshot?.accountID == account && model.snapshot?.savedAt == committed.savedAt)
    #expect(model.snapshot?.username == committed.username && model.snapshot?.currentLevel == 13)
    #expect(model.profile == committedProfile && model.dataRevision != previousRevision)
    #expect(model.error == nil && !model.isSyncing)
    let retained = try #require(await cache.materials(accountID: account).first)
    #expect(
      retained.pending && retained.material == note.material && retained.revision == note.revision)
    #expect(await server.subjectReads == 1)
    #expect(await server.writes == 0)
    #expect(credentials.token == "fixture" && credentials.saved.isEmpty)
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
  @Test func reauthenticationRejectsAnotherAccountBeforeDownloadingOrMutatingAnySavedWork()
    async throws
  {
    let (cache, model, server, credentials) = try await expiredEnvironment()
    let context = try #require(model.reauthenticationContext)
    let before = try await cache.generationSnapshot()
    let profile = model.profile
    let savedAt = model.snapshot?.savedAt
    let reads = await server.reads
    await #expect(throws: StudySignInError.accountMismatch) {
      try await model.reauthenticate("other", context: context)
    }
    #expect(await server.reads == reads + 1)
    #expect(await server.subjectReads == 0)
    #expect(await server.writes == 0)
    #expect(try await cache.generationSnapshot() == before)
    #expect(model.snapshot?.accountID == account && model.snapshot?.savedAt == savedAt)
    #expect(model.profile == profile && model.reauthenticationContext == context)
    #expect(credentials.token == "fixture" && credentials.saved.isEmpty && !model.isSyncing)
    #expect(try await cache.snapshot(credentialID: StudyAppModel.credentialID("other")) == nil)
  }
  @Test func sameAccountReauthenticationReplacesOnlyCredentialsAndKeepsSessionOutboxAndNotes()
    async throws
  {
    let (cache, model, server, credentials) = try await expiredEnvironment()
    let context = try #require(model.reauthenticationContext)
    let before = try #require(await cache.session(accountID: account))
    let reviews = try await cache.pendingReviews(accountID: account)
    let note = try #require(await cache.materials(accountID: account).first)
    #expect(reviews.count == 1 && note.pending)
    try await model.reauthenticate("  replacement\n", context: context)
    #expect(credentials.token == "replacement" && credentials.saved == ["replacement"])
    #expect(model.snapshot?.accountID == account && model.profile?.username == "test")
    #expect(model.accountIssue == nil && model.reauthenticationContext == nil && model.error == nil)
    #expect(try await cache.snapshot(credentialID: credential) == nil)
    #expect(
      try await cache.snapshot(credentialID: StudyAppModel.credentialID("replacement"))?.accountID
        == account)
    let after = try #require(await cache.session(accountID: account))
    #expect(after.revision == before.revision && after.session.items == before.session.items)
    #expect(after.session.completedIDs == before.session.completedIDs)
    #expect(try await cache.pendingReviews(accountID: account) == reviews)
    let retained = try #require(await cache.materials(accountID: account).first)
    #expect(
      retained.material == note.material && retained.revision == note.revision && retained.pending)
    #expect(
      retained.attemptedRevision == note.attemptedRevision
        && retained.issue?.reason == note.issue?.reason)
    #expect(await server.writes == 0)
    #expect(!model.isSyncing)
  }
  @Test func staleReauthenticationCannotReplaceADeliberatelySwitchedAccount() async throws {
    let (cache, model, server, credentials) = try await expiredEnvironment()
    let context = try #require(model.reauthenticationContext)
    try await model.connect("other")
    let before = try await cache.generationSnapshot()
    let reads = await server.reads
    await #expect(throws: StudySignInError.accountChanged) {
      try await model.reauthenticate("replacement", context: context)
    }
    model.acknowledgeAccountIssue(context)
    #expect(model.snapshot?.accountID == "other-account" && model.profile?.username == "other")
    #expect(credentials.token == "other" && credentials.saved == ["other"])
    #expect(model.accountIssue == nil && !model.isSyncing)
    #expect(await server.reads == reads)
    #expect(await server.writes == 0)
    #expect(try await cache.generationSnapshot() == before)
    #expect(try await cache.pendingReviews(accountID: account).count == 1)
    #expect(try await cache.materials(accountID: account).first?.pending == true)
  }
  @Test func disconnectFencesALateReauthenticationWithoutResurrectingCredentialsOrAccount()
    async throws
  {
    let gate = StudyTaskGate()
    let (cache, model, server, credentials) = try await expiredEnvironment(gate: gate)
    let context = try #require(model.reauthenticationContext)
    let reviews = try await cache.pendingReviews(accountID: account)
    let note = try #require(await cache.materials(accountID: account).first)
    let attempt = Task { try await model.reauthenticate("replacement", context: context) }
    await gate.waitForEntry()
    let disconnect = Task { await model.disconnect() }
    await gate.waitForCancellation()
    await gate.resume()
    await disconnect.value
    await #expect(throws: CancellationError.self) { try await attempt.value }
    #expect(model.snapshot == nil && model.profile == nil && model.accountIssue == nil)
    #expect(credentials.token == nil && credentials.saved.isEmpty && !model.isSyncing)
    #expect(
      try await cache.snapshot(credentialID: StudyAppModel.credentialID("replacement")) == nil)
    #expect(try await cache.pendingReviews(accountID: account) == reviews)
    let retained = try #require(await cache.materials(accountID: account).first)
    #expect(
      retained.material == note.material && retained.revision == note.revision && retained.pending)
    let reads = await server.reads
    await #expect(throws: StudySignInError.accountChanged) {
      try await model.reauthenticate("replacement", context: context)
    }
    #expect(await server.reads == reads)
    #expect(await server.writes == 0)
  }
  @Test func closingReauthenticationCannotSaveANewTokenEvenWhenTheSharedReadReturnsLate()
    async throws
  {
    let gate = StudyTaskGate()
    let (cache, model, server, credentials) = try await expiredEnvironment(gate: gate)
    let context = try #require(model.reauthenticationContext)
    let reviews = try await cache.pendingReviews(accountID: account)
    let signIn = StudySignIn { try await model.reauthenticate($0, context: context) }
    signIn.token = "replacement"
    let attempt = Task { await signIn.submit() }
    await gate.waitForEntry()
    signIn.cancel()
    await gate.resume()
    #expect(await attempt.value == nil)
    #expect(credentials.token == "fixture" && credentials.saved.isEmpty)
    #expect(model.snapshot?.accountID == account && model.reauthenticationContext == context)
    #expect(model.accountIssue?.acknowledged == false && !model.isSyncing)
    #expect(try await cache.pendingReviews(accountID: account) == reviews)
    #expect(try await cache.materials(accountID: account).first?.pending == true)
    #expect(await server.writes == 0)
  }
  @Test(arguments: ModelServer.AuthenticationFault.allCases, [false, true])
  private func connectedAuthenticationIncidentsKeepStateAndAcknowledgementForTypedAndWrappedErrors(
    _ fault: ModelServer.AuthenticationFault, _ wrapped: Bool
  ) async throws {
    let cache = try await store(pendingNote: true)
    let credentials = MemoryCredentials("fixture")
    let server = ModelServer()
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    await model.restore()
    let before = try await cache.generationSnapshot()
    let profile = model.profile
    let savedAt = model.snapshot?.savedAt
    await server.expire(fault, afterWrite: wrapped)
    if wrapped {
      await #expect(throws: StudySynchronizationFailure.self) {
        try await model.syncSavedWork(accountID: account)
      }
      #expect(model.syncSummary?.contains("1 note edits") == true)
      #expect(try await cache.savedWork(accountID: account).isEmpty)
      #expect(await server.writes == 1)
    } else {
      await #expect(throws: (any Error).self) { try await model.refresh(accountID: account) }
      #expect(try await cache.generationSnapshot() == before)
      #expect(await server.writes == 0)
    }
    let issue = try #require(model.accountIssue)
    #expect(issue.reason == (fault == .unauthorized ? .unauthorized : .hibernating))
    #expect(
      issue.context.accountID == account && issue.context.username == "test" && !issue.acknowledged)
    #expect(model.profile == profile && model.snapshot?.savedAt == savedAt)
    #expect(credentials.token == "fixture" && credentials.saved.isEmpty && !model.isSyncing)
    model.acknowledgeAccountIssue(issue.context)
    #expect(
      model.accountIssue?.acknowledged == true && model.reauthenticationContext == issue.context)
    await server.expire(fault)
    await #expect(throws: (any Error).self) { try await model.refresh(accountID: account) }
    #expect(
      model.accountIssue?.acknowledged == true && model.reauthenticationContext == issue.context)
    #expect(await server.writes == (wrapped ? 1 : 0))
  }
  private func expiredEnvironment(gate: StudyTaskGate? = nil) async throws -> (
    StudyStore, StudyAppModel, ModelServer, MemoryCredentials
  ) {
    let cache = try await store(pendingNote: true)
    let assignment = try #require(await cache.assignments(accountID: account).first)
    var session = try StudySession(items: [assignment.sessionItem(id: 0, isLesson: false)], seed: 1)
    while let question = session.nextQuestion() {
      _ = try session.mark(.correct, for: question, now: 100)
    }
    try await cache.saveSession(session, accountID: account, expectedRevision: nil)
    let credentials = MemoryCredentials("fixture")
    let server = ModelServer(gate: gate)
    let model = StudyAppModel(
      credentials: credentials, client: await server.client, openStore: { cache })
    await model.restore()
    await server.expire(.unauthorized)
    await model.refresh()
    #expect(model.accountIssue?.reason == .unauthorized)
    return (cache, model, server, credentials)
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
