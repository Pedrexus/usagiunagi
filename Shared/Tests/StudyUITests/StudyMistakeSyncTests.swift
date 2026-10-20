import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence
@testable import StudyUI

@MainActor private final class MistakeCloud: StudyMistakeCloudStore {
  var available = true
  var canSynchronize = true
  var failWrites = false
  var values: [String: Data] = [:]
  var reads: [String] = []
  var writes: [String] = []
  var onRead: (@MainActor (String) -> Void)?
  private var continuation: AsyncStream<StudyMistakeCloudEvent>.Continuation?
  func changes() -> AsyncStream<StudyMistakeCloudEvent> {
    let pair = AsyncStream<StudyMistakeCloudEvent>.makeStream()
    continuation = pair.continuation
    return pair.stream
  }
  func synchronize() -> Bool {
    #expect(continuation != nil)
    return canSynchronize
  }
  func data(forKey key: String) -> Data? {
    reads.append(key)
    let value = values[key]
    onRead?(key)
    return value
  }
  func set(_ data: Data, forKey key: String) throws {
    if failWrites { throw StudyMistakeError.quotaExceeded }
    writes.append(key)
    values[key] = data
    emit(.server, keys: [key])
  }
  func emit(_ reason: StudyMistakeCloudEvent.Reason, keys: Set<String>? = nil) {
    continuation?.yield(.init(reason: reason, keys: keys))
  }
}

@MainActor struct StudyMistakeSyncTests {
  private let account = "fixture-user-id"
  private var key: String { get throws { try StudyMistakeArchive.key(accountID: account) } }

  @Test func initialCatchUpMergesUnknownHintsWithoutUploadsAndSelfWritesSettle() async throws {
    let (model, store) = try await fixture()
    try await store.mergeMistakes([1: 100], accountID: account)
    let cloud = MistakeCloud()
    cloud.values[try key] = try StudyMistakeArchive(accountID: account, values: [1: 90, 999: 500])
      .encoded()
    cloud.values["testtsurukame-mistakes"] = Data("unattributed source".utf8)
    let sync = StudyMistakeSync(model: model, cloud: cloud)
    defer { sync.stop() }
    await sync.wake()
    await Task.yield()
    await sync.wake()
    let merged = try StudyMistakeArchive(data: #require(cloud.values[try key]), accountID: account)
    #expect(merged.values == [1: 100, 999: 500])
    #expect(cloud.writes == [try key] && cloud.reads.count < 30)
    #expect(!cloud.reads.contains("testtsurukame-mistakes"))
    #expect(sync.notice?.contains("verified import") == true)
    #expect(try await store.mistakeState(accountID: account).values == [1: 100])
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    #expect(try await store.session(accountID: account) == nil)
  }
  @Test func malformedWrongAccountAndFutureCloudDocumentsStayUntouched() async throws {
    for data in [
      Data("broken".utf8), try StudyMistakeArchive(accountID: "other", values: [1: 999]).encoded(),
      try PropertyListSerialization.data(
        fromPropertyList: ["formatVersion": 2, "accountID": account, "entries": []],
        format: .binary, options: 0),
      try PropertyListSerialization.data(
        fromPropertyList: [
          "formatVersion": 1, "accountID": account, "entries": [], "futureField": "kept",
        ],
        format: .binary, options: 0),
      try PropertyListSerialization.data(
        fromPropertyList: [
          "formatVersion": 1, "accountID": account,
          "entries": [["subjectID": 1, "timestamp": 999, "futureField": "kept"]],
        ],
        format: .binary, options: 0),
    ] {
      let (model, store) = try await fixture()
      let cloud = MistakeCloud()
      cloud.values[try key] = data
      let sync = StudyMistakeSync(model: model, cloud: cloud)
      await sync.wake()
      let retained = cloud.values[try key]
      #expect(cloud.writes.isEmpty && retained == data && sync.notice != nil)
      #expect(try await store.mistakeState(accountID: account).values.isEmpty)
      sync.stop()
    }
  }
  @Test func entitlementQuotaAndAppleAccountEventsPreserveLocalHistory() async throws {
    let (model, store) = try await fixture()
    try await store.mergeMistakes([1: 100], accountID: account)
    let cloud = MistakeCloud()
    cloud.canSynchronize = false
    let sync = StudyMistakeSync(model: model, cloud: cloud)
    defer { sync.stop() }
    await sync.wake()
    #expect(cloud.reads.isEmpty && cloud.writes.isEmpty && sync.notice != nil)
    cloud.canSynchronize = true
    cloud.failWrites = true
    await sync.wake()
    #expect(cloud.writes.isEmpty && sync.notice?.contains("full") == true)
    cloud.failWrites = false
    cloud.available = false
    cloud.emit(.account)
    await Task.yield()
    await sync.wake()
    #expect(cloud.writes.isEmpty)
    cloud.available = true
    cloud.emit(.initial, keys: [])
    await Task.yield()
    await sync.wake()
    #expect(cloud.writes == [try key])
    cloud.emit(.quota)
    await Task.yield()
    #expect(try await store.mistakeState(accountID: account).values == [1: 100])
    #expect(sync.notice != nil)
  }
  @Test func changedAccountDuringAReadCannotPublishAndLogoutStopsTheOldOwner() async throws {
    let (model, store) = try await fixture()
    let cloud = MistakeCloud()
    cloud.values[try key] = try StudyMistakeArchive(accountID: account, values: [1: 999]).encoded()
    cloud.onRead = { _ in model.loadPreview() }
    let sync = StudyMistakeSync(model: model, cloud: cloud)
    defer { sync.stop() }
    await sync.wake()
    #expect(cloud.writes.isEmpty)
    #expect(try await store.mistakeState(accountID: account).values.isEmpty)
    await model.disconnect()
    let reads = cloud.reads.count
    cloud.emit(.server, keys: [try key])
    await Task.yield()
    await sync.wake()
    #expect(cloud.reads.count == reads && cloud.writes.isEmpty)
  }
  @Test func lateRemoteUpdateAndConcurrentLocalCommitKeepBothMaximums() async throws {
    let (model, store) = try await fixture()
    let cloud = MistakeCloud()
    cloud.values[try key] = try StudyMistakeArchive(accountID: account, values: [1: 100, 999: 1])
      .encoded()
    let changed = try StudyMistakeArchive(accountID: account, values: [1: 200, 888: 2]).encoded()
    var firstRead = true
    cloud.onRead = { [weak cloud] key in
      if firstRead {
        firstRead = false
        cloud?.values[key] = changed
      }
    }
    let sync = StudyMistakeSync(model: model, cloud: cloud)
    defer { sync.stop() }
    async let local = store.mergeMistakes([1: 150], accountID: account)
    await sync.wake()
    _ = try await local
    await sync.wake()
    let result = try StudyMistakeArchive(data: #require(cloud.values[try key]), accountID: account)
    #expect(result.values == [1: 200, 888: 2, 999: 1])
    #expect(try await store.mistakeState(accountID: account).values == [1: 200])
  }
  @Test func onlyAnExplicitVerifiedBindingCanUseLegacyHintsAndRenameOrReuseStopsIt() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var source = LegacyStudyExport(schemaVersion: 15, profile: .init(username: "original"))
    source.profile.level = 1
    source.profile.maxLevelGranted = 3
    var subject = CatalogSubject(id: 1, kind: .kanji)
    subject.level = 1
    source.subjects = [subject]
    source.progress = [
      .init(
        subjectID: 1, level: 1, srsStage: 3, kind: .kanji,
        lastMistakeLocalTime: "2026-10-20 12:00:00", legacyRevision: 0)
    ]
    let handoff = try await store.prepareLegacyHandoff(
      source, sourceID: "verified-source", accountID: account,
      credentialID: StudyAppModel.credentialID("fixture"),
      identity: .init(
        id: account, username: "original",
        level: 1, onVacation: false, profile: source.profile), preferences: .init())
    _ = try await store.activateLegacyHandoff(handoff)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let context = StudyLegacyMistakeContext(
      locale: Locale(identifier: "en_US_POSIX"), calendar: calendar)
    let binding = StudyLegacyMistakeBinding(
      accountID: account, sourceID: "verified-source",
      sourceDigest: try source.importDigest, username: "original", context: context)
    let model = StudyAppModel(credentials: MemoryCredentials("fixture"), openStore: { store })
    await model.restore()
    let cloud = MistakeCloud()
    let raw = ["1": "2026-10-20 12:00:00", "unresolved-kind": "kept verbatim"]
    cloud.values[binding.key] = try JSONEncoder().encode(raw)
    let sync = StudyMistakeSync(model: model, cloud: cloud, legacyBinding: { _ in binding })
    await sync.wake()
    #expect(cloud.reads.contains(binding.key))
    #expect(sync.notice?.contains("kept unchanged") == true)
    #expect(
      try JSONDecoder().decode([String: String].self, from: #require(cloud.values[binding.key]))
        == raw)
    let previous = try #require(try await store.mistakeState(accountID: account).values[1])
    try await store.mergeMistakes([1: previous + 1], accountID: account)
    await sync.wake()
    let compatible = try JSONDecoder().decode(
      [String: String].self, from: #require(cloud.values[binding.key]))
    #expect(
      compatible["1"] == "2026-10-20 12:00:01" && compatible["unresolved-kind"] == "kept verbatim")
    var renamed = source.profile
    renamed.username = "renamed"
    try await store.applyVerifiedAccount(
      .init(
        id: account, username: "renamed", level: 1,
        onVacation: false, profile: renamed), accountID: account)
    await model.reloadSavedSnapshot()
    let legacyReads = cloud.reads.filter { $0 == binding.key }.count
    cloud.values[binding.key] = Data("unattributed after rename".utf8)
    await sync.wake()
    #expect(cloud.reads.filter { $0 == binding.key }.count == legacyReads)
    #expect(try key == StudyMistakeArchive.key(accountID: account))
    sync.stop()
    _ = try await store.importLegacyAccount(
      source, sourceID: "another-source", verifiedAccountID: "reused-id",
      verifiedUsername: "original", credentialID: StudyAppModel.credentialID("other"))
    let other = StudyAppModel(credentials: MemoryCredentials("other"), openStore: { store })
    await other.restore()
    let reused = StudyMistakeSync(model: other, cloud: cloud, legacyBinding: { _ in binding })
    defer { reused.stop() }
    await reused.wake()
    #expect(cloud.reads.filter { $0 == binding.key }.count == legacyReads)
    #expect(cloud.values[binding.key] == Data("unattributed after rename".utf8))
  }
  @Test func cloudNotificationReasonsAreTypedWithoutOpeningApplesStore() {

    let reasons: [(Int, StudyMistakeCloudEvent.Reason)] = [
      (NSUbiquitousKeyValueStoreServerChange, .server),
      (NSUbiquitousKeyValueStoreInitialSyncChange, .initial),
      (NSUbiquitousKeyValueStoreQuotaViolationChange, .quota),
      (NSUbiquitousKeyValueStoreAccountChange, .account),
      (99, .unknown),
    ]
    for (value, expected) in reasons {
      let event = StudyMistakeCloudEvent(
        notification: .init(
          name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
          userInfo: [
            NSUbiquitousKeyValueStoreChangeReasonKey: value,
            NSUbiquitousKeyValueStoreChangedKeysKey: ["key"],
          ]))
      #expect(event.reason == expected && event.keys == ["key"])
    }
  }
  private func fixture() async throws -> (StudyAppModel, StudyStore) {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let credentials = MemoryCredentials("fixture")
    _ = try await store.refresh(
      credentialID: StudyAppModel.credentialID("fixture"), token: "fixture",
      client: WaniKaniClient(transport: DownloadFixture.response))
    let model = StudyAppModel(
      credentials: credentials, client: WaniKaniClient(transport: DownloadFixture.response),
      openStore: { store })
    await model.restore()
    #expect(model.snapshot?.accountID == account)
    return (model, store)
  }
}
