import Foundation
import StudyCore
import Testing

@testable import StudyPersistence

struct LegacyImportTests {
  private func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(value)
  }
  private func fixture() -> LegacyStudyExport {
    var profile = StudyAccountProfile(username: "migration-fixture")
    profile.level = 12
    profile.maxLevelGranted = 60
    profile.subscribed = true
    profile.startedAt = 100
    profile.vacationStartedAt = 500
    var source = LegacyStudyExport(schemaVersion: 15, profile: profile)
    var subject = CatalogSubject(id: 42, kind: .vocabulary)
    subject.level = 12
    subject.japanese = "猫"
    subject.slug = "猫"
    subject.documentURL = "https://www.wanikani.com/vocabulary/猫"
    subject.meanings = [
      .init("cat", role: .primary), .init("kitty", role: .auxiliaryWhitelist),
      .init("dog", role: .blacklist),
    ]
    subject.readings = [.init("ねこ", isPrimary: true, kind: .kunyomi)]
    subject.meaningMnemonic = "<kanji>猫</kanji> mnemonic"
    subject.readingMnemonic = "Reading explanation"
    subject.meaningHint = "Meaning hint"
    subject.readingHint = "Reading hint"
    subject.deprecatedMnemonic = "Older mnemonic"
    subject.componentSubjectIDs = [20]
    subject.amalgamationSubjectIDs = [43]
    subject.visuallySimilarKanjiIDs = [44]
    subject.visuallySimilarKanji = "苗"
    subject.characterImageURL = "https://example.invalid/radical.svg"
    subject.hasCharacterImageFile = true
    subject.partsOfSpeech = [1, 2, 99]
    subject.sentences = [.init(japanese: "猫です。", english: "It is a cat.")]
    subject.audio = [.init(url: "https://example.invalid/cat.mp3", voiceActorID: 7)]
    source.subjects = [subject]
    var assignment = CatalogAssignment(id: 142, subjectID: 42, kind: .vocabulary)
    assignment.level = 12
    assignment.srsStage = 3
    assignment.availableAt = 400
    assignment.startedAt = 150
    assignment.passedAt = 200
    assignment.burnedAt = 300
    var available = CatalogAssignment(id: 143, subjectID: 43, kind: .radical)
    available.srsStage = 2
    available.availableAt = 400
    source.assignments = [assignment, available]
    source.supersededAssignments = [.init(id: 141, subjectID: 42, kind: .vocabulary)]
    source.pendingReviews = [
      .init(
        assignment: assignment,
        submission: .init(
          itemID: 0,
          subjectID: 42, assignmentID: 142, isLesson: false, meaningWrong: true,
          readingWrong: false,
          meaningWrongCount: 2, readingWrongCount: 0, createdAt: 450))
    ]
    source.materials = [
      .init(
        serverID: 242,
        value: .init(
          subjectID: 42, meaningNote: "未送信\nNote",
          readingNote: "ねこ", meaningSynonyms: ["kitty", "house cat"]), pending: true,
        legacyRevision: 9)
    ]
    source.progress = [
      .init(
        subjectID: 42, level: 12, srsStage: 2, kind: .vocabulary,
        lastMistakeLocalTime: "2026-10-17 12:34:56", legacyRevision: 8)
    ]
    var level = CatalogLevelProgression(id: 5)
    level.level = 12
    level.unlockedAt = 100
    level.startedAt = 200
    level.createdAt = 90
    level.passedAt = 300
    level.completedAt = 400
    level.abandonedAt = 500
    source.levels = [level]
    var statistic = CatalogReviewStatistic(
      id: 342,
      answers: .init(
        subjectID: 42, type: .vocabulary,
        meaningCorrect: 9, meaningIncorrect: 2, meaningCurrentStreak: 3, readingCorrect: 8,
        readingIncorrect: 1, readingCurrentStreak: 4, hidden: true))
    statistic.createdAt = 100
    statistic.meaningMaxStreak = 6
    statistic.readingMaxStreak = 7
    statistic.percentageCorrect = 85
    source.statistics = [statistic]
    var voice = StudyVoiceActor(id: 7)
    voice.name = "Voice"
    voice.description = "Fixture"
    voice.gender = 2
    source.voices = [voice]
    source.audio = [
      .init(subjectID: 42, voiceActorID: 7, level: 12, url: "https://example.invalid/cat.mp3")
    ]
    source.cursors = ["subjects_updated_after": "2026-10-17T00:00:00Z"]
    return source
  }
  @discardableResult private func importFixture(
    _ source: LegacyStudyExport, into store: StudyStore, sourceID: String = "fixture"
  ) async throws -> LegacyImportResult {
    try await store.importLegacyAccount(
      source, sourceID: sourceID, verifiedAccountID: "account-a",
      verifiedUsername: "migration-fixture", credentialID: "credential-a")
  }

  @Test func completeImportSurvivesReopenAndSeparatesPendingAnswers() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "study.store")
    let source = fixture()
    do {
      let store = try await StudyStore.open(at: url)
      let result = try await importFixture(source, into: store)
      #expect(!result.alreadyImported && result.subjects == 1 && result.assignments == 1)
      #expect(result.pendingReviews == 1 && result.pendingMaterials == 1)
    }
    let store = try await StudyStore.open(at: url)
    #expect(try encoded(await store.catalog(accountID: "account-a")) == encoded(source.subjects))
    #expect(
      try encoded(await store.assignments(accountID: "account-a"))
        == encoded([source.assignments[1]]))
    let state = try #require(await store.accountState(accountID: "account-a"))
    #expect(try encoded(state) == encoded(StudyAccountState(legacy: source)))
    let review = try #require(await store.pendingReviews(accountID: "account-a").first)
    #expect(review.submission == source.pendingReviews[0].submission && review.attempted)
    #expect(
      try encoded(review.originalAssignment)
        == encoded(Optional(source.pendingReviews[0].assignment)))
    await #expect(throws: StudyStoreError.self) { try await store.beginReviewAttempt(review) }
    let material = try #require(await store.materials(accountID: "account-a").first)
    #expect(
      material.material == source.materials[0].value && material.pending && material.serverID == 242
    )
    #expect(material.issue?.reason == .uncertain && material.attemptedMaterial == nil)
    try await store.saveMaterial(
      .init(subjectID: 42, meaningNote: "edited after import"), accountID: "account-a",
      expectedRevision: material.revision)
    #expect(try await store.materials(accountID: "account-a").first?.issue?.reason == .uncertain)
    let snapshot = try #require(await store.snapshot(credentialID: "credential-a"))
    #expect(
      snapshot.accountID == "account-a" && snapshot.pendingReviews == 1 && snapshot.onVacation)
    #expect(snapshot.assignments.map(\.subjectID) == [43])
    #expect(try await store.catalog(accountID: "other-account").isEmpty)
  }

  @Test func receiptPreventsResurrectionAndRejectsChangedSource() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let source = fixture()
    try await importFixture(source, into: store)
    let review = try #require(await store.pendingReviews(accountID: "account-a").first)
    let material = try #require(await store.materials(accountID: "account-a").first)
    try await store.acknowledgeReview(review)
    try await store.acknowledgeMaterial(material)
    try await store.removeSnapshot(credentialID: "credential-a")
    #expect(try await importFixture(source, into: store).alreadyImported)
    #expect(try await store.pendingReviews(accountID: "account-a").isEmpty)
    #expect(try await store.materials(accountID: "account-a").first?.pending == false)
    #expect(try await store.snapshot(credentialID: "credential-a") == nil)
    var changed = source
    changed.profile.level += 1
    await #expect(throws: LegacyImportError.self) { try await importFixture(changed, into: store) }
    #expect(try await store.accountState(accountID: "account-a")?.profile.level == 12)
  }

  @Test func invalidPendingPayloadRollsBackCatalogAndReceipt() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var source = fixture()
    let invalid = StudyReviewSubmission(
      itemID: 0, subjectID: 42, assignmentID: 999, isLesson: false,
      meaningWrong: false, readingWrong: false, meaningWrongCount: 0, readingWrongCount: 0,
      createdAt: nil)
    source.pendingReviews = [.init(assignment: source.assignments[0], submission: invalid)]
    await #expect(throws: LegacyImportError.self) { try await importFixture(source, into: store) }
    #expect(try await store.catalog(accountID: "account-a").isEmpty)
    #expect(try await store.assignments(accountID: "account-a").isEmpty)
    #expect(try await store.accountState(accountID: "account-a") == nil)
    #expect(try await store.snapshot(credentialID: "credential-a") == nil)
    #expect(try await !importFixture(fixture(), into: store).alreadyImported)
  }

  @Test func wrongAccountDuplicateIdentifiersAndFutureSchemaLeaveDestinationEmpty() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var source = fixture()
    source.profile.username = "other-account"
    await #expect(throws: LegacyImportError.self) { try await importFixture(source, into: store) }
    source = fixture()
    source.subjects += source.subjects
    await #expect(throws: LegacyImportError.self) { try await importFixture(source, into: store) }
    source = fixture()
    source.schemaVersion = 16
    await #expect(throws: LegacyImportError.self) { try await importFixture(source, into: store) }
    #expect(try await store.catalog(accountID: "account-a").isEmpty)
    #expect(try await store.pendingReviews(accountID: "account-a").isEmpty)
  }

  @Test func existingNativeWorkAndCredentialBindingCannotBeOverwritten() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let snapshot = StudySnapshot(
      accountID: "account-a", username: "migration-fixture", currentLevel: 20,
      assignments: [], statistics: [], levels: [], subjects: [])
    try await store.saveSnapshot(snapshot, credentialID: "credential-a")
    try await store.saveMaterial(
      .init(subjectID: 42, meaningNote: "newer work"), accountID: "account-a", expectedRevision: nil
    )
    await #expect(throws: LegacyImportError.self) {
      try await importFixture(fixture(), into: store)
    }
    #expect(
      try await store.materials(accountID: "account-a").first?.material.meaningNote == "newer work")
    await #expect(throws: LegacyImportError.self) {
      try await store.importLegacyAccount(
        fixture(), sourceID: "fixture", verifiedAccountID: "other-account",
        verifiedUsername: "migration-fixture", credentialID: "credential-a")
    }
    #expect(try await store.catalog(accountID: "other-account").isEmpty)
  }

  @Test func freshVerifiedSnapshotIsPreservedDuringImport() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let snapshot = StudySnapshot(
      accountID: "account-a", username: "migration-fixture", currentLevel: 20,
      assignments: [], statistics: [], levels: [], subjects: [])
    try await store.saveSnapshot(snapshot, credentialID: "credential-a")
    try await importFixture(fixture(), into: store)
    #expect(try await store.snapshot(credentialID: "credential-a")?.currentLevel == 20)
    #expect(try await store.pendingReviews(accountID: "account-a").count == 1)
  }
}
