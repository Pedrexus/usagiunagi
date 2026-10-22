import Foundation
import Observation
import StudyCore
import Testing

@testable import StudyPersistence
@testable import Tsurukame

actor ServiceStoreOpening {
  let store: StudyStore
  let gate: StudyTaskGate?
  let failFirst: Bool
  private(set) var calls = 0
  init(_ store: StudyStore, gate: StudyTaskGate? = nil, failFirst: Bool = false) {
    self.store = store
    self.gate = gate
    self.failFirst = failFirst
  }
  func open() async throws -> StudyStore {
    calls += 1
    if calls == 1, failFirst { throw CocoaError(.fileReadNoPermission) }
    if calls == 1, let gate { await gate.pause() }
    return store
  }
}
@MainActor private final class ServiceNotificationPreferences: StudyNotificationPreferences {
  func value(for option: NotificationPreference) -> Bool { false }
  func set(_ value: Bool, for option: NotificationPreference) {}
}
@MainActor private final class ServiceNotificationClient {
  var requests = 0
  var statusGate: StudyTaskGate?
  var client: StudyNotificationClient {
    .init(
      status: {
        if let gate = self.statusGate {
          self.statusGate = nil
          await gate.pause()
        }
        return .denied
      }, request: { self.requests += 1 }, pending: { [] }, remove: { _ in },
      badge: { _ in }, add: { _ in })
  }
}
@MainActor @Observable private final class ServiceEvents {
  var values: [StudyServiceSnapshot] = []
  var packets: [StudyCompanionSnapshot] = []
  func receive(_ value: StudyServiceSnapshot) { values.append(value) }
  func next(where predicate: (StudyServiceSnapshot) -> Bool) async -> StudyServiceSnapshot {
    for await values in Observations({ self.values }) {
      if let value = values.last(where: predicate) { return value }
    }
    preconditionFailure("Service observation ended before the expected projection")
  }
}
private actor ServiceReadTransport {
  let gate: StudyTaskGate
  var held = false
  init(_ gate: StudyTaskGate) { self.gate = gate }
  func response(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    if request.url?.lastPathComponent == "subjects", !held {
      held = true
      await gate.pause()
    }
    return try DownloadFixture.response(request)
  }
}
@MainActor @Suite(.timeLimit(.minutes(1))) struct NativeServiceOwnerTests {
  private let account = "fixture-user-id"
  @MainActor private final class Environment {
    let domain = "usagi-services-" + UUID().uuidString
    let store: StudyStore
    let model: StudyAppModel
    let settings: StudyLessonSettings
    let notices: StudyNotifications
    let client = ServiceNotificationClient()
    let events = ServiceEvents()
    let companion: StudyCompanionDelivery
    deinit { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
    init(
      reader: (any WaniKaniService)? = nil, failFirstOpen: Bool = false,
      kanaAssignment: Bool = false
    ) async throws {
      let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
      self.store = store
      let plain = WaniKaniClient(transport: DownloadFixture.response)
      let credential = StudyAppModel.credentialID("fixture")
      _ = try await store.synchronize(credentialID: credential, token: "fixture", client: plain)
      if kanaAssignment {
        var download = try await plain.download(token: "fixture")
        let subject = try #require(download.subjects.first { $0.isKanaOnlyVocabulary == true })
        var assignment = CatalogAssignment(id: 102, subjectID: subject.id, kind: .vocabulary)
        assignment.level = subject.level
        assignment.srsStage = 3
        assignment.startedAt = 1
        assignment.availableAt = 1
        assignment.isKanaOnlyVocabulary = true
        download.assignments.append(assignment)
        let baseline = try await store.refreshBaseline(accountID: "fixture-user-id")
        _ = try await store.applyDownload(download, credentialID: credential, baseline: baseline)
      }
      let opening = ServiceStoreOpening(store, failFirst: failFirstOpen)
      model = StudyAppModel(
        credentials: MemoryCredentials("fixture"), client: reader ?? plain,
        openStore: { try await opening.open() })
      settings = StudyLessonSettings(
        store: DefaultsStudyLessonPreferences(defaults: UserDefaults(suiteName: domain)!))
      notices = StudyNotifications(
        preferences: ServiceNotificationPreferences(), client: client.client)
      let events = events
      companion = StudyCompanionDelivery { packet, _ in
        events.packets.append(packet)
        return true
      }
      let companion = companion
      notices.didRead = {
        events.receive($0)
        companion.update($0)
      }
    }
    func start() { notices.observe(model: model, lessonSettings: settings) }
  }
  private func completeReview(_ store: StudyStore) async throws {
    let assignment = try #require(await store.assignments(accountID: account).first)
    var session = try StudySession(items: [assignment.sessionItem(id: 0, isLesson: false)], seed: 1)
    while let question = session.nextQuestion() {
      _ = try session.mark(.correct, for: question, now: Int64(Date().timeIntervalSince1970))
    }
    try await store.saveSession(session, accountID: account, expectedRevision: nil)
  }
  @Test func aSourceRestoresAndUpdatesTheCompanionWithoutAWindowOrPermissionRequest() async throws {
    let env = try await Environment()
    env.start()
    let initial = await env.events.next { $0.currentLevel != nil }
    #expect(initial.reviewDates.count == 1)
    #expect(env.events.values.allSatisfy { $0.currentLevel != nil })
    #expect(env.events.packets.last?.reviews == 1 && env.client.requests == 0)
    try await completeReview(env.store)
    _ = await env.events.next { $0.currentLevel != nil && $0.reviewDates.isEmpty }
    #expect(env.events.packets.last?.reviews == 0 && env.client.requests == 0)
  }
  @Test func aHeldNotificationDeliveryDoesNotDelayNewCompanionProgress() async throws {
    let env = try await Environment()
    let gate = StudyTaskGate()
    env.client.statusGate = gate
    env.start()
    _ = await env.events.next { !$0.reviewDates.isEmpty }
    await gate.waitForEntry()
    try await completeReview(env.store)
    _ = await env.events.next { $0.currentLevel != nil && $0.reviewDates.isEmpty }
    #expect(env.events.packets.last?.reviews == 0)
    await gate.resume()
    await env.notices.refresh()
  }
  @Test func storeChangesPublishEvenWhileTheAccountModelWaitsForANetworkRead() async throws {
    let gate = StudyTaskGate()
    let transport = ServiceReadTransport(gate)
    let reader = WaniKaniClient { try await transport.response($0) }
    let env = try await Environment(reader: reader)
    env.start()
    _ = await env.events.next { !$0.reviewDates.isEmpty }
    let read = Task { try await env.model.refresh(accountID: account) }
    await gate.waitForEntry()
    let revision = env.model.dataRevision
    try await completeReview(env.store)
    _ = await env.events.next { $0.currentLevel != nil && $0.reviewDates.isEmpty }
    #expect(env.model.isSyncing && env.model.dataRevision == revision)
    #expect(env.events.packets.last?.reviews == 0)
    await gate.resume()
    try await read.value
  }
  @Test func aFailedRestoreDoesNotInventLogoutAndRetryAttachesTheSource() async throws {
    let env = try await Environment(failFirstOpen: true)
    env.start()
    for await error in Observations({ env.model.error }) { if error != nil { break } }
    await env.notices.refresh()
    #expect(env.events.values.isEmpty && env.events.packets.isEmpty)
    await env.model.restore()
    _ = await env.events.next { $0.currentLevel != nil }
    #expect(env.model.error == nil && env.client.requests == 0)
  }
  @Test func logoutPublishesKnownEmptyProgressWithoutAView() async throws {
    let env = try await Environment()
    env.start()
    _ = await env.events.next { $0.currentLevel != nil }
    await env.model.disconnect()
    _ = await env.events.next { $0.currentLevel == nil }
    #expect(env.events.packets.last?.level == 0 && env.events.packets.last?.reviews == 0)
    #expect(env.client.requests == 0)
  }
  @Test func lessonVisibilityEditsRefreshTheSameAppOwnedProjection() async throws {
    let env = try await Environment(kanaAssignment: true)
    env.start()
    _ = await env.events.next { $0.reviewDates.count == 2 }
    let old = env.settings.value
    var new = old
    new.includeKanaVocabulary = false
    env.settings.applyChanges(from: old, to: new)
    _ = await env.events.next { $0.reviewDates.count == 1 }
    #expect(env.events.packets.last?.reviews == 1 && env.client.requests == 0)
  }
}
