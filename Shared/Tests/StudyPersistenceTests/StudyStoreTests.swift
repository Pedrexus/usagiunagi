import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

struct StudyStoreTests {
  private func folder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
  private func snapshot(account: String? = "account-a", level: Int = 1) -> StudySnapshot {
    StudySnapshot(
      accountID: account, username: "test", currentLevel: level, assignments: [], statistics: [],
      levels: [],
      subjects: [.init(id: 42, characters: "猫", meaning: "Cat", readings: ["ねこ"])])
  }
  private func session(subject: Int64 = 42, practice: Bool = false) throws -> StudySession {
    try StudySession(
      items: [
        .init(
          id: 0, subjectID: subject, assignmentID: subject + 100, srsStage: 3,
          availableAt: 10, hasReading: false)
      ], isPractice: practice, seed: 3)
  }
  private func complete(_ session: inout StudySession) throws {
    let next = session.nextQuestion()
    let question = try #require(next)
    _ = try session.mark(.correct, for: question, now: 100)
  }

  @Test func nativeCodableRoundTripIncludesFullSessionAndSubmission() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "study.store")
    let savedRevision: UUID
    do {
      let store = try await StudyStore.open(at: url)
      try await store.saveSnapshot(snapshot(), credentialID: "token-a")
      var state = try session()
      let first = try await store.saveSession(state, accountID: "account-a", expectedRevision: nil)
      try complete(&state)
      savedRevision = try await store.saveSession(
        state, accountID: "account-a", expectedRevision: first)
      let pending = try #require(await store.pendingReviews(accountID: "account-a").first)
      #expect(pending.submission == state.completedSubmissions.first)
      try await store.beginReviewAttempt(pending)
    }
    let reopened = try await StudyStore.open(at: url)
    let saved = try #require(await reopened.session(accountID: "account-a"))
    let pending = try #require(await reopened.pendingReviews(accountID: "account-a").first)
    #expect(saved.revision == savedRevision && saved.session.completedIDs == [0])
    #expect(
      pending.attempted && pending.submission.createdAt == 100
        && pending.originalItem.availableAt == 10)
    #expect(
      try await reopened.snapshot(credentialID: "token-a")?.subjects.first?.readings == ["ねこ"])
    await #expect(throws: StudyStoreError.self) { try await reopened.beginReviewAttempt(pending) }
  }

  @Test func acknowledgedAnswersAreNotReenqueuedByLaterSessionSaves() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    try await store.saveSnapshot(snapshot(), credentialID: "a")
    var state = try session()
    try complete(&state)
    let revision = try await store.saveSession(state, accountID: "account-a", expectedRevision: nil)
    let review = try #require(await store.pendingReviews(accountID: "account-a").first)
    try await store.beginReviewAttempt(review)
    try await store.acknowledgeReview(review)
    try await store.saveSession(state, accountID: "account-a", expectedRevision: revision)
    #expect(try await store.pendingReviews(accountID: "account-a").isEmpty)
  }

  @Test func oldAcknowledgementCannotRemoveNextReviewForSameSubject() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "study.store")
    let old: SavedReview
    let expected: [SavedReview]
    do {
      let store = try await StudyStore.open(at: url)
      try await store.saveSnapshot(snapshot(), credentialID: "a")
      var state = try session()
      try complete(&state)
      let revision = try await store.saveSession(
        state, accountID: "account-a", expectedRevision: nil)
      old = try #require(await store.pendingReviews(accountID: "account-a").first)
      try await store.beginReviewAttempt(old)
      try await store.acknowledgeReview(old)
      try await store.removeSession(accountID: "account-a", expectedRevision: revision)
      var next = try StudySession(
        items: [
          .init(id: 0, subjectID: 42, assignmentID: 142, srsStage: 4, hasReading: false),
          .init(id: 1, subjectID: 43, assignmentID: 143, srsStage: 2, hasReading: false),
        ], seed: 1)
      while let question = next.nextQuestion() {
        _ = try next.mark(.correct, for: question, now: 200)
      }
      try await store.saveSession(next, accountID: "account-a", expectedRevision: nil)
      for review in try await store.pendingReviews(accountID: "account-a") {
        try await store.beginReviewAttempt(review)
      }
      expected = try await store.pendingReviews(accountID: "account-a")
      #expect(expected.map(\.subjectID) == [42, 43])
      #expect(expected.first?.revision != old.revision)
      #expect(
        expected.allSatisfy { $0.submission.createdAt == 200 } && old.submission.createdAt == 100)
    }
    let reopened = try await StudyStore.open(at: url)
    #expect(try await reopened.pendingReviews(accountID: "account-a") == expected)
    try await reopened.acknowledgeReview(old)
    try await reopened.acknowledgeReview(old)
    #expect(try await reopened.pendingReviews(accountID: "account-a") == expected)
    let current = try #require(expected.first)
    try await reopened.acknowledgeReview(current)
    try await reopened.acknowledgeReview(current)
    #expect(
      try await reopened.pendingReviews(accountID: "account-a") == Array(expected.dropFirst()))
    let other = try #require(expected.last)
    try await reopened.acknowledgeReview(other)
    try await reopened.acknowledgeReview(other)
    #expect(try await reopened.pendingReviews(accountID: "account-a").isEmpty)
  }

  @Test func staleScenesAndDifferentAccountsCannotReplaceProgress() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    try await store.saveSnapshot(snapshot(), credentialID: "a")
    try await store.saveSnapshot(snapshot(account: "account-b"), credentialID: "b")
    var state = try session()
    let first = try await store.saveSession(state, accountID: "account-a", expectedRevision: nil)
    try complete(&state)
    let latest = try await store.saveSession(state, accountID: "account-a", expectedRevision: first)
    await #expect(throws: StudyStoreError.self) {
      try await store.saveSession(state, accountID: "account-a", expectedRevision: first)
    }
    await #expect(throws: StudyStoreError.self) {
      try await store.saveSession(state, accountID: "account-b", expectedRevision: latest)
    }
    #expect(try await store.session(accountID: "account-a")?.revision == latest)
    #expect(try await store.session(accountID: "account-b") == nil)
    #expect(try await store.pendingReviews(accountID: "account-b").isEmpty)
  }

  @Test func conflictRollsBackEntireSessionTransaction() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    try await store.saveSnapshot(snapshot(), credentialID: "a")
    var first = try session()
    try complete(&first)
    let version = try await store.saveSession(first, accountID: "account-a", expectedRevision: nil)
    try await store.removeSession(accountID: "account-a", expectedRevision: version)
    // First insert succeeds, second subject conflicts: neither the first insert nor session may survive.
    var options = StudySessionOptions()
    options.batchSize = 1
    var next = try StudySession(
      items: [
        .init(id: 0, subjectID: 43, assignmentID: 143, srsStage: 3, hasReading: false),
        .init(id: 1, subjectID: 42, assignmentID: 142, srsStage: 3, hasReading: false),
      ], options: options, seed: 0)
    while let question = next.nextQuestion() {
      _ = try next.mark(.correct, for: question, now: 100)
    }
    #expect(next.completedIDs == [0, 1])
    await #expect(throws: StudyStoreError.self) {
      try await store.saveSession(next, accountID: "account-a", expectedRevision: nil)
    }
    #expect(try await store.session(accountID: "account-a") == nil)
    #expect(try await store.pendingReviews(accountID: "account-a").map(\.subjectID) == [42])
  }

  @Test func practiceNeverCreatesPendingReviews() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    try await store.saveSnapshot(snapshot(), credentialID: "a")
    var state = try session(practice: true)
    try complete(&state)
    try await store.saveSession(state, accountID: "account-a", expectedRevision: nil)
    #expect(try await store.pendingReviews(accountID: "account-a").isEmpty)
  }

  @Test func sampleAndDifferentAccountCannotOverwriteCredentialBinding() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    try await store.saveSnapshot(snapshot(), credentialID: "a")
    await #expect(throws: StudyStoreError.self) {
      try await store.saveSnapshot(snapshot(account: "other"), credentialID: "a")
    }
    await #expect(throws: StudyStoreError.self) {
      try await store.saveSnapshot(StudySnapshot.sample(), credentialID: "a")
    }
    #expect(try await store.snapshot(credentialID: "a")?.accountID == "account-a")
  }
  @Test func acknowledgedNotesSurviveOlderDownloadAndStaleAcknowledgement() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let database = dir.appending(path: "study.store")
    do {
      let store = try await StudyStore.open(at: database)
      try await store.saveSnapshot(snapshot(), credentialID: "a")
      let original = StudyMaterial(
        subjectID: 42, meaningNote: "original", readingNote: "ねこ", meaningSynonyms: ["cat"])
      try await store.mergeMaterials(
        [original], accountID: "account-a", baseline: [:], replacingAll: true)
      let before = try #require(await store.materials(accountID: "account-a").first)
      let baseline = [Int64(42): before.revision]
      var edited = original
      edited.meaningNote = "edited"
      edited.meaningSynonyms.append("kitty")
      try await store.saveMaterial(
        edited, accountID: "account-a", expectedRevision: before.revision)
      let sent = try #require(await store.materials(accountID: "account-a").first)
      try await store.saveMaterial(
        original, accountID: "account-a", expectedRevision: sent.revision)
      try await store.acknowledgeMaterial(sent)
      let latest = try #require(await store.materials(accountID: "account-a").first)
      #expect(latest.pending && latest.revision != before.revision)
      try await store.acknowledgeMaterial(latest)
      try await store.mergeMaterials(
        [edited], accountID: "account-a", baseline: baseline, replacingAll: true)
      #expect(try await store.materials(accountID: "account-a").first?.material == original)
      await #expect(throws: StudyStoreError.self) {
        try await store.saveMaterial(
          edited, accountID: "account-a", expectedRevision: sent.revision)
      }
    }
    let reopened = try await StudyStore.open(at: database)
    let saved = try #require(await reopened.materials(accountID: "account-a").first)
    #expect(
      saved.material.meaningNote == "original" && saved.material.readingNote == "ねこ"
        && !saved.pending)
    #expect(try await reopened.materials(accountID: "other-account").isEmpty)
  }

  @Test func fullRefreshPrunesOnlyUnchangedUploadedNotes() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    try await store.saveSnapshot(snapshot(), credentialID: "a")
    try await store.mergeMaterials(
      [.init(subjectID: 42), .init(subjectID: 43)], accountID: "account-a", baseline: [:],
      replacingAll: true)
    let before = try await store.materials(accountID: "account-a")
    let baseline = Dictionary(
      uniqueKeysWithValues: before.map { ($0.material.subjectID, $0.revision) })
    try await store.saveMaterial(
      .init(subjectID: 42, meaningNote: "offline note"), accountID: "account-a",
      expectedRevision: baseline[42])
    try await store.mergeMaterials(
      [], accountID: "account-a", baseline: baseline, replacingAll: true)
    let remaining = try await store.materials(accountID: "account-a")
    #expect(
      remaining.count == 1 && remaining.first?.material.meaningNote == "offline note"
        && remaining.first?.pending == true)
  }

  @Test func fullCatalogSnapshotRoundTripsWithoutLosingNestedValues() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "study.store")
    let sample = try StudySnapshot.sample()
    let original = StudySnapshot(
      accountID: "large-fixture", username: "Large fixture", currentLevel: sample.currentLevel,
      onVacation: sample.onVacation, assignments: sample.assignments, statistics: sample.statistics,
      levels: sample.levels, subjects: sample.subjects, savedAt: sample.savedAt,
      pendingReviews: sample.pendingReviews)
    do {
      let store = try await StudyStore.open(at: url)
      try await store.saveSnapshot(original, credentialID: "fixture")
    }
    let reopened = try await StudyStore.open(at: url)
    let restored = try #require(await reopened.snapshot(credentialID: "fixture"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    #expect(restored.subjects.count == 2136)
    #expect(try encoder.encode(restored) == encoder.encode(original))
  }

}

extension StudyStoreTests {
  @Test func acknowledgedMaterialsAbsentFromAnOlderFullSnapshotSurviveReopen() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "study.store")
    let expected = [Int64(42), 43, 44].map {
      StudyMaterial(
        subjectID: $0, meaningNote: "  Edited \($0) 🐰\nSecond line",
        readingNote: "ねこ\n\($0)  ", meaningSynonyms: ["Exact \($0)", "別"])
    }
    var revisions: [Int64: UUID] = [:]
    do {
      let store = try await StudyStore.open(at: url)
      try await store.saveSnapshot(snapshot(), credentialID: "a")
      try await store.mergeMaterials(
        [.init(subjectID: 42, meaningNote: "old 42"), .init(subjectID: 43, meaningNote: "old 43")],
        accountID: "account-a", baseline: [:], replacingAll: true)
      let baseline = Dictionary(
        uniqueKeysWithValues:
          try await store.materials(accountID: "account-a").map {
            ($0.material.subjectID, $0.revision)
          })
      for material in expected {
        try await store.saveMaterial(
          material, accountID: "account-a", expectedRevision: baseline[material.subjectID])
        let sent = try #require(
          await store.materials(accountID: "account-a").first {
            $0.material.subjectID == material.subjectID
          })
        try await store.acknowledgeMaterial(sent)
        let acknowledged = try #require(
          await store.materials(accountID: "account-a").first {
            $0.material.subjectID == material.subjectID
          })
        try await store.acknowledgeMaterial(sent)
        let repeated = try #require(
          await store.materials(accountID: "account-a").first {
            $0.material.subjectID == material.subjectID
          })
        #expect(
          repeated.revision == acknowledged.revision && repeated.material == material
            && !repeated.pending)
        revisions[material.subjectID] = repeated.revision
      }
      try await store.mergeMaterials(
        [.init(subjectID: 42, meaningNote: "stale")],
        accountID: "account-a", baseline: baseline, replacingAll: true)
      #expect(try await store.materials(accountID: "account-a").map(\.material) == expected)
    }
    let reopened = try await StudyStore.open(at: url)
    let restored = try await reopened.materials(accountID: "account-a")
    #expect(restored.map(\.material) == expected)
    #expect(restored.allSatisfy { !$0.pending && $0.revision == revisions[$0.material.subjectID] })
  }
}
