import Foundation
import StudyCore
import Testing
import WaniKaniAPI

@testable import Tsurukame

@Suite(.serialized) @MainActor struct LessonPreferenceTests {
  @Test func commonPreferencesKeepTheOriginalIPhoneArchivesAndUnrelatedOptions() {
    let keys = [
      "lessonBatchSize", "prioritizeCurrentLevel", "apprenticeLessonsLimit", "showKanaOnlyVocab",
      "lessonOrder", "allowExcludeItems",
    ]
    let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer {
      for (key, value) in zip(keys, previous) {
        if let value {
          UserDefaults.standard.set(value, forKey: key)
        } else {
          UserDefaults.standard.removeObject(forKey: key)
        }
      }
    }
    let exactMatch = Settings.exactMatch
    var value = StudyLessonPreferences()
    value.batchSize = 7
    value.apprenticeLimit = 50
    value.includeKanaVocabulary = false
    value.allowVocabularyExclusion = false
    value.prioritizeCurrentLevel = true
    value.order = [.vocabulary, .kanji, .radical]
    let store = LegacyLessonPreferences()
    store.value = value
    #expect(store.value == value)
    #expect(
      Settings.lessonOrder == [.vocabulary, .kanji, .radical] && Settings.lessonBatchSize == 7
        && !Settings.allowExcludeItems)
    #expect(
      Settings.exactMatch == exactMatch
        && keys.allSatisfy { UserDefaults.standard.data(forKey: $0) != nil })
  }
  @Test func legacyItemsUseTheCommonStrictSortKeys() {
    var assignment = TKMAssignment()
    assignment.subjectID = 3
    assignment.level = 2
    assignment.subjectType = .vocabulary
    let first = ReviewItem(assignment: assignment)
    assignment.subjectID = 8
    let second = ReviewItem(assignment: assignment)
    let preferences = StudyLessonPreferences()
    #expect(preferences.precedes(first.lessonSortKey, second.lessonSortKey))
    #expect(!preferences.precedes(first.lessonSortKey, first.lessonSortKey))
  }
}
