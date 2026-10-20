import Foundation
import StudyCore
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor struct LessonPreferenceTests {
  @Test func commonPreferencesKeepTheOriginalIPhoneArchivesAndUnrelatedOptions() throws {
    try PreferenceTestValues.withDefaults { defaults in
      let integers = ["lessonBatchSize": 7, "apprenticeLessonsLimit": 50]
      let booleans = [
        "prioritizeCurrentLevel": true, "showKanaOnlyVocab": false, "allowExcludeItems": false,
        "exactMatch": true,
      ]
      for (key, value) in integers {
        try PreferenceTestValues.archive(value, key: key, in: defaults)
      }
      for (key, value) in booleans {
        try PreferenceTestValues.archive(value, key: key, in: defaults)
      }
      try PreferenceTestValues.archive([3, 2, 1], key: "lessonOrder", in: defaults)
      let keys = Array(integers.keys) + Array(booleans.keys) + ["lessonOrder"]
      let original = keys.map { defaults.data(forKey: $0) }
      let source = try LegacyPreferenceImporter.read(defaults: defaults)
      #expect(source.lessons.order == [.vocabulary, .kanji, .radical])
      #expect(source.lessons.batchSize == 7 && source.lessons.apprenticeLimit == 50)
      #expect(source.lessons.prioritizeCurrentLevel && !source.lessons.includeKanaVocabulary)
      #expect(!source.lessons.allowVocabularyExclusion && source.review.exactMatch)
      try StudyPreferenceImport(defaults: defaults).apply(source, accountID: "fixture")
      let review = defaults.data(forKey: "native.reviewPreferences")
      let preferences = DefaultsStudyLessonPreferences(defaults: defaults)
      #expect(preferences.value == source.lessons)
      var changed = preferences.value
      changed.order = [.radical, .vocabulary, .kanji]
      changed.batchSize = 9
      preferences.value = changed
      #expect(DefaultsStudyLessonPreferences(defaults: defaults).value == changed)
      #expect(defaults.data(forKey: "native.reviewPreferences") == review)
      #expect(keys.map { defaults.data(forKey: $0) } == original)
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
