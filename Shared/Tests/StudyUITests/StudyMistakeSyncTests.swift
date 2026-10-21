import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence
@testable import StudyUI

@MainActor private final class MistakeICloud: StudyMistakeICloudStore {
  var observedEpoch = UUID()
  var synchronizations = 0
  var available = true
  var canSynchronize = true
  var failWrites = false
  var values: [String: Data] = [:]
  var reads: [String] = []
  var writes: [String] = []
  var onRead: (@MainActor (String) -> Void)?
  private var continuation: AsyncStream<StudyMistakeICloudEvent>.Continuation?
  func changes() -> AsyncStream<StudyMistakeICloudEvent> {
    let pair = AsyncStream<StudyMistakeICloudEvent>.makeStream()
    continuation = pair.continuation
    return pair.stream
  }
  func synchronize() -> Bool {
    #expect(continuation != nil)
    synchronizations += 1
    return canSynchronize
  }
  func data(forKey key: String) -> Data? {
    reads.append(key)
    let value = values[key]
    onRead?(key)
    return value
  }
  func set(_ data: Data, forKey key: String, observedEpoch: UUID) throws {
    guard self.observedEpoch == observedEpoch else { throw CancellationError() }
    if failWrites { throw StudyMistakeError.quotaExceeded }
    writes.append(key)
    values[key] = data
    emit(.server, keys: [key])
  }
  func emit(_ reason: StudyMistakeICloudEvent.Reason, keys: Set<String>? = nil) {
    observe(reason)
    continuation?.yield(.init(reason: reason, keys: keys))
  }
  func observe(_ reason: StudyMistakeICloudEvent.Reason) {
    if reason != .server { observedEpoch = UUID() }
  }
}

@MainActor struct StudyMistakeSyncTests {
  private let account = "fixture-user-id"
  private var key: String { get throws { try StudyMistakeArchive.key(accountID: account) } }

  @Test func initialCatchUpMergesUnknownHintsWithoutUploadsAndSelfWritesSettle() async throws {
    let (model, store) = try await fixture()
    try await store.mergeMistakes([1: 100], accountID: account)
    let iCloud = MistakeICloud()
    iCloud.values[try key] = try StudyMistakeArchive(accountID: account, values: [1: 90, 999: 500])
      .encoded()
    iCloud.values["testtsurukame-mistakes"] = Data("unattributed source".utf8)
    let sync = StudyMistakeSync(
      model: model, iCloud: iCloud, now: { Date(timeIntervalSince1970: 1_000) })
    defer { sync.stop() }
    await sync.wake()
    await Task.yield()
    await sync.wake()
    let merged = try StudyMistakeArchive(data: #require(iCloud.values[try key]), accountID: account)
    #expect(merged.values == [1: 100, 999: 500])
    #expect(iCloud.writes == [try key] && iCloud.reads.count < 30)
    #expect(!iCloud.reads.contains("testtsurukame-mistakes"))
    #expect(sync.notice == nil)
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
      let iCloud = MistakeICloud()
      iCloud.values[try key] = data
      let sync = StudyMistakeSync(
        model: model, iCloud: iCloud, now: { Date(timeIntervalSince1970: 1_000) })
      await sync.wake()
      let retained = iCloud.values[try key]
      #expect(iCloud.writes.isEmpty && retained == data && sync.notice != nil)
      #expect(try await store.mistakeState(accountID: account).values.isEmpty)
      sync.stop()
    }
  }
  @Test func entitlementQuotaAndAppleAccountEventsPreserveLocalHistory() async throws {
    let (model, store) = try await fixture()
    try await store.mergeMistakes([1: 100], accountID: account)
    let iCloud = MistakeICloud()
    iCloud.canSynchronize = false
    let sync = StudyMistakeSync(
      model: model, iCloud: iCloud, now: { Date(timeIntervalSince1970: 1_000) })
    defer { sync.stop() }
    await sync.wake()
    #expect(iCloud.reads.isEmpty && iCloud.writes.isEmpty && sync.notice != nil)
    iCloud.canSynchronize = true
    iCloud.failWrites = true
    await sync.wake()
    #expect(iCloud.writes.isEmpty && sync.notice?.contains("full") == true)
    iCloud.failWrites = false
    iCloud.available = false
    iCloud.emit(.account)
    try await requireNotice(sync, containing: "Apple account changed")
    await sync.wake()
    #expect(iCloud.writes.isEmpty)
    iCloud.available = true
    iCloud.emit(.initial, keys: [])
    try await requireNotice(sync, containing: "loading")
    await sync.wake()
    let cloudKey = try key
    #expect(iCloud.writes == [cloudKey])
    iCloud.emit(.quota)
    try await requireNotice(sync, containing: "full")
    #expect(try await store.mistakeState(accountID: account).values == [1: 100])
    #expect(sync.notice != nil)
  }
  @Test func changedAccountDuringAReadCannotPublishAndLogoutStopsTheOldOwner() async throws {
    let (model, store) = try await fixture()
    let iCloud = MistakeICloud()
    iCloud.values[try key] = try StudyMistakeArchive(accountID: account, values: [1: 999]).encoded()
    iCloud.onRead = { _ in model.loadPreview() }
    let sync = StudyMistakeSync(
      model: model, iCloud: iCloud, now: { Date(timeIntervalSince1970: 1_000) })
    defer { sync.stop() }
    await sync.wake()
    #expect(iCloud.writes.isEmpty)
    #expect(try await store.mistakeState(accountID: account).values.isEmpty)
    await model.disconnect()
    let reads = iCloud.reads.count
    iCloud.emit(.server, keys: [try key])
    await Task.yield()
    await sync.wake()
    #expect(iCloud.reads.count == reads && iCloud.writes.isEmpty)
  }
  @Test func lateRemoteUpdateAndConcurrentLocalCommitKeepBothMaximums() async throws {
    let (model, store) = try await fixture()
    let iCloud = MistakeICloud()
    iCloud.values[try key] = try StudyMistakeArchive(accountID: account, values: [1: 100, 999: 1])
      .encoded()
    let changed = try StudyMistakeArchive(accountID: account, values: [1: 200, 888: 2]).encoded()
    var firstRead = true
    iCloud.onRead = { [weak iCloud] key in
      if firstRead {
        firstRead = false
        iCloud?.values[key] = changed
      }
    }
    let sync = StudyMistakeSync(
      model: model, iCloud: iCloud, now: { Date(timeIntervalSince1970: 1_000) })
    defer { sync.stop() }
    async let local = store.mergeMistakes([1: 150], accountID: account)
    await sync.wake()
    _ = try await local
    await sync.wake()
    let result = try StudyMistakeArchive(data: #require(iCloud.values[try key]), accountID: account)
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
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let context = StudyLegacyMistakeContext(
      locale: Locale(identifier: "en_US_POSIX"), calendar: calendar)
    let handoff = try await store.prepareLegacyHandoff(
      source, sourceID: "verified-source", accountID: account,
      credentialID: StudyAppModel.credentialID("fixture"),
      identity: .init(
        id: account, username: "original",
        level: 1, onVacation: false, profile: source.profile), preferences: .init(),
      mistakeContext: context)
    _ = try await store.activateLegacyHandoff(handoff)
    let binding = try #require(try await store.mistakeState(accountID: account).legacyBinding)
    let model = StudyAppModel(credentials: MemoryCredentials("fixture"), openStore: { store })
    await model.restore()
    let iCloud = MistakeICloud()
    let raw = ["1": "2026-10-20 12:00:00", "unresolved-kind": "kept verbatim"]
    iCloud.values[binding.key] = try JSONEncoder().encode(raw)
    let sync = StudyMistakeSync(
      model: model, iCloud: iCloud, now: { Date(timeIntervalSince1970: 1_792_497_602) })
    await sync.wake()
    #expect(iCloud.reads.contains(binding.key))
    #expect(sync.notice?.contains("kept unchanged") == true)
    #expect(
      try JSONDecoder().decode([String: String].self, from: #require(iCloud.values[binding.key]))
        == raw)
    let previous = try #require(try await store.mistakeState(accountID: account).values[1])
    try await store.mergeMistakes([1: previous + 1], accountID: account)
    await sync.wake()
    let compatible = try JSONDecoder().decode(
      [String: String].self, from: #require(iCloud.values[binding.key]))
    #expect(
      compatible["1"] == "2026-10-20 12:00:01" && compatible["unresolved-kind"] == "kept verbatim")
    var renamed = source.profile
    renamed.username = "renamed"
    try await store.applyVerifiedAccount(
      .init(
        id: account, username: "renamed", level: 1,
        onVacation: false, profile: renamed), accountID: account)
    await model.reloadSavedSnapshot()
    let legacyReads = iCloud.reads.filter { $0 == binding.key }.count
    iCloud.values[binding.key] = Data("unattributed after rename".utf8)
    await sync.wake()
    #expect(iCloud.reads.filter { $0 == binding.key }.count == legacyReads)
    #expect(try key == StudyMistakeArchive.key(accountID: account))
    sync.stop()
    _ = try await store.importLegacyAccount(
      source, sourceID: "another-source", verifiedAccountID: "reused-id",
      verifiedUsername: "original", credentialID: StudyAppModel.credentialID("other"))
    let other = StudyAppModel(credentials: MemoryCredentials("other"), openStore: { store })
    await other.restore()
    let reused = StudyMistakeSync(
      model: other, iCloud: iCloud, now: { Date(timeIntervalSince1970: 1_792_497_602) })
    defer { reused.stop() }
    await reused.wake()
    #expect(iCloud.reads.filter { $0 == binding.key }.count == legacyReads)
    #expect(iCloud.values[binding.key] == Data("unattributed after rename".utf8))
  }
  @Test func cloudNotificationReasonsAreTypedWithoutOpeningApplesStore() {

    let reasons: [(Int, StudyMistakeICloudEvent.Reason)] = [
      (NSUbiquitousKeyValueStoreServerChange, .server),
      (NSUbiquitousKeyValueStoreInitialSyncChange, .initial),
      (NSUbiquitousKeyValueStoreQuotaViolationChange, .quota),
      (NSUbiquitousKeyValueStoreAccountChange, .account),
      (99, .unknown),
    ]
    for (value, expected) in reasons {
      let event = StudyMistakeICloudEvent(
        notification: .init(
          name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
          userInfo: [
            NSUbiquitousKeyValueStoreChangeReasonKey: value,
            NSUbiquitousKeyValueStoreChangedKeysKey: ["key"],
          ]))
      #expect(event.reason == expected && event.keys == ["key"])
    }
  }
  @Test func anObservedAccountChangeFencesAReadBeforeItsEventIsConsumed() async throws {
    let (model, store) = try await fixture()
    let iCloud = MistakeICloud()
    let remote = try StudyMistakeArchive(accountID: account, values: [1: 999]).encoded()
    iCloud.values[try key] = remote
    // Deliberately withhold the AsyncStream event: the synchronous observation is the fence.
    iCloud.onRead = { [weak iCloud] _ in iCloud?.observe(.account) }
    let sync = StudyMistakeSync(
      model: model, iCloud: iCloud, now: { Date(timeIntervalSince1970: 1_000) })
    defer { sync.stop() }
    await sync.wake()
    let cloudKey = try key
    #expect(iCloud.writes.isEmpty && iCloud.values[cloudKey] == remote)
    #expect(try await store.mistakeState(accountID: account).values.isEmpty)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    #expect(try await store.session(accountID: account) == nil)
    iCloud.onRead = nil
    iCloud.emit(.initial)
    try await requireNotice(sync, containing: "loading")
    await sync.wake()
    #expect(try await store.mistakeState(accountID: account).values == [1: 999])
  }
  @Test func notificationCallbackAdvancesEpochSynchronouslyAndCancellationRemovesIt() async {
    let center = NotificationCenter()
    let object = NSObject()
    let (stream, continuation) = AsyncStream<StudyMistakeICloudEvent>.makeStream()
    let observer = StudyMistakeICloudObserver(
      notifications: center, object: object, continuation: continuation)
    let initial = observer.epoch
    center.post(
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: object,
      userInfo: [NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreServerChange])
    #expect(observer.epoch == initial)
    center.post(
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: object,
      userInfo: [NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreAccountChange])
    #expect(observer.epoch != initial)
    let observed = observer.epoch
    observer.cancel(in: center)
    center.post(
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: object,
      userInfo: [
        NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreInitialSyncChange
      ])
    #expect(observer.epoch == observed)
    continuation.finish()
    var reasons: [StudyMistakeICloudEvent.Reason] = []
    for await event in stream { reasons.append(event.reason) }
    #expect(reasons == [.server, .account])
  }
  @Test func unavailableCacheRetriesOnceThenForegroundCanRecoverWithoutAnInitialEvent() async throws
  {
    let (model, store) = try await fixture()
    try await store.mergeMistakes([1: 100], accountID: account)
    let iCloud = MistakeICloud()
    iCloud.canSynchronize = false
    let sync = StudyMistakeSync(
      model: model, iCloud: iCloud, now: { Date(timeIntervalSince1970: 1_000) })
    defer { sync.stop() }
    await sync.wake()
    #expect(iCloud.synchronizations == 1 && iCloud.reads.isEmpty)
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while iCloud.synchronizations < 2 && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(iCloud.synchronizations == 2)
    try await Task.sleep(for: .milliseconds(2_200))
    #expect(iCloud.synchronizations == 2 && iCloud.reads.isEmpty && iCloud.writes.isEmpty)
    iCloud.canSynchronize = true
    await sync.wake()
    let cloudKey = try key
    #expect(iCloud.synchronizations == 3 && iCloud.writes == [cloudKey])
    #expect(try await store.mistakeState(accountID: account).values == [1: 100])
  }
  @Test func wireExpiryKeepsDurableHistoryAndUnknownRecentHints() async throws {
    let (model, store) = try await fixture()
    let now = Date(timeIntervalSince1970: 200_000)
    try await store.mergeMistakes([1: 100], accountID: account)
    let iCloud = MistakeICloud()
    iCloud.values[try key] = try StudyMistakeArchive(
      accountID: account, values: [1: 100, 888: 113_599, 999: 113_600, 777: Int64.max]
    ).encoded()
    let sync = StudyMistakeSync(model: model, iCloud: iCloud, now: { now })
    defer { sync.stop() }
    await sync.wake()
    let wire = try StudyMistakeArchive(data: #require(iCloud.values[try key]), accountID: account)
    #expect(wire.values == [999: 113_600, 777: Int64.max])
    #expect(try await store.mistakeState(accountID: account).values == [1: 100])
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    #expect(try await store.session(accountID: account) == nil)
  }
  private func requireNotice(_ sync: StudyMistakeSync, containing text: String) async throws {
    // Yielding does not drain AsyncStream: wait for the event's observable state transition.
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while sync.notice?.contains(text) != true && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    try #require(sync.notice?.contains(text) == true)
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
