import CryptoKit
import Foundation
import Testing

@testable import StudyCore

struct SubjectPreferenceTests {
  @Test func defaultsAndOlderArchivesKeepTheOriginalDisplayChoices() throws {
    let expected = SubjectDetailsPreferences()
    #expect(
      expected.primaryKanjiReadingsOnly && expected.blurTranslations && expected.showStatistics)
    #expect(expected.showDeprecatedMnemonic && expected.showPreviousLevelGraph)
    #expect(
      !expected.useKatakanaForOnyomi && !expected.showArtwork
        && !expected.showSimilarKanjiAboveCurrentLevel)
    let empty = try JSONEncoder().encode([String: Bool]())
    #expect(try JSONDecoder().decode(SubjectDetailsPreferences.self, from: empty) == expected)
    let older = try JSONEncoder().encode(["useKatakanaForOnyomi": true, "blurTranslations": false])
    let decoded = try JSONDecoder().decode(SubjectDetailsPreferences.self, from: older)
    #expect(decoded.useKatakanaForOnyomi && !decoded.blurTranslations)
    #expect(
      decoded.showStatistics && decoded.showDeprecatedMnemonic && decoded.primaryKanjiReadingsOnly)
    #expect(
      try JSONDecoder().decode(SubjectDetailsPreferences.self, from: JSONEncoder().encode(decoded))
        == decoded)
  }
  @Test @MainActor func independentWindowsMergeOnlyTheirChangesAndReopenWithTheSameValues() throws {
    let suite = "subject-preferences-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = DefaultsStudySubjectPreferences(defaults: defaults)
    let first = StudySubjectSettings(store: store)
    let second = StudySubjectSettings(store: store)
    let old = first.value
    var reading = old
    reading.useKatakanaForOnyomi = true
    first.applyChanges(from: old, to: reading)
    var translation = old
    translation.blurTranslations = false
    second.applyChanges(from: old, to: translation)
    let reopened = StudySubjectSettings(store: DefaultsStudySubjectPreferences(defaults: defaults))
    #expect(
      reopened.value.useKatakanaForOnyomi && !reopened.value.blurTranslations
        && reopened.value.showStatistics)
    first.reload()
    #expect(first.value == reopened.value)
    defaults.set(Data([0]), forKey: "native.subjectPreferences")
    #expect(store.value == SubjectDetailsPreferences())
  }
  @Test func similarKanjiVisibilityRetainsOrderAndRespectsTheCurrentLevel() {
    let subjects = (1...4).map { level in
      var subject = CatalogSubject(id: Int64(level), kind: .kanji)
      subject.level = level
      return subject
    }.reversed()
    var preferences = SubjectDetailsPreferences()
    #expect(preferences.visibleSimilar(Array(subjects), currentLevel: 2).map(\.id) == [2, 1])
    preferences.showSimilarKanjiAboveCurrentLevel = true
    #expect(preferences.visibleSimilar(Array(subjects), currentLevel: 2).map(\.id) == [4, 3, 2, 1])
  }
  @Test func everyOriginalArtworkEntrySurvivesTheResourceConversion() throws {
    let catalog = try StudyArtwork.bundled()
    #expect(catalog.paths.count == 469)
    let canonical = catalog.paths.keys.sorted().map { "\($0):\(catalog.paths[$0]!)\n" }.joined()
    let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    #expect(digest == "00d4f38cd8546f92f190bd71fd79f4d9126a799eab9150a71930f567e1758b40")
    #expect(
      catalog.url(subjectID: 6)?.absoluteString
        == "https://global.discourse-cdn.com/wanikanicommunity/original/4X/5/6/f/56f448502c1e93a871d9c6c47bb1f9a23950b531.png"
    )
    #expect(catalog.url(subjectID: 0) == nil && catalog.url(subjectID: -1) == nil)
    #expect(throws: DecodingError.self) { try StudyArtwork(data: Data([0])) }
  }
}
