import Foundation
import StudyCore
import Testing

struct ReviewPreferencesTests {
  @Test func changedFieldsPreserveAnotherWindowsPreferences() {
    let opened = ReviewPreferences()
    var saved = opened
    saved.appearance = .dark
    saved.autoplayAudio = true
    saved.fontScale = 2
    var draft = opened
    draft.exactMatch = true
    draft.allowSkipping = true
    saved.applyChanges(from: opened, to: draft)
    #expect(saved.appearance == .dark && saved.autoplayAudio && saved.fontScale == 2)
    #expect(saved.exactMatch && saved.allowSkipping)
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
    var stored = original
    stored.applyChanges(from: original, to: changed)
    #expect(stored == changed)
    let encoded = try JSONEncoder().encode(stored)
    let decoded = try JSONDecoder().decode(ReviewPreferences.self, from: encoded)
    #expect(decoded == changed)
    stored.applyChanges(from: changed, to: original)
    #expect(stored == original)
  }
}
