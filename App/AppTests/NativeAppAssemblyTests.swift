import Foundation
import StudyCore
import StudyPersistence
import Testing

@testable import Tsurukame

@MainActor private final class AssemblyCredentials: StudyCredentialStore {
  var token: String?
  init(_ token: String?) { self.token = token }
  func load() -> String? { token }
  func save(_ token: String) { self.token = token }
  func remove() { token = nil }
}
actor AssemblyServer: WaniKaniService {
  var offline = false
  private(set) var writes = 0
  private var data: StudyDownload
  private var downloadGate: AssemblyGate?
  init() {
    var profile = StudyAccountProfile(username: "Assembly fixture")
    profile.level = 1
    profile.maxLevelGranted = 60
    var subject = CatalogSubject(id: 1, kind: .kanji)
    subject.level = 1
    subject.japanese = "一"
    subject.meanings = [.init("One", role: .primary)]
    subject.readings = [.init("いち", isPrimary: true, kind: .onyomi)]
    var assignment = CatalogAssignment(id: 101, subjectID: 1, kind: .kanji)
    assignment.level = 1
    assignment.srsStage = 5
    assignment.startedAt = 1
    assignment.availableAt = 1
    data = .init(
      accountID: "assembly-fixture", profile: profile, subjects: [subject],
      assignments: [assignment])
  }
  func setOffline() { offline = true }
  func pauseDownloads(using gate: AssemblyGate) { downloadGate = gate }
  func account(token: String) throws -> WaniKaniAccount {
    if offline { throw URLError(.notConnectedToInternet) }
    return .init(
      id: data.accountID, username: data.profile.username, level: data.profile.level,
      onVacation: false, profile: data.profile)
  }
  func download(token: String, subjects: [CatalogSubject], cursors: [String: String]) async throws
    -> StudyDownload
  {
    if offline { throw URLError(.notConnectedToInternet) }
    if let downloadGate { await downloadGate.pause() }
    return data
  }
  func assignment(subjectID: Int64, token: String) -> CatalogAssignment? {
    data.assignments.first { $0.subjectID == subjectID }
  }
  func material(subjectID: Int64, token: String) -> WaniKaniMaterial? { nil }
  func submit(_ answer: StudyReviewSubmission, token: String, now: Date) -> CatalogAssignment {
    writes += 1
    data.assignments[0].srsStage += 1
    data.assignments[0].availableAt = Int64(now.timeIntervalSince1970) + 3600
    return data.assignments[0]
  }
  func writeMaterial(_ value: StudyMaterial, serverID: Int64?, token: String) throws
    -> WaniKaniMaterial
  {
    throw WaniKaniClient.APIError.invalidPayload
  }
}
@MainActor final class AssemblyNoticeSpy {
  var requests = 0
  var packets: [StudyCompanionSnapshot] = []
  var client: StudyNotificationClient {
    .init(
      status: { .denied }, request: { self.requests += 1 }, pending: { [] },
      remove: { _ in }, badge: { _ in }, add: { _ in })
  }
}
@MainActor final class AssemblyGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private let entered = AsyncStream<Void>.makeStream()
  private let cancelled = AsyncStream<Void>.makeStream()
  func pause() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        entered.continuation.yield(())
      }
    } onCancel: {
      Task { @MainActor in self.cancelled.continuation.yield(()) }
    }
  }
  func waitForEntry() async {
    var iterator = entered.stream.makeAsyncIterator()
    _ = await iterator.next()
  }
  func waitForCancellation() async {
    var iterator = cancelled.stream.makeAsyncIterator()
    _ = await iterator.next()
  }
  func resume() {
    continuation?.resume()
    continuation = nil
    entered.continuation.finish()
    cancelled.continuation.finish()
  }
}
@MainActor @Suite(.timeLimit(.minutes(1))) struct NativeAppAssemblyTests {
  private let account = "assembly-fixture"
  func environment(connected: Bool = true, pending: Bool = false, persistent: Bool = false)
    async throws -> (
      StudyAppAssembly, StudyStore, AssemblyServer, AssemblyNoticeSpy, String, URL
    )
  {
    let domain = "usagi-native-assembly-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    let store = try await StudyStore.open(
      at: directory.appending(path: "study.store"), inMemory: !persistent)
    let server = AssemblyServer()
    _ = try await store.synchronize(
      credentialID: StudyCredentialID.forToken("assembly"), token: "assembly", client: server)
    if pending {
      let assignment = try #require(await store.assignments(accountID: account).first)
      var session = try StudySession(
        items: [assignment.sessionItem(id: 0, isLesson: false)], seed: 1)
      while let question = session.nextQuestion() {
        _ = try session.mark(.correct, for: question, now: 100)
      }
      try await store.saveSession(session, accountID: account, expectedRevision: nil)
    }
    let spy = AssemblyNoticeSpy()
    let model = StudyAppModel(
      credentials: AssemblyCredentials(connected ? "assembly" : nil), client: server,
      openStore: { store })
    let assembly = StudyAppAssembly(
      model: model,
      fonts: .init(
        catalog: .init(directory: directory.appending(path: "fonts")),
        preferences: DefaultsStudyFontPreferences(defaults: defaults)),
      audio: .init(
        downloads: .init(directory: directory.appending(path: "audio")),
        preferences: DefaultsStudyAudioPreferences(defaults: defaults)),
      defaults: defaults,
      notifications: .init(
        preferences: DefaultsStudyNotificationPreferences(defaults: defaults), client: spy.client),
      companion: .init { packet, _ in
        spy.packets.append(packet)
        return true
      },
      paths: AsyncStream {
        $0.yield(false)
        $0.finish()
      })
    return (assembly, store, server, spy, domain, directory)
  }
  func cleanup(_ domain: String, _ directory: URL) {
    UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
    try? FileManager.default.removeItem(at: directory)
  }
  @Test func sharedOwnerSendsConfirmedWorkReadsAndPublishesWithoutAWindow() async throws {
    let (assembly, store, server, spy, domain, directory) = try await environment(pending: true)
    defer { cleanup(domain, directory) }
    await assembly.model.restore()
    try await assembly.model.syncSavedWork(accountID: account)
    await assembly.notifications.refresh()
    #expect(await server.writes == 1)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    #expect(try await store.accountState(accountID: account)?.catalogRefreshID == nil)
    #expect(assembly.model.snapshot?.accountID == account)
    #expect(spy.packets.last?.reviews == 0 && spy.requests == 0)
  }
  @Test func disconnectedOwnerClearsCompanionWithoutSigningInOrPrompting() async throws {
    let (assembly, _, server, spy, domain, directory) = try await environment(connected: false)
    defer { cleanup(domain, directory) }
    await assembly.model.restore()
    await assembly.notifications.refresh()
    #expect(assembly.model.snapshot == nil && spy.packets.last?.level == 0)
    #expect(await server.writes == 0)
    #expect(spy.requests == 0)
  }
  @Test func failedReadKeepsTheAccountCacheAndPendingWork() async throws {
    let (assembly, store, server, spy, domain, directory) = try await environment(pending: true)
    defer { cleanup(domain, directory) }
    await server.setOffline()
    await assembly.model.restore()
    await #expect(throws: (any Error).self) {
      try await assembly.model.syncSavedWork(accountID: account)
    }
    await assembly.notifications.refresh()
    #expect(assembly.model.snapshot?.accountID == account)
    #expect(try await store.pendingReviews(accountID: account).count == 1)
    #expect(await server.writes == 0)
    #expect(spy.requests == 0 && spy.packets.last?.level == 1)
  }
  @Test func applicationPreparationIsSharedAcrossCancelledAndRemainingWindows() async throws {
    let (assembly, _, _, _, domain, directory) = try await environment()
    defer { cleanup(domain, directory) }
    let gate = AssemblyGate()
    var creations = 0
    let owner = StudyApplicationOwner {
      creations += 1
      await gate.pause()
      return assembly
    }
    let first = Task { await owner.prepare() }
    await gate.waitForEntry()
    let second = Task { await owner.prepare() }
    first.cancel()
    gate.resume()
    await second.value
    await first.value
    #expect(creations == 1 && owner.failure == nil)
    #expect(owner.services?.model === assembly.model)
  }
  @Test func failedApplicationPreparationRetainsAnExplicitRetry() async throws {
    let (assembly, _, _, _, domain, directory) = try await environment()
    defer { cleanup(domain, directory) }
    var attempts = 0
    let owner = StudyApplicationOwner {
      attempts += 1
      if attempts == 1 { throw CocoaError(.fileReadNoPermission) }
      return assembly
    }
    await owner.prepare()
    #expect(owner.services == nil && owner.failure != nil)
    await owner.prepare()
    #expect(attempts == 2 && owner.services?.model === assembly.model && owner.failure == nil)
  }
  @Test func nativeBackgroundTaskSendsConfirmedWork() async throws {
    let (assembly, store, server, _, domain, directory) = try await environment(pending: true)
    defer { cleanup(domain, directory) }
    let owner = StudyApplicationOwner { assembly }
    #expect(await owner.refreshInBackground())
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    #expect(await server.writes == 1)
  }
  @Test func expiredBackgroundTaskDoesNotCancelSharedPreparationOrStartLateWrites() async throws {
    let (assembly, store, server, _, domain, directory) = try await environment(pending: true)
    defer { cleanup(domain, directory) }
    let gate = AssemblyGate()
    let owner = StudyApplicationOwner {
      await gate.pause()
      return assembly
    }
    let background = Task { await owner.refreshInBackground() }
    await gate.waitForEntry()
    background.cancel()
    let foreground = Task { await owner.prepare() }
    gate.resume()
    await foreground.value
    #expect(await background.value == false)
    #expect(owner.services?.model === assembly.model)
    #expect(await server.writes == 0)
    #expect(try await store.pendingReviews(accountID: account).count == 1)
    #expect(await owner.refreshInBackground())
    #expect(await server.writes == 1)
  }

  @Test func nativeDiagnosticExportPreservesTheLiveCatalogAndProtectedOutbox() async throws {
    let (assembly, store, server, _, domain, directory) = try await environment(
      pending: true, persistent: true)
    defer { cleanup(domain, directory) }
    await assembly.model.restore()
    let source = directory.appending(path: "study.store")
    let before = try Data(contentsOf: source)
    let pending = try await store.pendingReviews(accountID: account)
    let bytes = try await StudyDiagnosticArchive(store: store, accountID: account).data()
    let exported = try PropertyListDecoder().decode(StudyDiagnosticDocument.self, from: bytes)
    #expect(try Data(contentsOf: source) == before)
    #expect(exported.accountID == account && exported.snapshots.first?.accountID == account)
    #expect(exported.catalog.first?.japanese == "一")
    #expect(exported.reviews == pending && exported.reviews.count == 1)
    #expect(exported.receiptScope == .verifiedAccountHandoffsOnly)
    #expect(try await store.pendingReviews(accountID: account) == pending)
    #expect(await server.writes == 0)
  }

}
