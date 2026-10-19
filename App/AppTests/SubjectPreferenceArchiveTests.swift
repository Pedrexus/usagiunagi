import Foundation
import StudyCore
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor struct SubjectPreferenceArchiveTests {
  @Test func productionHostLoadsTheBundledArtworkCatalog() throws {
    #expect(try StudyArtwork.bundled().url(subjectID: 6)?.host == "global.discourse-cdn.com")
  }
  @Test func commonChoicesPreserveTheOriginalIPhoneArchivesAndReviewPolicy() {
    let keys = [
      "showAllReadings", "useKatakanaForOnyomi", "showOldMnemonic", "blurContextSentences",
      "showStatsSection", "showArtwork", "showPreviousLevelGraph", "showSimilarKanjiAboveLevel",
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
    let skip = Settings.skipKanjiReadings
    let exact = Settings.exactMatch
    var value = SubjectDetailsPreferences()
    value.primaryKanjiReadingsOnly = false
    value.useKatakanaForOnyomi = true
    value.showDeprecatedMnemonic = false
    value.blurTranslations = false
    value.showStatistics = false
    value.showArtwork = true
    value.showPreviousLevelGraph = false
    value.showSimilarKanjiAboveCurrentLevel = true
    let store = LegacySubjectPreferences()
    store.value = value
    #expect(store.value == value && Settings.showAllReadings && Settings.useKatakanaForOnyomi)
    #expect(Settings.skipKanjiReadings == skip && Settings.exactMatch == exact)
    #expect(keys.allSatisfy { UserDefaults.standard.data(forKey: $0) != nil })
  }
}
