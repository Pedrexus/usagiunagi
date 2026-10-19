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
      StudyAppearancePicker(selection: $preferences.appearance).accessibilityIdentifier(
        "reviewSettings.appearance")
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
        #if os(iOS)
          Toggle("Interrupt background audio", isOn: $preferences.interruptBackgroundAudio)
            .accessibilityIdentifier("reviewSettings.interruptAudio")
        #endif
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

/// The complete settings body on every host; narrow platform extras stay at the boundary.
public struct FullReviewSettingsContent<Display: View, Answers: View>: View {
  @Binding private var preferences: ReviewPreferences
  private let fonts: (() -> Void)?
  private let offlineAudio: (() -> Void)?
  private let display: Display
  private let answers: Answers
  public init(
    preferences: Binding<ReviewPreferences>, fonts: (() -> Void)? = nil,
    offlineAudio: (() -> Void)? = nil, @ViewBuilder display: () -> Display,
    @ViewBuilder answers: () -> Answers
  ) {
    _preferences = preferences
    self.fonts = fonts
    self.offlineAudio = offlineAudio
    self.display = display()
    self.answers = answers()
  }
  public var body: some View {
    Section {
      Toggle("Review items in batches", isOn: $preferences.policy.limitEnabled)
        .accessibilityIdentifier("settings.reviewItemsLimitEnabled")
      if preferences.policy.limitEnabled {
        Picker("Batch size", selection: $preferences.policy.limit) {
          ForEach(
            Array(Set([5, 10, 15, 20, 25, 30, 50, 75, 100, preferences.policy.normalized.limit]))
              .sorted(), id: \.self
          ) {
            Text("\($0) reviews").tag($0)
          }
        }.accessibilityIdentifier("settings.reviewItemsLimit")
      }
      Picker("Order", selection: $preferences.policy.order) {
        ForEach(StudyReviewOrder.allCases, id: \.self) { Text($0.description).tag($0) }
      }.accessibilityIdentifier("settings.reviewOrder")
    } header: {
      Text("Review session")
    } footer: {
      Text(
        "Order and batch limit apply when starting scheduled reviews. Paused queues and extra study keep their own selection."
      )
    }
    StudySessionSettingsContent(options: $preferences.sessionOptions)
    ReviewSettingsContent(
      preferences: $preferences, fonts: fonts, display: { display }, answers: { answers },
      audio: {
        if let offlineAudio {
          Button("Offline Audio", systemImage: "arrow.down.circle", action: offlineAudio)
            .accessibilityIdentifier("reviewSettings.offlineAudio")
        }
      })
    Section {
      Picker("Leech threshold", selection: $preferences.policy.leechThreshold) {
        ForEach(
          Array(
            Set((4...20).map { Double($0) / 4 } + [preferences.policy.normalized.leechThreshold])
          ).sorted(), id: \.self
        ) {
          Text($0.formatted()).tag($0)
        }
      }.accessibilityIdentifier("settings.leechThreshold")
    } header: {
      Text("Extra study")
    } footer: {
      Text(
        "A lower threshold includes more repeatedly missed items. The score is errors / correct streak¹·⁵."
      )
    }
  }
}
