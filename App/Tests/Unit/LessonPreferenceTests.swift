import Foundation
import StudyCore
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor struct LessonPreferenceTests {
  @Test func commonPreferencesPersistWithoutChangingReviewOptions() throws {
    try PreferenceTestValues.withDefaults { defaults in
      let review = try JSONEncoder().encode(ReviewPreferences())
      defaults.set(review, forKey: "native.reviewPreferences")
      let preferences = DefaultsStudyLessonPreferences(defaults: defaults)
      var value = StudyLessonPreferences()
      value.order = [.vocabulary, .kanji, .radical]
      value.batchSize = 7
      value.apprenticeLimit = 50
      value.prioritizeCurrentLevel = true
      value.includeKanaVocabulary = false
      value.allowVocabularyExclusion = false
      preferences.value = value
      #expect(DefaultsStudyLessonPreferences(defaults: defaults).value == value)
      var changed = preferences.value
      changed.order = [.radical, .vocabulary, .kanji]
      changed.batchSize = 9
      preferences.value = changed
      #expect(DefaultsStudyLessonPreferences(defaults: defaults).value == changed)
      #expect(defaults.data(forKey: "native.reviewPreferences") == review)
    }
  }
  @Test func nativeItemsUseTheCommonStrictSortKeys() {
    let first: StudyLessonPreferences.SortKey = (level: 2, kind: .vocabulary, subjectID: 3)
    let second: StudyLessonPreferences.SortKey = (level: 2, kind: .vocabulary, subjectID: 8)
    let preferences = StudyLessonPreferences()
    #expect(preferences.precedes(first, second))
    #expect(!preferences.precedes(first, first))
  }
}
