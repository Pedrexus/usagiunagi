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
  let now: @MainActor @Sendable () -> Date
  var readFault: Fault = .none
  var readGate: StudyTaskGate?
  var fault: Fault = .none
  var differentAccount = false
  var gate: StudyTaskGate?
  private(set) var writes = 0
  private(set) var fullReads = 0
  private(set) var identityReads = 0
  init(_ data: StudyDownload, now: @escaping @MainActor @Sendable () -> Date) {
    self.data = data
    self.now = now
  }
  func configureReads(_ fault: Fault = .none, gate: StudyTaskGate? = nil) {
    readFault = fault
    readGate = gate
  }
  func unlockLesson() {
    var subject = CatalogSubject(id: 900, kind: .kanji)
    subject.level = 1
    subject.japanese = "二"
    subject.meanings = [.init("Two", role: .primary)]
    subject.readings = [.init("に", isPrimary: true, kind: .onyomi)]
    var assignment = CatalogAssignment(id: 1900, subjectID: subject.id, kind: .kanji)
    assignment.level = 1
    assignment.unlockedAt = 1
    data.subjects.append(subject)
    data.assignments.append(assignment)
  }
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
  func download(token: String) async throws -> StudyDownload {
    fullReads += 1
    if let gate = readGate {
      readGate = nil
      await gate.pause()
    }
    if readFault == .offline { throw URLError(.notConnectedToInternet) }
    if readFault == .unauthorized { throw WaniKaniClient.APIError.unauthorized }
    if readFault == .throttled {
      throw WaniKaniClient.APIError.rateLimited(retryAt: Date().addingTimeInterval(60))
    }
    return StudyDownload(
      accountID: data.accountID, profile: data.profile,
      subjects: data.subjects, assignments: data.assignments, materials: data.materials,
      levels: data.levels, statistics: data.statistics, voices: data.voices,
      systems: data.systems, fetchedAt: await now())
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

@MainActor private final class AutomaticReadClock {
  var date = Date()
  func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct AutomaticSyncTests {
  private let account = "fixture-user-id"
  private func environment(
    now: @escaping @MainActor @Sendable () -> Date = { .now },
    credentials: MemoryCredentials? = nil
  ) async throws -> (
    StudyStore, StudyAppModel, AutomaticServer, StudyAutomaticSync, AsyncStream<Bool>.Continuation
  ) {
    let data = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    let server = AutomaticServer(data, now: now)
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let credential = StudyAppModel.credentialID("fixture")
    _ = try await store.synchronize(credentialID: credential, token: "fixture", client: server)
    let model = StudyAppModel(
      credentials: credentials ?? MemoryCredentials("fixture"), client: server, openStore: { store }
    )
    await model.restore()
    let (paths, connection) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let sync = StudyAutomaticSync(model: model, paths: paths, now: now)
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
    await sync.wake()
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
    await sync.wake()
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
    await sync.wake()
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
    await sync.wake()
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
    let context = try #require(model.reauthenticationContext)
    #expect(context.accountID == account && context.username == "test")
    #expect(
      model.accountIssue?.reason == .unauthorized && model.accountIssue?.acknowledged == false)
    model.acknowledgeAccountIssue(context)
    let revision = model.dataRevision
    try await edit("new draft while paused", store: store)
    for await changed in Observations({ model.dataRevision }) { if changed != revision { break } }
    #expect(await server.writes == 1)
    #expect(try await store.automaticWorkState(accountID: account) == .ready)
    await server.configure()
    await sync.wake()
    try await empty(store)
    #expect(await server.writes == 2)
    #expect(await server.data.materials.first?.value.meaningNote == "new draft while paused")
    #expect(model.accountIssue == nil && model.reauthenticationContext == nil)
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

  @Test func foregroundReadsStayFreshWithoutRewritingCredentialsOrUploading() async throws {
    let clock = AutomaticReadClock()
    let credentials = MemoryCredentials("fixture")
    credentials.failSaves = true
    let (_, model, server, sync, connection) = try await environment(
      now: { clock.date }, credentials: credentials)
    defer { connection.finish() }
    let reads = await server.fullReads
    sync.updateScene(UUID(), active: true, studying: false)
    connection.yield(true)
    await sync.wake()
    #expect(await server.fullReads == reads)
    clock.advance(1801)
    await sync.wake()
    #expect(await server.fullReads == reads + 1)
    #expect(model.snapshot?.savedAt == clock.date)
    await sync.wake()
    await sync.wake()
    #expect(await server.fullReads == reads + 1)
    #expect(await server.writes == 0)
    #expect(credentials.saved.isEmpty && credentials.token == "fixture")
  }
  @Test func completedStudyReadsNewUnlocksAfterLeavingStudyWithoutChangingTheSession() async throws
  {
    let clock = AutomaticReadClock()
    let (store, model, server, sync, connection) = try await environment(now: { clock.date })
    defer { connection.finish() }
    let scene = UUID()
    sync.updateScene(scene, active: true, studying: true)
    connection.yield(true)
    let reads = await server.fullReads
    await server.unlockLesson()
    try await completeReview(store)
    let session = try #require(await store.session(accountID: account))
    await sync.wake()
    clock.advance(61)
    await sync.wake()
    #expect(await server.fullReads == reads)
    #expect(await server.writes == 1)
    sync.updateScene(scene, active: true, studying: false)
    await sync.wake()
    #expect(await server.fullReads == reads + 1)
    #expect(model.snapshot?.subjects.contains { $0.id == 900 } == true)
    #expect(
      try await store.assignments(accountID: account).contains {
        $0.subjectID == 900 && $0.srsStage == 0
      })
    #expect(try await store.session(accountID: account)?.revision == session.revision)
    #expect(try await store.savedWork(accountID: account).isEmpty)
  }
  @Test func uncertainWorkCanRefreshButIsNeverReplayedOrAcknowledgedByARead() async throws {
    let clock = AutomaticReadClock()
    let (store, model, server, sync, connection) = try await environment(now: { clock.date })
    defer { connection.finish() }
    let scene = UUID()
    sync.updateScene(scene, active: true, studying: true)
    connection.yield(true)
    await server.configure(.lostReply)
    try await completeReview(store)
    await sync.wake()
    let reads = await server.fullReads
    await server.configure()
    await server.unlockLesson()
    clock.advance(61)
    sync.updateScene(scene, active: true, studying: false)
    await sync.wake()
    #expect(await server.fullReads == reads + 1)
    #expect(await server.writes == 1)
    let pending = try #require(await store.pendingReviews(accountID: account).first)
    #expect(pending.attempted && pending.issue?.reason == .uncertain)
    #expect(model.snapshot?.subjects.contains { $0.id == 900 } == true)
    #expect(sync.notice?.contains("needs attention") == true)
  }
  @Test func scenesShareOneReadOwnerAndBackgroundWindowsDoNotRead() async throws {
    let clock = AutomaticReadClock()
    let (_, _, server, sync, connection) = try await environment(now: { clock.date })
    defer { connection.finish() }
    let study = UUID()
    let home = UUID()
    sync.updateScene(study, active: true, studying: true)
    sync.updateScene(home, active: true, studying: false)
    connection.yield(true)
    let reads = await server.fullReads
    clock.advance(1801)
    await sync.wake()
    #expect(await server.fullReads == reads)
    sync.removeScene(study)
    await sync.wake()
    #expect(await server.fullReads == reads + 1)
    sync.updateScene(home, active: false, studying: false)
    clock.advance(1801)
    await sync.wake()
    #expect(await server.fullReads == reads + 1)
    sync.updateScene(home, active: true, studying: false)
    await sync.wake()
    #expect(await server.fullReads == reads + 2)
    #expect(await server.writes == 0)
  }
  @Test func failedAutomaticReadKeepsTheCacheAndAnExplicitWakeRecovers() async throws {
    let clock = AutomaticReadClock()
    let (_, model, server, sync, connection) = try await environment(now: { clock.date })
    defer { connection.finish() }
    let saved = try #require(model.snapshot?.savedAt)
    let reads = await server.fullReads
    sync.updateScene(UUID(), active: true, studying: false)
    connection.yield(true)
    clock.advance(1801)
    await server.configureReads(.offline)
    await sync.wake()
    #expect(model.snapshot?.savedAt == saved && sync.notice?.contains("Couldn't refresh") == true)
    #expect(await server.fullReads == reads + 1)
    #expect(await server.writes == 0)
    await server.configureReads()
    await sync.wake()
    #expect(model.snapshot?.savedAt == clock.date && sync.notice == nil)
    #expect(await server.fullReads == reads + 2)
    #expect(await server.writes == 0)
  }
  @Test func readRateLimitsKeepTheirDurableDeadlineAcrossWakes() async throws {
    let clock = AutomaticReadClock()
    let (store, _, server, sync, connection) = try await environment(now: { clock.date })
    defer { connection.finish() }
    sync.updateScene(UUID(), active: true, studying: false)
    connection.yield(true)
    clock.advance(1801)
    await server.configureReads(.throttled)
    await sync.wake()
    let deadline = try #require(await store.uploadRetryDate(accountID: account))
    let reads = await server.fullReads
    await sync.wake()
    await sync.wake()
    #expect(try await store.uploadRetryDate(accountID: account) == deadline && deadline > Date())
    #expect(await server.fullReads == reads)
    #expect(await server.writes == 0)
    #expect(sync.notice?.contains("limiting requests") == true)
  }
  @Test func disconnectDrainsAnAutomaticReadWithoutRestoringTheRemovedAccount() async throws {
    let clock = AutomaticReadClock()
    let (_, model, server, sync, connection) = try await environment(now: { clock.date })
    defer { connection.finish() }
    sync.updateScene(UUID(), active: true, studying: false)
    connection.yield(true)
    let gate = StudyTaskGate()
    await server.configureReads(gate: gate)
    clock.advance(1801)
    let read = Task { await sync.wake() }
    await gate.waitForEntry()
    let disconnect = Task { await model.disconnect() }
    await gate.waitForCancellation()
    await gate.resume()
    await disconnect.value
    await read.value
    #expect(model.snapshot == nil)
    #expect(await server.writes == 0)
  }
  @Test func aClockRollbackTriggersOneReadWithoutAnImmediateReadLoop() async throws {
    let clock = AutomaticReadClock()
    let (_, model, server, sync, connection) = try await environment(now: { clock.date })
    defer { connection.finish() }
    sync.updateScene(UUID(), active: true, studying: false)
    connection.yield(true)
    let reads = await server.fullReads
    clock.advance(-3600)
    await sync.wake()
    await sync.wake()
    #expect(await server.fullReads == reads + 1)
    #expect(await server.writes == 0)
    #expect(model.snapshot?.savedAt == clock.date)
  }

  @Test func aNewWorkerFindsTheDurablePostStudyReadRequest() async throws {
    let clock = AutomaticReadClock()
    let (store, model, server, sync, connection) = try await environment(now: { clock.date })
    defer { connection.finish() }
    connection.yield(true)
    try await completeReview(store)
    await sync.wake()
    #expect(try await store.accountState(accountID: account)?.catalogRefreshID != nil)
    let reads = await server.fullReads
    await server.unlockLesson()
    clock.advance(61)
    let paths = AsyncStream<Bool> {
      $0.yield(true)
      $0.finish()
    }
    let resumed = StudyAutomaticSync(model: model, paths: paths, now: { clock.date })
    resumed.start()
    resumed.updateScene(UUID(), active: true, studying: false)
    await resumed.wake()
    #expect(await server.fullReads == reads + 1)
    #expect(await server.writes == 1)
    #expect(model.snapshot?.subjects.contains { $0.id == 900 } == true)
    #expect(try await store.accountState(accountID: account)?.catalogRefreshID == nil)
  }

}
