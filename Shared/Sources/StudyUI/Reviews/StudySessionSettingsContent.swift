import StudyCore
import SwiftUI

/// Shared session controls for main and in-session settings.
struct StudySessionSettingsContent: View {
  @Binding var options: StudySessionOptions
  var body: some View {
    Section {
      Picker(
        "Answer mode",
        selection: Binding(
          get: { options.ankiMode },
          set: {
            options.ankiMode = $0
            options.combinedAnki = false
          })
      ) {
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
        "Choose how meaning and reading questions are presented. Skipping kanji readings completes kanji after the meaning answer."
      )
    }
  }
}
