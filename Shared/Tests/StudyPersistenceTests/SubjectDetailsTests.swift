import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

struct SubjectDetailsTests {
  private let account = "fixture-user-id"
  private func store() async throws -> StudyStore {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    _ = try await store.refresh(
      credentialID: "credential", token: "fixture",
      client: WaniKaniClient(transport: DownloadFixture.response))
    return store
  }
  @Test func fullDetailsIncludeLocalUnsentNotesAndAccessibleRelations() async throws {
    let store = try await store()
    let existing = try await store.materials(accountID: account)
    let saved = try #require(existing.first { $0.material.subjectID == 1 })
    var material = saved.material
    material.meaningNote = "Unsent note 🐰"
    material.meaningSynonyms = ["First", "Single"]
    _ = try await store.saveMaterial(material, accountID: account, expectedRevision: saved.revision)
    let details = try await store.subjectDetails(subjectID: 1, accountID: account)
    #expect(details.subject.meaningMnemonic == "A <kanji>fixture</kanji> mnemonic.")
    #expect(details.subject.meaningHint == "Meaning hint")
    #expect(details.subject.readingHint == "Reading hint")
    #expect(details.material == material)
    #expect(details.components.map(\.id) == [3])
    #expect(details.combinations.map(\.id) == [5])
    #expect(details.similar.isEmpty)
    #expect(details.unavailableRelatedCount == 1)
    let vocabulary = try await store.subjectDetails(subjectID: 5, accountID: account)
    #expect(vocabulary.subject.sentences.first?.japanese == "はい。")
    #expect(vocabulary.subject.partOfSpeechNames?.contains("future_kind") == true)
    #expect(try await store.materials(accountID: account).first?.pending == true)
  }
  @Test func hiddenMissingAndForeignAccountContentIsUnavailable() async throws {
    let store = try await store()
    for id: Int64 in [4, 90000] {
      await #expect(throws: SubjectDetailsError.self) {
        try await store.subjectDetails(subjectID: id, accountID: account)
      }
    }
    await #expect(throws: StudyStoreError.self) {
      try await store.subjectDetails(subjectID: 1, accountID: "another-account")
    }
  }
  @Test func subscriptionLimitAppliesToSelectedAndRelatedSubjects() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var profile = StudyAccountProfile(username: "Limited")
    profile.maxLevelGranted = 3
    var allowed = CatalogSubject(id: 1, kind: .kanji)
    allowed.level = 1
    allowed.componentSubjectIDs = [3, 2, 3, 9000]
    var locked = CatalogSubject(id: 2, kind: .radical)
    locked.level = 4
    var available = CatalogSubject(id: 3, kind: .radical)
    available.level = 2
    var fixture = NativeStoreFixture(profile: profile)
    fixture.subjects = [allowed, locked, available]
    try await store.seedFixture(fixture, accountID: account, credentialID: "limited")
    let details = try await store.subjectDetails(subjectID: 1, accountID: account)
    #expect(details.components.map(\.id) == [3])
    #expect(details.unavailableRelatedCount == 2)
    await #expect(throws: SubjectDetailsError.self) {
      try await store.subjectDetails(subjectID: 2, accountID: account)
    }
  }
}

extension SubjectDetailsTests {
  private func exclusionStore() async throws -> StudyStore {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var profile = StudyAccountProfile(username: "Exclusion fixture")
    profile.level = 1
    profile.maxLevelGranted = 3
    var fixture = NativeStoreFixture(profile: profile)
    for id in 1...5 {
      var subject = CatalogSubject(id: Int64(id), kind: id == 3 ? .kanji : .vocabulary)
      subject.level = id == 5 ? 4 : 1
      subject.japanese = "一つ"
      subject.meanings = [.init("One thing", role: .primary)]
      subject.readings = [.init("ひとつ", isPrimary: true, kind: .unknown)]
      if id == 4 { subject.hiddenAt = 1 }
      fixture.subjects.append(subject)
      if id <= 3 {
        var item = CatalogAssignment(id: Int64(100 + id), subjectID: subject.id, kind: subject.kind)
        item.level = 1
        item.unlockedAt = 1
        if id != 2 {
          item.srsStage = 2
          item.startedAt = 1
          item.availableAt = 1
        }
        fixture.assignments.append(item)
      }
    }
    fixture.materials = [
      .init(
        serverID: 71,
        value: .init(
          subjectID: 1, meaningNote: " \nSaved note 🐰\n", readingNote: "reading",
          meaningSynonyms: ["Single"]), pending: false)
    ]
    try await store.seedFixture(fixture, accountID: account, credentialID: "fixture")
    return store
  }
  @Test func exclusionUsesTheLatestNotesAndPreservesServerIdentityAndSelectionRules() async throws {
    let store = try await exclusionStore()
    let initial = try await store.subjectDetails(subjectID: 1, accountID: account)
    var edited = try #require(initial.material)
    edited.meaningNote = "A newer note\n 🐰  "
    edited.meaningSynonyms = ["Single", "First"]
    try await store.saveSubjectMaterial(
      edited, accountID: account, expectedRevision: initial.savedMaterial?.revision)
    let excluded = try await store.setSubjectExcluded(
      subjectID: 1, accountID: account, excluded: true)
    #expect(
      excluded.material?.isExcluded == true
        && excluded.material?.meaningNoteText == edited.meaningNote)
    #expect(
      excluded.material?.readingNote == edited.readingNote
        && excluded.material?.meaningSynonyms == edited.meaningSynonyms)
    #expect(excluded.savedMaterial?.serverID == 71 && excluded.savedMaterial?.pending == true)
    var preferences = StudyLessonPreferences()
    preferences.allowVocabularyExclusion = false
    #expect(
      try await store.homeData(accountID: account, lessonPreferences: preferences).reviews == 1)
    #expect(
      try await store.subjectCatalog(accountID: account).items.first { $0.subject.id == 1 }?
        .isExcluded == true)
    let included = try await store.setSubjectExcluded(
      subjectID: 1, accountID: account, excluded: false)
    #expect(included.material == edited)
    #expect(try await store.homeData(accountID: account).reviews == 2)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
  @Test func repeatedChoicesDoNotCreateOrReplacePendingMaterial() async throws {
    let store = try await exclusionStore()
    let original = try await store.subjectDetails(subjectID: 1, accountID: account)
    let unchanged = try await store.setSubjectExcluded(
      subjectID: 1, accountID: account, excluded: false)
    #expect(
      unchanged.savedMaterial?.revision == original.savedMaterial?.revision
        && unchanged.savedMaterial?.pending == false)
    let first = try await store.setSubjectExcluded(subjectID: 1, accountID: account, excluded: true)
    let repeated = try await store.setSubjectExcluded(
      subjectID: 1, accountID: account, excluded: true)
    #expect(
      first.savedMaterial?.revision == repeated.savedMaterial?.revision
        && first.material == repeated.material)
    let absent = try await store.setSubjectExcluded(
      subjectID: 2, accountID: account, excluded: false)
    #expect(absent.savedMaterial == nil)
    _ = try await store.setSubjectExcluded(subjectID: 2, accountID: account, excluded: true)
    #expect(try await store.availableLessons(accountID: account).isEmpty)
  }
  @Test func exclusionRejectsForeignHiddenLockedAndNonVocabularyContentWithoutWriting() async throws
  {
    let store = try await exclusionStore()
    let original = try await store.materials(accountID: account)
    await #expect(throws: StudyStoreError.self) {
      try await store.setSubjectExcluded(subjectID: 1, accountID: "another-account", excluded: true)
    }
    for id: Int64 in [3, 4, 5, 9000] {
      await #expect(throws: SubjectDetailsError.self) {
        try await store.setSubjectExcluded(subjectID: id, accountID: account, excluded: true)
      }
    }
    #expect(
      try await store.materials(accountID: account).map(\.revision) == original.map(\.revision))
  }
  @Test func excludingVocabularyDoesNotRewriteAPausedReviewOrItsAssignments() async throws {
    let store = try await exclusionStore()
    let saved = try await store.openReviews(accountID: account)
    let assignments = try await store.assignments(accountID: account)
    _ = try await store.setSubjectExcluded(subjectID: 1, accountID: account, excluded: true)
    let reopened = try await store.openReviews(accountID: account)
    #expect(reopened.saved.revision == saved.saved.revision && reopened.question == saved.question)
    #expect(reopened.saved.session.items.keys.sorted() == saved.saved.session.items.keys.sorted())
    #expect(try await store.assignments(accountID: account) == assignments)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
}

extension SubjectDetailsTests {
  @Test func anOlderNotesEditorCannotUndoANewerExclusion() async throws {
    let store = try await exclusionStore()
    let original = try await store.subjectDetails(subjectID: 1, accountID: account)
    let excluded = try await store.setSubjectExcluded(
      subjectID: 1, accountID: account, excluded: true)
    var stale = try #require(original.material)
    stale.meaningNote = "An older unsaved draft"
    do {
      try await store.saveSubjectMaterial(
        stale, accountID: account, expectedRevision: original.savedMaterial?.revision)
      Issue.record("A stale notes editor replaced a newer exclusion")
    } catch StudyStoreError.staleMaterial {}
    let current = try await store.subjectDetails(subjectID: 1, accountID: account)
    #expect(
      current.savedMaterial?.revision == excluded.savedMaterial?.revision
        && current.material == excluded.material)
  }
}
