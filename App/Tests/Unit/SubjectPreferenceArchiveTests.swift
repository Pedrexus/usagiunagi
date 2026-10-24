import Foundation
import StudyCore
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor struct SubjectPreferenceArchiveTests {
  @Test func productionHostLoadsTheBundledArtworkCatalog() throws {
    #expect(try StudyArtwork.bundled().url(subjectID: 6)?.host == "global.discourse-cdn.com")
  }
  @Test func commonChoicesPersistWithoutChangingReviewPolicy() throws {
    try PreferenceTestValues.withDefaults { defaults in
      var review = ReviewPreferences()
      review.sessionOptions.skipKanjiReadings = true
      review.exactMatch = true
      let reviewData = try JSONEncoder().encode(review)
      defaults.set(reviewData, forKey: "native.reviewPreferences")
      var value = SubjectDetailsPreferences()
      value.primaryKanjiReadingsOnly = false
      value.useKatakanaForOnyomi = true
      value.showDeprecatedMnemonic = false
      value.blurTranslations = false
      value.showStatistics = false
      value.showArtwork = true
      value.showPreviousLevelGraph = false
      value.showSimilarKanjiAboveCurrentLevel = true
      let preferences = DefaultsStudySubjectPreferences(defaults: defaults)
      preferences.value = value
      #expect(DefaultsStudySubjectPreferences(defaults: defaults).value == value)
      var changed = preferences.value
      changed.showArtwork = false
      preferences.value = changed
      #expect(DefaultsStudySubjectPreferences(defaults: defaults).value == changed)
      #expect(defaults.data(forKey: "native.reviewPreferences") == reviewData)
    }
  }
}
