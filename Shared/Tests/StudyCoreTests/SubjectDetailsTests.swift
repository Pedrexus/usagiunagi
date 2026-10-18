import Testing

@testable import StudyCore

@Test func detailsConcealMeaningLeaksUntilBothQuestionsAreAttempted() {
  let reading = SubjectDetailVisibility([.reading])
  #expect(reading.reading && !reading.meaning && !reading.readingExplanation)
  #expect(reading.editableQuestions.isEmpty)
  let meaning = SubjectDetailVisibility([.meaning])
  #expect(meaning.meaning && !meaning.reading && !meaning.readingExplanation)
  #expect(meaning.editableQuestions == [.meaning])
  let all = SubjectDetailVisibility([.meaning, .reading])
  #expect(all.meaning && all.reading && all.readingExplanation)
  #expect(all.editableQuestions == [.meaning, .reading])
  #expect(SubjectDetailVisibility([]).editableQuestions.isEmpty)
}

@Test func detailMeaningsNeverExposeBlacklistedAnswersOrDuplicatePrimaryMeanings() {
  var subject = CatalogSubject(id: 1, kind: .radical)
  subject.meanings = [
    .init("other", role: .secondary), .init("main", role: .primary),
    .init("old", role: .auxiliaryWhitelist), .init("reject", role: .blacklist),
  ]
  var preferences = SubjectDetailsPreferences()
  #expect(
    subject.displayedMeanings(preferences: preferences).map(\.text) == ["main", "other", "old"])
  preferences.showDeprecatedMnemonic = false
  #expect(subject.displayedMeanings(preferences: preferences).map(\.text) == ["main", "other"])
  preferences.showDeprecatedMnemonic = true
  subject.kind = .kanji
  #expect(subject.displayedMeanings(preferences: preferences).map(\.text) == ["main", "other"])
}

@Test func detailReadingPreferencesPreservePrimaryOrderAndKanaOnlyVocabulary() {
  var subject = CatalogSubject(id: 1, kind: .kanji)
  subject.readings = [
    .init("さけ", isPrimary: false, kind: .kunyomi),
    .init("しゅ", isPrimary: true, kind: .onyomi),
  ]
  var preferences = SubjectDetailsPreferences()
  preferences.primaryKanjiReadingsOnly = true
  preferences.useKatakanaForOnyomi = true
  #expect(subject.displayedReadings(preferences: preferences).map(\.text) == ["シュ"])
  preferences.primaryKanjiReadingsOnly = false
  #expect(subject.displayedReadings(preferences: preferences).map(\.text) == ["シュ", "さけ"])
  subject.kind = .vocabulary
  subject.japanese = "おはよう"
  subject.readings = []
  #expect(subject.displayedReadings(preferences: preferences).map(\.text) == ["おはよう"])
}

@Test func noteEditingRetainsExclusionAndExactUntouchedBytes() {
  let material = StudyMaterial(
    subjectID: 1, meaningNote: "  私\n#tsurukameExclude\n ",
    readingNote: "reading", meaningSynonyms: ["  Exact  "])
  #expect(material.isExcluded)
  #expect(material.replacingMeaningNote(material.meaningNoteText) == material)
  let edited = material.replacingMeaningNote("  new\n")
  #expect(edited.meaningNoteText == "  new\n" && edited.isExcluded)
  #expect(
    edited.readingNote == material.readingNote && edited.meaningSynonyms == material.meaningSynonyms
  )
  #expect(!StudyMaterial(subjectID: 1).replacingMeaningNote("note").isExcluded)
}

@Test func resolvingAnEditPreservesHiddenFieldsAndCurrentExclusion() {
  let current = StudyMaterial(
    subjectID: 3, meaningNote: "server\n#tsurukameExclude",
    readingNote: "new hidden reading", meaningSynonyms: ["server"])
  let changes = StudyMaterialChanges(meaningNote: "my draft", meaningSynonyms: ["mine"])
  let edited = changes.applying(to: current)
  #expect(edited.meaningNoteText == "my draft" && edited.isExcluded)
  #expect(edited.readingNote == "new hidden reading" && edited.meaningSynonyms == ["mine"])
  #expect(StudyMaterialChanges().applying(to: current) == current)
}
