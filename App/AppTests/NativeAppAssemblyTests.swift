import Foundation
import StudyCore
import StudyPersistence
import StudyUI
import Testing

@testable import Tsurukame

@MainActor private final class AssemblyCredentials: StudyCredentialStore {
  var token: String?
  init(_ token: String?) { self.token = token }
  func load() -> String? { token }
  func save(_ token: String) { self.token = token }
  func remove() { token = nil }
}
private actor AssemblyServer: WaniKaniService {
  var offline = false
  private(set) var writes = 0
  private var data: StudyDownload
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
  func account(token: String) throws -> WaniKaniAccount {
    if offline { throw URLError(.notConnectedToInternet) }
    return .init(
      id: data.accountID, username: data.profile.username, level: data.profile.level,
      onVacation: false, profile: data.profile)
  }
  func download(token: String) throws -> StudyDownload {
    if offline { throw URLError(.notConnectedToInternet) }
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
@MainActor private final class AssemblyNoticeSpy {
  var requests = 0
  var packets: [StudyCompanionSnapshot] = []
  var client: StudyNotificationClient {
    .init(
      status: { .denied }, request: { self.requests += 1 }, pending: { [] },
      remove: { _ in }, badge: { _ in }, add: { _ in })
  }
}
@MainActor @Suite(.timeLimit(.minutes(1))) struct NativeAppAssemblyTests {
  private let account = "assembly-fixture"
  private func environment(connected: Bool = true, pending: Bool = false) async throws -> (
    StudyAppAssembly, StudyStore, AssemblyServer, AssemblyNoticeSpy, String, URL
  ) {
    let domain = "usagi-native-assembly-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
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
  private func cleanup(_ domain: String, _ directory: URL) {
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
}
