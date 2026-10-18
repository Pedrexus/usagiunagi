import StudyCore
import SwiftUI

/// Shared form sections; hosts can add platform-specific controls without duplicating preferences.
public struct ReviewSettingsContent<Display: View, Answers: View, Audio: View>: View {
  @Binding private var preferences: ReviewPreferences
  private let fonts: (() -> Void)?
  private let supportsAudio: Bool
  private let display: Display
  private let answers: Answers
  private let audio: Audio

  public init(
    preferences: Binding<ReviewPreferences>, fonts: (() -> Void)? = nil,
    supportsAudio: Bool = true, @ViewBuilder display: () -> Display,
    @ViewBuilder answers: () -> Answers, @ViewBuilder audio: () -> Audio
  ) {
    _preferences = preferences
    self.fonts = fonts
    self.supportsAudio = supportsAudio
    self.display = display()
    self.answers = answers()
    self.audio = audio()
  }
  public var body: some View {
    Section("Display") {
      Picker("Appearance", selection: $preferences.appearance) {
        Text("System").tag(ReviewPreferences.Appearance.system)
        Text("Light").tag(ReviewPreferences.Appearance.light)
        Text("Dark").tag(ReviewPreferences.Appearance.dark)
      }.accessibilityIdentifier("reviewSettings.appearance")
      Picker("SRS indicator", selection: $preferences.stageIndicator) {
        Text("Off").tag(ReviewPreferences.StageIndicator.none)
        Text("Name").tag(ReviewPreferences.StageIndicator.name)
        Text("Dots").tag(ReviewPreferences.StageIndicator.dots)
      }.accessibilityIdentifier("reviewSettings.stage")
      Picker("Japanese font size", selection: $preferences.fontScale) {
        ForEach(4...10, id: \.self) { step in
          Text("\(step * 25)%").tag(Double(step) / 4)
        }
      }.accessibilityIdentifier("reviewSettings.fontSize")
      if let fonts {
        Button("Japanese fonts", systemImage: "textformat", action: fonts)
          .accessibilityIdentifier("reviewSettings.fonts")
      }
      display
    }
    Section("Answers and marking") {
      Toggle("Autoreveal answers", isOn: $preferences.revealAnswers)
        .accessibilityIdentifier("reviewSettings.autoreveal")
      Toggle("Reveal full answer", isOn: $preferences.revealFullAnswer)
        .accessibilityIdentifier("reviewSettings.fullAnswer")
      Toggle("Exact match", isOn: $preferences.exactMatch)
        .accessibilityIdentifier("reviewSettings.exactMatch")
      Toggle("Allow answer corrections", isOn: $preferences.allowCorrections)
        .accessibilityIdentifier("reviewSettings.corrections")
      Toggle("Allow skipping", isOn: $preferences.allowSkipping)
        .accessibilityIdentifier("reviewSettings.skipping")
      answers
    }
    if supportsAudio {
      Section("Audio") {
        Toggle("Autoplay audio", isOn: $preferences.autoplayAudio)
          .accessibilityIdentifier("reviewSettings.autoplay")
        Toggle("Interrupt background audio", isOn: $preferences.interruptBackgroundAudio)
          .accessibilityIdentifier("reviewSettings.interruptAudio")
        audio
      }
    }
    Section {
      Toggle("Correct answer feedback", isOn: $preferences.correctAnswerFeedback)
        .accessibilityIdentifier("reviewSettings.correctAnswerFeedback")
      Toggle("Completed item +1", isOn: $preferences.completedItemFeedback)
        .accessibilityIdentifier("reviewSettings.completedItemFeedback")
      Toggle("SRS milestone estimates", isOn: $preferences.srsMilestoneFeedback)
        .accessibilityIdentifier("reviewSettings.srsMilestoneFeedback")
    } header: {
      Text("Review feedback")
    } footer: {
      Text(
        "Uses subtle symbol effects. Reduce Motion keeps feedback still. SRS milestones are local estimates until synced."
      )
    }
  }
}
