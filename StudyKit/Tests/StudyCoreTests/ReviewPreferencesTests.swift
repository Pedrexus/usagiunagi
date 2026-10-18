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
