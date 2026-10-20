import Foundation
import StudyCore
import Testing

@testable import StudyPersistence

struct StudyMistakeStoreTests {
  private let account = "mistake-account"
  @Test func maximumMergeOnlyTouchesExistingSupportedHistoryAndNeverCreatesUploads() async throws {
    let store = try await populated()
    let before = try #require(try await store.accountState(accountID: account))
    let assignments = try await store.assignments(accountID: account)
    #expect(try await store.mergeMistakes([1: 100, 2: 200, 3: 300, 999: 999], accountID: account))
    #expect(try await !store.mergeMistakes([1: 100, 999: 1000], accountID: account))
    #expect(try await !store.mergeMistakes([1: 99], accountID: account))
    let state = try #require(try await store.accountState(accountID: account))
    #expect(state.progress.count == before.progress.count && state.progress[0].lastMistakeAt == 100)
    #expect(state.progress[1].lastMistakeAt == nil)
    #expect(state.progress[0].lastMistakeLocalTime == before.progress[0].lastMistakeLocalTime)
    #expect(state.progress[0].legacyRevision == before.progress[0].legacyRevision)
    #expect(try await store.assignments(accountID: account) == assignments)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    #expect(try await store.materials(accountID: account).isEmpty)
    #expect(try await store.session(accountID: account) == nil)
    #expect(try await store.mistakeState(accountID: account).values == [1: 100])
    #expect(try await store.mistakeState(accountID: "mistake-other").values.isEmpty)
  }
  @Test func historySurvivesReopenAndFutureTimestampsAreNotClamped() async throws {
    let folder = URL.temporaryDirectory.appending(path: "mistake-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    do {
      let store = try await populated(at: url)
      #expect(try await store.mergeMistakes([1: Int64.max], accountID: account))
    }
    let store = try await StudyStore.open(at: url)
    #expect(try await store.mistakeState(accountID: account).values == [1: Int64.max])
    #expect(try await !store.mergeMistakes([1: 1], accountID: account))
  }
  @Test func concurrentMergesCancellationAndInvalidAccountsKeepTheMaximum() async throws {
    let store = try await populated()
    async let first = store.mergeMistakes([1: 200], accountID: account)
    async let second = store.mergeMistakes([1: 100], accountID: account)
    _ = try await (first, second)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await store.mergeMistakes([1: 999], accountID: account)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    for id in ["", "missing"] {
      await #expect(throws: StudyStoreError.self) {
        try await store.mergeMistakes([1: 999], accountID: id)
      }
    }
    await #expect(throws: StudyMistakeError.self) {
      try await store.mergeMistakes([1: -1], accountID: account)
    }
    #expect(try await store.mistakeState(accountID: account).values == [1: 200])
  }
  @Test func legacyBindingRequiresActivatedExactReceiptAndMatchingOriginalUsername() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let source = fixture(username: "original")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let context = StudyLegacyMistakeContext(
      locale: Locale(identifier: "en_US_POSIX"), calendar: calendar)
    let binding = StudyLegacyMistakeBinding(
      accountID: account, sourceID: "verified-source",
      sourceDigest: try source.importDigest, username: "original", context: context)
    let identity = WaniKaniAccount(
      id: account, username: "original", level: 1, onVacation: false, profile: source.profile)
    let handoff = try await store.prepareLegacyHandoff(
      source, sourceID: "verified-source", accountID: account,
      credentialID: "fixture", identity: identity, preferences: .init())
    #expect(
      try await store.mistakeState(accountID: account, legacyBinding: binding).legacyBinding == nil)
    _ = try await store.activateLegacyHandoff(handoff)
    let bound = try await store.mistakeState(accountID: account, legacyBinding: binding)
    #expect(bound.legacyBinding == binding && bound.values[1] != nil)
    #expect(try await store.mistakeState(accountID: account).values.isEmpty)
    let wrongDigest = StudyLegacyMistakeBinding(
      accountID: account, sourceID: "verified-source",
      sourceDigest: "different", username: "original", context: context)
    #expect(
      try await store.mistakeState(accountID: account, legacyBinding: wrongDigest).legacyBinding
        == nil)
    var renamed = source.profile
    renamed.username = "renamed"
    try await store.applyVerifiedAccount(
      .init(id: account, username: "renamed", level: 1, onVacation: false, profile: renamed),
      accountID: account)
    #expect(
      try await store.mistakeState(accountID: account, legacyBinding: binding).legacyBinding == nil)
    #expect(try await store.mistakeState(accountID: account).values.isEmpty)
  }
  private func populated(at url: URL? = nil) async throws -> StudyStore {
    let store = try await StudyStore.open(at: url ?? URL(filePath: "/unused"), inMemory: url == nil)
    for (id, name) in [(account, "original"), ("mistake-other", "other")] {
      _ = try await store.importLegacyAccount(
        fixture(username: name), sourceID: "source",
        verifiedAccountID: id, verifiedUsername: name, credentialID: id)
    }
    return store
  }
  private func fixture(username: String) -> LegacyStudyExport {
    var source = LegacyStudyExport(schemaVersion: 15, profile: .init(username: username))
    source.profile.level = 1
    source.profile.maxLevelGranted = 3
    for id in Int64(1)...2 {
      var subject = CatalogSubject(id: id, kind: .kanji)
      subject.level = 1
      source.subjects.append(subject)
      var assignment = CatalogAssignment(id: id + 100, subjectID: id, kind: .kanji)
      assignment.srsStage = 3
      assignment.startedAt = 1
      assignment.availableAt = 1
      source.assignments.append(assignment)
    }
    source.progress = [1, 3].map {
      .init(
        subjectID: $0, level: 1, srsStage: 3, kind: .kanji,
        lastMistakeLocalTime: $0 == 1 ? "2026-10-20 12:00:00" : nil, legacyRevision: 17)
    }
    return source
  }
}
