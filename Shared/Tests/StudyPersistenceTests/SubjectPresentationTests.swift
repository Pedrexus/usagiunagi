import Foundation
import StudyCore
import Testing

@testable import StudyPersistence

struct SubjectPresentationTests {
  private let account = "subject-presentation"
  private func store() async throws -> StudyStore {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var profile = StudyAccountProfile(username: "Subject presentation fixture")
    profile.level = 2
    profile.maxLevelGranted = 3
    var source = LegacyStudyExport(schemaVersion: 15, profile: profile)
    for (id, text, level, kind) in [
      (Int64(1), "一", 1, SubjectKind.kanji), (2, "二", 2, .kanji),
      (3, "三", 3, .kanji), (4, "外", 4, .kanji), (5, "隠", 1, .kanji), (6, "二", 1, .vocabulary),
    ] {
      var subject = CatalogSubject(id: id, kind: kind)
      subject.level = level
      subject.japanese = text
      subject.meanings = [.init("Fixture", role: .primary)]
      subject.readings = [.init("いち", isPrimary: true, kind: .onyomi)]
      if id == 1 {
        subject.visuallySimilarKanjiIDs = [3, 99]
        subject.visuallySimilarKanji = "二三外隠二"
      }
      if id == 5 { subject.hiddenAt = 1 }
      source.subjects.append(subject)
      if id <= 2 {
        var assignment = CatalogAssignment(id: id + 100, subjectID: id, kind: kind)
        assignment.level = level
        assignment.srsStage = 3
        assignment.startedAt = 100
        assignment.availableAt = 200
        source.assignments.append(assignment)
      }
    }
    _ = try await store.importLegacyAccount(
      source, sourceID: "presentation", verifiedAccountID: account,
      verifiedUsername: profile.username, credentialID: "presentation")
    return store
  }
  @Test func presentationIncludesSavedProgressAndResolvesOnlyAccessibleSimilarKanji() async throws {
    let store = try await store()
    let assignments = try await store.assignments(accountID: account)
    let details = try await store.subjectDetails(subjectID: 1, accountID: account)
    #expect(
      details.currentLevel == 2 && details.assignment == assignments.first { $0.subjectID == 1 })
    #expect(details.similar.map(\.id) == [3, 2])
    #expect(details.subject.visuallySimilarKanji.isEmpty)
    var preferences = SubjectDetailsPreferences()
    #expect(
      preferences.visibleSimilar(details.similar, currentLevel: details.currentLevel).map(\.id) == [
        2
      ])
    preferences.showSimilarKanjiAboveCurrentLevel = true
    #expect(
      preferences.visibleSimilar(details.similar, currentLevel: details.currentLevel).map(\.id) == [
        3, 2,
      ])
    #expect(
      try await store.catalog(accountID: account).first { $0.id == 1 }?.visuallySimilarKanji
        == "二三外隠二")
    #expect(try await store.assignments(accountID: account) == assignments)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
  @Test func hidingThePriorLevelChangesOnlyHomePresentation() async throws {
    let store = try await store()
    #expect(try await store.homeData(accountID: account).levels.map(\.id) == [1, 2])
    var preferences = SubjectDetailsPreferences()
    preferences.showPreviousLevelGraph = false
    #expect(
      try await store.homeData(accountID: account, subjectPreferences: preferences).levels.map(\.id)
        == [2])
    #expect(try await store.homeData(accountID: account).levels.map(\.id) == [1, 2])
    #expect(try await store.assignments(accountID: account).count == 2)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
}
