import Foundation
import Observation
import StudyCore
import StudyPersistence
import StudyTestSupport
import StudyUI
import Testing

private actor AutomaticServer: WaniKaniService {
  enum Fault: Equatable { case none, offline, lostReply, unauthorized, throttled }
  var data: StudyDownload
  var fault: Fault = .none
  var differentAccount = false
  var gate: StudyTaskGate?
  private(set) var writes = 0
  private(set) var fullReads = 0
  private(set) var identityReads = 0
  init(_ data: StudyDownload) { self.data = data }
  func configure(_ fault: Fault = .none, differentAccount: Bool = false, gate: StudyTaskGate? = nil)
  {
    self.fault = fault
    self.differentAccount = differentAccount
    self.gate = gate
  }
  func grant(_ level: Int) {
    data.profile.maxLevelGranted = level
    data.profile.subscribed = level > 3
  }
  func vacation(_ enabled: Bool) { data.profile.vacationStartedAt = enabled ? 100 : nil }
  func account(token: String) throws -> WaniKaniAccount {
    identityReads += 1
    if fault == .offline { throw URLError(.notConnectedToInternet) }
    return .init(
      id: differentAccount ? "another-account" : data.accountID,
      username: data.profile.username, level: data.profile.level,
      onVacation: data.profile.vacationStartedAt != nil, profile: data.profile)
  }
  func download(token: String) -> StudyDownload {
    fullReads += 1
    return data
  }
  func assignment(subjectID: Int64, token: String) -> CatalogAssignment? {
    data.assignments.first { $0.subjectID == subjectID }
  }
  func material(subjectID: Int64, token: String) -> WaniKaniMaterial? {
    data.materials.first { $0.value.subjectID == subjectID }
  }
  private func beginWrite() async throws {
    writes += 1
    if let gate {
      self.gate = nil
      await gate.pause()
    }
    if fault == .unauthorized { throw WaniKaniClient.APIError.unauthorized }
    if fault == .throttled {
      throw WaniKaniClient.APIError.rateLimited(retryAt: Date().addingTimeInterval(60))
    }
  }
  func submit(_ answer: StudyReviewSubmission, token: String, now: Date) async throws
    -> CatalogAssignment
  {
    try await beginWrite()
    let index = data.assignments.firstIndex { $0.subjectID == answer.subjectID }!
    var assignment = data.assignments[index]
    assignment.srsStage = answer.isLesson ? 1 : assignment.srsStage + 1
    assignment.availableAt = Int64(now.timeIntervalSince1970) + 3600
    assignment.startedAt = assignment.startedAt ?? Int64(now.timeIntervalSince1970)
    data.assignments[index] = assignment
    if fault == .lostReply { throw URLError(.timedOut) }
    return assignment
  }
  func writeMaterial(_ value: StudyMaterial, serverID: Int64?, token: String) async throws
    -> WaniKaniMaterial
  {
    try await beginWrite()
    let material = WaniKaniMaterial(id: serverID ?? 201, value: value)
    data.materials.removeAll { $0.value.subjectID == value.subjectID }
    data.materials.append(material)
    if fault == .lostReply { throw URLError(.timedOut) }
    return material
  }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct AutomaticSyncTests {
  private let account = "fixture-user-id"
  private func environment() async throws -> (
    StudyStore, StudyAppModel, AutomaticServer, StudyAutomaticSync, AsyncStream<Bool>.Continuation
  ) {
    let data = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    let server = AutomaticServer(data)
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let credential = StudyAppModel.credentialID("fixture")
    _ = try await store.synchronize(credentialID: credential, token: "fixture", client: server)
    let model = StudyAppModel(
      credentials: MemoryCredentials("fixture"), client: server, openStore: { store })
    await model.restore()
    let (paths, connection) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let sync = StudyAutomaticSync(model: model, paths: paths)
    sync.start()
    return (store, model, server, sync, connection)
  }
  private func edit(_ text: String, store: StudyStore) async throws {
    let saved = try #require(await store.materials(accountID: account).first)
    var material = saved.material
    material.meaningNote = text
    try await store.saveMaterial(material, accountID: account, expectedRevision: saved.revision)
  }
  private func completeReview(_ store: StudyStore) async throws {
    let assignment = try #require(await store.assignments(accountID: account).first)
    var session = try StudySession(items: [assignment.sessionItem(id: 0, isLesson: false)], seed: 1)
    while let question = session.nextQuestion() {
      _ = try session.mark(.correct, for: question, now: Int64(Date().timeIntervalSince1970))
    }
    try await store.saveSession(session, accountID: account, expectedRevision: nil)
  }
  private func empty(_ store: StudyStore) async throws {
    for await _ in await store.changes() {
      if try await store.savedWork(accountID: account).isEmpty { return }
    }
  }
  private func notice(_ sync: StudyAutomaticSync, containing text: String) async {
    for await value in Observations({ sync.notice }) {
      if value?.contains(text) == true { return }
    }
  }

  private func idle(_ model: StudyAppModel) async {
    for await busy in Observations({ model.isSyncing }) { if !busy { return } }
  }

  @Test func confirmedReviewsUploadWithoutAnotherCatalogDownloadOrSessionReset() async throws {
    let (store, model, server, sync, connection) = try await environment()
    defer {
      connection.finish()
      withExtendedLifetime(sync) {}
    }
    let reads = await server.fullReads
    connection.yield(true)
    try await completeReview(store)
    let session = try #require(await store.session(accountID: account))
    try await empty(store)
    await idle(model)
    #expect(await server.writes == 1)
    #expect(await server.fullReads == reads)
    #expect(try await store.assignments(accountID: account).first?.srsStage == 6)
    #expect(try await store.session(accountID: account)?.revision == session.revision)
    #expect(model.snapshot?.accountID == account)
    #expect(sync.notice == nil)
  }
  @Test func offlineNotesSendWhenTheConnectionReturns() async throws {
    let (store, _, server, sync, connection) = try await environment()
    defer {
      connection.finish()
      withExtendedLifetime(sync) {}
    }
    connection.yield(false)
    try await edit("offline draft", store: store)
    await notice(sync, containing: "Offline")
    #expect(await server.writes == 0)
    connection.yield(true)
    try await empty(store)
    #expect(await server.writes == 1)
    #expect(await server.data.materials.first?.value.meaningNote == "offline draft")
  }
  @Test func anEditDuringAnUploadGetsItsOwnAcknowledgement() async throws {
    let (store, _, server, sync, connection) = try await environment()
    defer {
      connection.finish()
      withExtendedLifetime(sync) {}
    }
    let gate = StudyTaskGate()
    await server.configure(gate: gate)
    connection.yield(true)
    try await edit("first draft", store: store)
    await gate.waitForEntry()
    try await edit("newer draft", store: store)
    await gate.resume()
    try await empty(store)
    #expect(await server.writes == 2)
    #expect(await server.data.materials.first?.value.meaningNote == "newer draft")
  }
  @Test func aLostReviewReplyIsNeverReplayedByConnectionOrForegroundWakes() async throws {
    let (store, model, server, sync, connection) = try await environment()
    defer {
      connection.finish()
      withExtendedLifetime(sync) {}
    }
    await server.grant(3)
    await server.configure(.lostReply)
    connection.yield(true)
    try await completeReview(store)
    await notice(sync, containing: "needs attention")
    #expect(model.maximumContentLevel == 3)
    await server.configure()
    connection.yield(false)
    connection.yield(true)
    sync.wake()
    await notice(sync, containing: "needs attention")
    #expect(await server.writes == 1)
    #expect(try await store.pendingReviews(accountID: account).first?.issue?.reason == .uncertain)
  }
  @Test func vacationUpdatesLocalGatesAndAllowsNotesBeforeReviewsResume() async throws {
    let (store, model, server, sync, connection) = try await environment()
    defer {
      connection.finish()
      withExtendedLifetime(sync) {}
    }
    await server.vacation(true)
    connection.yield(false)
    try await completeReview(store)
    try await edit("vacation note", store: store)
    connection.yield(true)
    await notice(sync, containing: "Vacation")
    #expect(model.snapshot?.onVacation == true)
    #expect(await server.writes == 1)
    #expect(try await store.pendingReviews(accountID: account).count == 1)
    await server.vacation(false)
    sync.wake()
    try await empty(store)
    await idle(model)
    #expect(await server.writes == 2)
    #expect(model.snapshot?.onVacation == false)
  }
  @Test func aDifferentAccountCannotSendAndAnExplicitWakeCanRecover() async throws {
    let (store, _, server, sync, connection) = try await environment()
    defer {
      connection.finish()
      withExtendedLifetime(sync) {}
    }
    await server.configure(differentAccount: true)
    connection.yield(true)
    try await edit("account-bound note", store: store)
    await notice(sync, containing: "different WaniKani account")
    #expect(await server.writes == 0)
    await server.configure()
    sync.wake()
    try await empty(store)
    #expect(await server.writes == 1)
  }
  @Test func aServerThrottleRetainsTheDeadlineAndDoesNotSpinWrites() async throws {
    let (store, _, server, sync, connection) = try await environment()
    defer {
      connection.finish()
      withExtendedLifetime(sync) {}
    }
    await server.configure(.throttled)
    connection.yield(true)
    try await completeReview(store)
    await notice(sync, containing: "limiting requests")
    let deadline = try #require(await store.uploadRetryDate(accountID: account))
    #expect(deadline > Date())
    sync.wake()
    await notice(sync, containing: "limiting requests")
    #expect(await server.writes == 1)
    #expect(try await store.automaticWorkState(accountID: account) == .ready)
  }
  @Test func unauthorizedWritesPauseUntilExplicitRecoveryWithoutLoopingOnCommits() async throws {
    let (store, model, server, sync, connection) = try await environment()
    defer {
      connection.finish()
      withExtendedLifetime(sync) {}
    }
    await server.configure(.unauthorized)
    connection.yield(true)
    try await edit("first draft", store: store)
    await notice(sync, containing: "rejected this token")
    let revision = model.dataRevision
    try await edit("new draft while paused", store: store)
    for await changed in Observations({ model.dataRevision }) { if changed != revision { break } }
    #expect(await server.writes == 1)
    #expect(try await store.automaticWorkState(accountID: account) == .ready)
    await server.configure()
    sync.wake()
    try await empty(store)
    #expect(await server.writes == 2)
    #expect(await server.data.materials.first?.value.meaningNote == "new draft while paused")
  }

  @Test func disconnectDrainsAnInFlightWriteAndReconnectionKeepsItUncertain() async throws {
    let (store, model, server, sync, connection) = try await environment()
    defer {
      connection.finish()
      withExtendedLifetime(sync) {}
    }
    let gate = StudyTaskGate()
    await server.configure(gate: gate)
    connection.yield(true)
    try await completeReview(store)
    await gate.waitForEntry()
    let disconnect = Task { await model.disconnect() }
    await gate.waitForCancellation()
    await gate.resume()
    await disconnect.value
    #expect(model.snapshot == nil)
    #expect(try await store.pendingReviews(accountID: account).first?.attempted == true)
    try await model.connect("fixture")
    await notice(sync, containing: "needs attention")
    #expect(await server.writes == 1)
    #expect(try await store.pendingReviews(accountID: account).count == 1)
  }

}
