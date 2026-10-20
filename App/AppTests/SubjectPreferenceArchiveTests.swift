import Foundation
import StudyCore
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor struct SubjectPreferenceArchiveTests {
  @Test func productionHostLoadsTheBundledArtworkCatalog() throws {
    #expect(try StudyArtwork.bundled().url(subjectID: 6)?.host == "global.discourse-cdn.com")
  }
  @Test func commonChoicesPreserveTheOriginalIPhoneArchivesAndReviewPolicy() throws {
    try PreferenceTestValues.withDefaults { defaults in
      let choices = [
        "showAllReadings": true, "useKatakanaForOnyomi": true, "showOldMnemonic": false,
        "blurContextSentences": false, "showStatsSection": false, "showArtwork": true,
        "showPreviousLevelGraph": false, "showSimilarKanjiAboveLevel": true,
      ]
      for (key, value) in choices {
        try PreferenceTestValues.archive(value, key: key, in: defaults)
      }
      try PreferenceTestValues.archive(true, key: "skipKanjiReadings", in: defaults)
      try PreferenceTestValues.archive(true, key: "exactMatch", in: defaults)
      let original = defaults.dictionaryRepresentation() as NSDictionary
      let source = try LegacyPreferenceImporter.read(defaults: defaults)
      #expect(!source.subjects.primaryKanjiReadingsOnly && source.subjects.useKatakanaForOnyomi)
      #expect(!source.subjects.showDeprecatedMnemonic && !source.subjects.blurTranslations)
      #expect(!source.subjects.showStatistics && source.subjects.showArtwork)
      #expect(
        !source.subjects.showPreviousLevelGraph && source.subjects.showSimilarKanjiAboveCurrentLevel
      )
      try StudyPreferenceImport(defaults: defaults).apply(source, accountID: "fixture")
      let reviewBefore = defaults.data(forKey: "native.reviewPreferences")
      let preferences = DefaultsStudySubjectPreferences(defaults: defaults)
      #expect(preferences.value == source.subjects)
      var changed = preferences.value
      changed.showArtwork = false
      preferences.value = changed
      #expect(DefaultsStudySubjectPreferences(defaults: defaults).value == changed)
      #expect(defaults.data(forKey: "native.reviewPreferences") == reviewBefore)
      for key in choices.keys {
        #expect(defaults.object(forKey: key) as? Data == original[key] as? Data)
      }
      #expect(
        defaults.object(forKey: "skipKanjiReadings") as? Data == original["skipKanjiReadings"]
          as? Data)
      #expect(defaults.object(forKey: "exactMatch") as? Data == original["exactMatch"] as? Data)
    }
  }
}
