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
      client: .init(transport: DownloadFixture.response))
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
    var fixture = LegacyStudyExport(schemaVersion: 15, profile: profile)
    fixture.subjects = [allowed, locked, available]
    _ = try await store.importLegacyAccount(
      fixture, sourceID: "limited", verifiedAccountID: account,
      verifiedUsername: profile.username, credentialID: "limited")
    let details = try await store.subjectDetails(subjectID: 1, accountID: account)
    #expect(details.components.map(\.id) == [3])
    #expect(details.unavailableRelatedCount == 2)
    await #expect(throws: SubjectDetailsError.self) {
      try await store.subjectDetails(subjectID: 2, accountID: account)
    }
  }
}
