import StudyCore
import SwiftUI

/// Queue choices are captured when a session starts; paused work keeps its saved choices.
struct StudySessionSettingsContent: View {
  @Binding var options: StudySessionOptions
  var body: some View {
    Section {
      Picker("Answer mode", selection: $options.ankiMode) {
        Text("Typed answers").tag(StudySessionOptions.AnkiMode.off)
        Text("Anki: meaning only").tag(StudySessionOptions.AnkiMode.meaning)
        Text("Anki: reading only").tag(StudySessionOptions.AnkiMode.reading)
        Text("Anki: meaning and reading").tag(StudySessionOptions.AnkiMode.both)
      }.accessibilityIdentifier("reviewSettings.answerMode")
      if options.ankiMode == .both {
        Toggle("Combine meaning and reading", isOn: $options.combinedAnki)
          .accessibilityIdentifier("reviewSettings.combineAnki")
      }
      Toggle("Back-to-back meaning and reading", isOn: $options.groupMeaningReading)
        .accessibilityIdentifier("reviewSettings.groupMeaningReading")
      if options.groupMeaningReading || (options.ankiMode == .both && options.combinedAnki) {
        Picker("Question order", selection: $options.meaningFirst) {
          Text("Meaning then reading").tag(true)
          Text("Reading then meaning").tag(false)
        }.accessibilityIdentifier("reviewSettings.meaningFirst")
      } else {
        Picker("Reviews between meaning and reading", selection: $options.batchSize) {
          ForEach(3...10, id: \.self) { Text("\($0) reviews").tag($0) }
        }.accessibilityIdentifier("reviewSettings.batchSize")
      }
      Picker("Repeat incorrect answers", selection: $options.incorrectAnswerDelay) {
        ForEach(0...10, id: \.self) {
          Text($0 == 0 ? "Immediately" : "After \($0) items").tag($0)
        }
      }.accessibilityIdentifier("reviewSettings.incorrectDelay")
      Toggle("Skip kanji readings", isOn: $options.skipKanjiReadings)
        .accessibilityIdentifier("reviewSettings.skipKanjiReadings")
      Toggle("Minimize review penalty", isOn: $options.minimizePenalty)
        .accessibilityIdentifier("reviewSettings.minimizePenalty")
    } header: {
      Text("New study sessions")
    } footer: {
      Text(
        "These choices apply to new review and lesson sessions. Paused sessions keep their saved choices. Skipping kanji readings completes kanji after the meaning answer."
      )
    }
  }
}
