import Foundation
import StudyCore
import Testing

struct ReviewPreferencesTests {
  @Test func changedFieldsPreserveAnotherWindowsPreferences() {
    let opened = ReviewPreferences()
    var saved = opened
    saved.appearance = .dark
    saved.autoplayAudio = true
    saved.completedItemFeedback = false
    saved.fontScale = 2
    var draft = opened
    draft.exactMatch = true
    draft.allowSkipping = true
    draft.correctAnswerFeedback = false
    saved.applyChanges(from: opened, to: draft)
    #expect(saved.appearance == .dark && saved.autoplayAudio && saved.fontScale == 2)
    #expect(saved.exactMatch && saved.allowSkipping)
    #expect(
      !saved.completedItemFeedback && !saved.correctAnswerFeedback && saved.srsMilestoneFeedback)
  }

  @Test func allEditableValuesRoundTripAndCanBeReset() throws {
    let original = ReviewPreferences()
    var changed = original
    changed.appearance = .light
    changed.stageIndicator = .dots
    changed.fontScale = 2.5
    changed.revealAnswers.toggle()
    changed.revealFullAnswer.toggle()
    changed.exactMatch.toggle()
    changed.allowCorrections.toggle()
    changed.allowSkipping.toggle()
    changed.autoplayAudio.toggle()
    changed.interruptBackgroundAudio.toggle()
    changed.correctAnswerFeedback.toggle()
    changed.completedItemFeedback.toggle()
    changed.srsMilestoneFeedback.toggle()
    var stored = original
    stored.applyChanges(from: original, to: changed)
    #expect(stored == changed)
    let encoded = try JSONEncoder().encode(stored)
    let decoded = try JSONDecoder().decode(ReviewPreferences.self, from: encoded)
    #expect(decoded == changed)
    stored.applyChanges(from: changed, to: original)
    #expect(stored == original)
  }

  @Test func olderSavedPreferencesKeepTheirValuesWhenFeedbackIsAdded() throws {
    let data = Data(
      #"{"appearance":"dark","stageIndicator":"dots","fontScale":1.75,"revealAnswers":false,"revealFullAnswer":true,"exactMatch":true,"allowCorrections":false,"allowSkipping":true,"autoplayAudio":true,"interruptBackgroundAudio":true}"#
        .utf8)
    let saved = try JSONDecoder().decode(ReviewPreferences.self, from: data)
    #expect(saved.appearance == .dark && saved.stageIndicator == .dots && saved.fontScale == 1.75)
    #expect(
      !saved.revealAnswers && saved.revealFullAnswer && saved.exactMatch && !saved.allowCorrections)
    #expect(saved.allowSkipping && saved.autoplayAudio && saved.interruptBackgroundAudio)
    #expect(
      saved.correctAnswerFeedback && saved.completedItemFeedback && saved.srsMilestoneFeedback)
  }
}

extension ReviewPreferencesTests {
  @Test func sessionOptionsMergeOnlyEditedFieldsAndRoundTrip() throws {
    let opened = ReviewPreferences()
    var saved = opened
    saved.sessionOptions.ankiMode = .both
    saved.sessionOptions.combinedAnki = true
    saved.sessionOptions.batchSize = 9
    var draft = opened
    draft.sessionOptions.groupMeaningReading = true
    draft.sessionOptions.meaningFirst = false
    draft.sessionOptions.incorrectAnswerDelay = 2
    draft.sessionOptions.skipKanjiReadings = true
    draft.sessionOptions.minimizePenalty = true
    saved.applyChanges(from: opened, to: draft)
    #expect(saved.sessionOptions.ankiMode == .both && saved.sessionOptions.combinedAnki)
    #expect(saved.sessionOptions.batchSize == 9 && saved.sessionOptions.groupMeaningReading)
    #expect(!saved.sessionOptions.meaningFirst && saved.sessionOptions.incorrectAnswerDelay == 2)
    #expect(saved.sessionOptions.skipKanjiReadings && saved.sessionOptions.minimizePenalty)
    let reopened = try JSONDecoder().decode(
      ReviewPreferences.self, from: JSONEncoder().encode(saved))
    #expect(reopened == saved)
    var reset = reopened
    reset.applyChanges(from: reopened, to: opened)
    #expect(reset == opened)
  }
  @Test func oldSessionsKeepQueueOptionsAndInferOnlyExistingCombinedAnki() throws {
    let old = Data(
      #"{"batchSize":7,"groupMeaningReading":true,"combinedAnki":true,"meaningFirst":false,"incorrectAnswerDelay":2,"skipKanjiReadings":true,"minimizePenalty":true}"#
        .utf8)
    let restored = try JSONDecoder().decode(StudySessionOptions.self, from: old)
    #expect(restored.ankiMode == .both && restored.combinedAnki)
    #expect(restored.batchSize == 7 && restored.groupMeaningReading && !restored.meaningFirst)
    #expect(
      restored.incorrectAnswerDelay == 2 && restored.skipKanjiReadings && restored.minimizePenalty)
    #expect(try JSONDecoder().decode(StudySessionOptions.self, from: Data("{}".utf8)) == .init())
    let oldPreferences = try JSONDecoder().decode(
      ReviewPreferences.self, from: Data(#"{"exactMatch":true}"#.utf8))
    #expect(oldPreferences.exactMatch && oldPreferences.sessionOptions == .init())
  }
  @Test(arguments: StudySessionOptions.AnkiMode.allCases)
  func ankiScopeIncludesOnlySelectedQuestions(mode: StudySessionOptions.AnkiMode) {
    #expect(mode.includes(.meaning) == (mode == .meaning || mode == .both))
    #expect(mode.includes(.reading) == (mode == .reading || mode == .both))
  }
}
