import Foundation
import StudyCore
import StudyPersistence
import Testing

struct LessonPreferencesTests {
  private func store() async throws -> StudyStore {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var profile = StudyAccountProfile(username: "Lesson fixture")
    profile.level = 2
    profile.maxLevelGranted = 3
    var source = NativeStoreFixture(profile: profile)
    for id in 1...4 {
      var subject = CatalogSubject(
        id: Int64(id), kind: id == 1 ? .radical : id == 2 ? .kanji : .vocabulary)
      subject.level = id == 2 ? 2 : 1
      subject.japanese = id >= 3 ? "いち" : "一"
      subject.meanings = [.init("One", role: .primary)]
      if id == 2 { subject.readings = [.init("いち", isPrimary: true, kind: .onyomi)] }
      subject.isKanaOnlyVocabulary = id >= 3
      var assignment = CatalogAssignment(
        id: Int64(100 + id), subjectID: subject.id, kind: subject.kind)
      assignment.level = subject.level
      assignment.unlockedAt = 1
      assignment.isKanaOnlyVocabulary = id >= 3
      if id == 4 {
        assignment.srsStage = 2
        assignment.startedAt = 1
        assignment.availableAt = 1
      }
      source.subjects.append(subject)
      source.assignments.append(assignment)
    }
    try await store.seedFixture(source, accountID: "account", credentialID: "credential")
    return store
  }
  @Test func lessonSelectionUsesTheSameOrderAndKanaChoiceAsHome() async throws {
    let store = try await store()
    #expect(try await store.availableLessons(accountID: "account").map(\.id) == [1, 3, 2])
    var preferences = StudyLessonPreferences()
    preferences.order = [.vocabulary, .kanji, .radical]
    preferences.prioritizeCurrentLevel = true
    preferences.includeKanaVocabulary = false
    #expect(
      try await store.availableLessons(accountID: "account", lessonPreferences: preferences).map(
        \.id) == [2, 1])
    #expect(
      try await store.homeData(accountID: "account", lessonPreferences: preferences).lessons == 2)
  }
  @Test func apprenticeLimitDisablesHomeAndPreventsStartingNewLessons() async throws {
    let store = try await store()
    var preferences = StudyLessonPreferences()
    preferences.apprenticeLimit = 1
    let home = try await store.homeData(accountID: "account", lessonPreferences: preferences)
    #expect(home.lessons == 3 && home.lessonsDisabledMessage == "Apprentice limit reached")
    await #expect(throws: NativeReviewError.apprenticeLimitReached) {
      try await store.openLessons(
        accountID: "account", subjectIDs: [1], lessonPreferences: preferences)
    }
    #expect(try await store.session(accountID: "account") == nil)
  }
  @Test func savedLessonQuizSurvivesMoreRestrictivePreferences() async throws {
    let store = try await store()
    let saved = try await store.openLessons(accountID: "account", subjectIDs: [3])
    var preferences = StudyLessonPreferences()
    preferences.apprenticeLimit = 0
    preferences.includeKanaVocabulary = false
    let resumed = try await store.openLessons(
      accountID: "account", subjectIDs: [3], lessonPreferences: preferences)
    #expect(
      resumed.saved.revision == saved.saved.revision && resumed.question == saved.question
        && resumed.saved.session.items.keys.sorted() == saved.saved.session.items.keys.sorted()
    )
  }
  @Test func hidingKanaOnlyVocabularyAffectsNewReviewsButDoesNotRewriteAPausedSession() async throws
  {
    let store = try await store()
    var hidden = StudyLessonPreferences()
    hidden.includeKanaVocabulary = false
    await #expect(throws: NativeReviewError.noReviews) {
      try await store.openReviews(accountID: "account", lessonPreferences: hidden)
    }
    let original = try await store.openReviews(accountID: "account")
    let resumed = try await store.openReviews(accountID: "account", lessonPreferences: hidden)
    #expect(
      resumed.saved.revision == original.saved.revision && resumed.question == original.question)
  }
}
