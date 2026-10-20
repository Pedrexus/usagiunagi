import Foundation
import StudyCore
import SwiftData
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
    let handoff = try await prepare(in: store)
    #expect(try await store.mistakeState(accountID: account).legacyBinding == nil)
    #expect(try await store.mistakeState(accountID: account).values.isEmpty)
    _ = try await store.activateLegacyHandoff(handoff)
    let bound = try await store.mistakeState(accountID: account)
    let binding = try #require(bound.legacyBinding)
    #expect(binding.accountID == account && binding.sourceID == "verified-source")
    #expect(binding.sourceDigest == (try source.importDigest) && binding.username == "original")
    #expect(binding.context == context && !bound.needsLegacyImport)
    #expect(
      bound.values
        == StudyLegacyMistakes(originals: ["1": "2026-10-20 12:00:00"], context: context).values)
    try await store.setMistakeTestReceiptDigest("different", receiptID: handoff.receiptID)
    await #expect(throws: StudyStoreError.self) { try await store.mistakeState(accountID: account) }
    try await store.setMistakeTestReceiptDigest(
      try source.importDigest, receiptID: handoff.receiptID)
    #expect(try await store.mistakeState(accountID: account).legacyBinding == binding)
    var renamed = source.profile
    renamed.username = "renamed"
    try await store.applyVerifiedAccount(
      .init(id: account, username: "renamed", level: 1, onVacation: false, profile: renamed),
      accountID: account)
    #expect(try await store.mistakeState(accountID: account).legacyBinding == nil)
    #expect(try await store.mistakeState(accountID: account).values.isEmpty)
  }
  @Test func verifiedBindingAndInterpretationSurviveRepreparationAndReopen() async throws {
    let folder = URL.temporaryDirectory.appending(path: "mistake-binding-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let saved: StudyLegacyHandoff
    let expected: [Int64: Int64]
    do {
      let store = try await StudyStore.open(at: url)
      let prepared = try await prepare(in: store)
      // Resuming before activation must preserve the first captured civil-time interpretation.
      let resumed = try await prepare(
        in: store,
        interpretation: .init(
          locale: .init(identifier: "ja_JP"), calendar: .init(identifier: .buddhist)))
      #expect(resumed == prepared)
      saved = try await store.activateLegacyHandoff(resumed)
      let state = try await store.mistakeState(accountID: account)
      expected = state.values
      #expect(!expected.isEmpty && state.legacyBinding?.context == context)
    }
    let reopened = try await StudyStore.open(at: url)
    #expect(try await reopened.legacyHandoff(sourceID: "verified-source") == saved)
    #expect(try await prepare(in: reopened) == saved)
    let restored = try await reopened.mistakeState(accountID: account)
    #expect(restored.values == expected && restored.legacyBinding?.context == context)
    #expect(!restored.needsLegacyImport)
  }
  @Test(arguments: ["profile", "identity-only", "download"])
  func verifiedRenameRevokesDurablyAndRenameBackCannotRestoreLegacyOwnership(_ path: String)
    async throws
  {
    let folder = URL.temporaryDirectory.appending(path: "mistake-revocation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let source = fixture(username: "original")
    let binding: StudyLegacyMistakeBinding
    do {
      let store = try await StudyStore.open(at: url)
      let handoff = try await prepare(in: store)
      _ = try await store.activateLegacyHandoff(handoff)
      binding = try #require(try await store.mistakeState(accountID: account).legacyBinding)
      try await store.mergeMistakes([1: 2_000_000_000], accountID: account)
      var renamed = source.profile
      renamed.username = "renamed"
      if path == "download" {
        let baseline = try await store.refreshBaseline(accountID: account)
        _ = try await store.applyDownload(
          .init(
            accountID: account, profile: renamed, subjects: source.subjects,
            assignments: source.assignments),
          credentialID: "fixture", baseline: baseline)
      } else {
        try await store.applyVerifiedAccount(
          .init(
            id: account, username: "renamed", level: 1, onVacation: false,
            profile: path == "profile" ? renamed : nil), accountID: account)
      }
      #expect(
        try await store.legacyHandoff(sourceID: "verified-source")?.mistakeAccess
          == .revoked(binding))
      #expect(try await store.mistakeState(accountID: account).legacyBinding == nil)
      try await store.applyVerifiedAccount(
        .init(
          id: account, username: "original", level: 1, onVacation: false, profile: source.profile),
        accountID: account)
      #expect(try await prepare(in: store).mistakeAccess == .revoked(binding))
    }
    let reopened = try await StudyStore.open(at: url)
    #expect(try await prepare(in: reopened).mistakeAccess == .revoked(binding))
    let state = try await reopened.mistakeState(accountID: account)
    #expect(state.username == "original" && state.legacyBinding == nil && !state.needsLegacyImport)
    #expect(state.values == [1: 2_000_000_000])
    #expect(try await reopened.pendingReviews(accountID: account).isEmpty)
  }
  @Test func historicalReceiptWithoutBindingCannotAcquireOwnershipOnReopenOrPreparation()
    async throws
  {
    let folder = URL.temporaryDirectory.appending(path: "mistake-unverified-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let historical: StudyLegacyHandoff
    do {
      let store = try await StudyStore.open(at: url)
      let current = try await store.activateLegacyHandoff(try await prepare(in: store))
      var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
      object.removeValue(forKey: "mistakeAccess")
      historical = try JSONDecoder().decode(
        StudyLegacyHandoff.self, from: JSONSerialization.data(withJSONObject: object))
      #expect(historical.activated && historical.mistakeAccess == nil)
      try await store.replaceMistakeTestHandoff(historical)
    }
    let reopened = try await StudyStore.open(at: url)
    #expect(try await prepare(in: reopened) == historical)
    let state = try await reopened.mistakeState(accountID: account)
    #expect(state.legacyBinding == nil && state.needsLegacyImport && state.values.isEmpty)
    let accountState = try #require(try await reopened.accountState(accountID: account))
    #expect(accountState.progress.first?.lastMistakeLocalTime == "2026-10-20 12:00:00")
  }
  private var context: StudyLegacyMistakeContext {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return .init(locale: Locale(identifier: "en_US_POSIX"), calendar: calendar)
  }
  private func prepare(in store: StudyStore, interpretation: StudyLegacyMistakeContext? = nil)
    async throws -> StudyLegacyHandoff
  {
    let source = fixture(username: "original")
    return try await store.prepareLegacyHandoff(
      source, sourceID: "verified-source", accountID: account, credentialID: "fixture",
      identity: .init(
        id: account, username: "original", level: 1, onVacation: false, profile: source.profile),
      preferences: .init(), mistakeContext: interpretation ?? context)
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

extension StudyStore {
  fileprivate func setMistakeTestReceiptDigest(_ digest: String, receiptID: String) throws {
    try transaction {
      let row = try #require(
        try modelContext.fetch(
          FetchDescriptor<ImportReceipt>(predicate: #Predicate { $0.sourceID == receiptID })
        ).first)
      row.digest = digest
    }
  }
  fileprivate func replaceMistakeTestHandoff(_ handoff: StudyLegacyHandoff) throws {
    let receiptID = handoff.receiptID
    try transaction {
      let row = try #require(
        try modelContext.fetch(
          FetchDescriptor<ImportReceipt>(predicate: #Predicate { $0.sourceID == receiptID })
        ).first)
      row.handoff = handoff
    }
  }
}
