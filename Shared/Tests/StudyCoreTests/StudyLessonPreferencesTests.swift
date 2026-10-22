import Foundation
import StudyCore
import Testing

@MainActor struct StudyLessonPreferencesTests {
  @Test func originalDefaultsAndPartialArchivesKeepEveryChoice() throws {
    let value = try JSONDecoder().decode(
      StudyLessonPreferences.self, from: Data(#"{"batchSize":7}"#.utf8))
    #expect(value.batchSize == 7 && value.order == [.radical, .kanji, .vocabulary])
    #expect(
      value.includeKanaVocabulary && value.allowVocabularyExclusion
        && value.apprenticeLimit == Int.max
        && !value.prioritizeCurrentLevel)
    #expect(
      try JSONDecoder().decode(StudyLessonPreferences.self, from: JSONEncoder().encode(value))
        == value)
  }
  @Test func normalizationKeepsACompleteUniqueOrderAndValidBatchSizes() {
    var value = StudyLessonPreferences()
    value.order = [.vocabulary, .vocabulary]
    value.batchSize = 0
    value.apprenticeLimit = -1
    #expect(value.normalized.order == [.vocabulary, .radical, .kanji])
    #expect(value.normalized.batchSize == 1 && value.normalized.apprenticeLimit == 0)
    value.batchSize = 99
    #expect(value.normalized.batchSize == 10)
  }
  @Test func oneStrictComparatorHonorsLevelTypeAndSubjectOrder() {
    var preferences = StudyLessonPreferences()
    let radical: StudyLessonPreferences.SortKey = (1, .radical, 4)
    let vocabulary: StudyLessonPreferences.SortKey = (1, .vocabulary, 1)
    let next: StudyLessonPreferences.SortKey = (2, .kanji, 2)
    #expect(preferences.precedes(radical, vocabulary) && preferences.precedes(vocabulary, next))
    #expect(!preferences.precedes(radical, radical) && !preferences.precedes(vocabulary, radical))
    preferences.order = [.vocabulary, .kanji, .radical]
    #expect(preferences.precedes(vocabulary, radical))
    preferences.prioritizeCurrentLevel = true
    #expect(preferences.precedes(next, vocabulary))
    #expect(preferences.precedes((1, .vocabulary, 1), (1, .vocabulary, 2)))
  }
  @Test func independentEditsMergeWithoutReplacingAnotherWindowsChoices() {
    let store = LessonPreferencesFixture()
    let settings = StudyLessonSettings(store: store)
    let original = settings.value
    var external = original
    external.order = [.vocabulary, .kanji, .radical]
    store.value = external
    var local = original
    local.batchSize = 9
    settings.applyChanges(from: original, to: local)
    #expect(settings.value.batchSize == 9 && settings.value.order == external.order)
    store.value.includeKanaVocabulary = false
    store.value.allowVocabularyExclusion = false
    settings.reload()
    #expect(!settings.value.includeKanaVocabulary && !settings.value.allowVocabularyExclusion)
  }
  @Test func nativeDefaultsPersistWithoutChangingOtherKeys() throws {
    let name = "lesson-options-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("keep", forKey: "other")
    let store = DefaultsStudyLessonPreferences(defaults: defaults)
    var value = StudyLessonPreferences()
    value.batchSize = 3
    value.allowVocabularyExclusion = false
    value.order = [.vocabulary, .radical, .kanji]
    store.value = value
    #expect(DefaultsStudyLessonPreferences(defaults: defaults).value == value)
    #expect(defaults.string(forKey: "other") == "keep")
  }
  @Test func visibilityAndApprenticeLimitAgreeWithoutDroppingPendingWorkload() {
    var profile = StudyAccountProfile(username: "Fixture")
    profile.level = 2
    profile.maxLevelGranted = 3
    let account = StudyAccountState(download: .init(accountID: "fixture", profile: profile))
    let subjects = (1...5).map { id in
      var item = CatalogSubject(
        id: Int64(id), kind: id == 1 ? .radical : id == 2 ? .kanji : .vocabulary)
      item.level = id == 2 ? 2 : 1
      item.isKanaOnlyVocabulary = id == 3 || id == 4
      return item
    }
    let assignments = subjects.map { subject in
      var item = CatalogAssignment(id: subject.id + 100, subjectID: subject.id, kind: subject.kind)
      item.level = subject.level
      item.unlockedAt = 1
      item.isKanaOnlyVocabulary = subject.isKanaOnlyVocabulary == true
      if subject.id >= 4 {
        item.srsStage = 2
        item.startedAt = 1
        item.availableAt = 1
      }
      return item
    }
    var preferences = StudyLessonPreferences()
    preferences.includeKanaVocabulary = false
    preferences.apprenticeLimit = 2
    let value = StudyAvailability(
      account: account, subjects: subjects, assignments: assignments,
      pending: [5], lessonPreferences: preferences)
    #expect(value.lessons.map(\.subjectID) == [1, 2])
    #expect(value.scheduled.isEmpty && value.practice(.recentLessons).isEmpty)
    #expect(value.apprenticeCount == 2 && value.apprenticeLimitReached)
  }
}

@MainActor private final class LessonPreferencesFixture: StudyLessonPreferenceStore {
  var value = StudyLessonPreferences()
}
