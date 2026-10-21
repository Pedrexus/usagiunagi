import StudyCore
import SwiftUI

/// Shared preference sections for main and in-session settings.
struct ReviewSettingsContent<Display: View, Answers: View, Audio: View>: View {
  @Environment(\.studyICloudPreferences) private var iCloud
  private var waniKaniSources = StudyWaniKaniSources()
  @Environment(\.waniKaniPreferences) private var waniKaniPreferences
  @Binding var preferences: ReviewPreferences
  var fonts: (() -> Void)? = nil
  @ViewBuilder let display: Display
  @ViewBuilder let answers: Answers
  @ViewBuilder let audio: Audio

  var body: some View {
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
    Section("Audio") {
      Toggle(
        "Use WaniKani audio settings",
        isOn: waniKaniSources.$audio.syncing(.waniKaniAudio, with: iCloud))
      if !waniKaniSources.audio {
        Toggle("Autoplay audio", isOn: $preferences.autoplayAudio)
          .accessibilityIdentifier("reviewSettings.autoplay")
      } else {
        Text(
          waniKaniPreferences == nil
            ? "Using local audio settings until WaniKani settings are available."
            : "Lessons, reviews and Extra Study use their separate WaniKani audio settings."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      #if os(iOS)
        Toggle("Interrupt background audio", isOn: $preferences.interruptBackgroundAudio)
          .accessibilityIdentifier("reviewSettings.interruptAudio")
      #endif
      audio
    }
    Section {
      Toggle("Correct answer feedback", isOn: $preferences.correctAnswerFeedback)
        .accessibilityIdentifier("reviewSettings.correctAnswerFeedback")
      Toggle("Completed item +1", isOn: $preferences.completedItemFeedback)
        .accessibilityIdentifier("reviewSettings.completedItemFeedback")
      Toggle(
        "Use WaniKani SRS feedback",
        isOn: waniKaniSources.$srsFeedback.syncing(.waniKaniSrsFeedback, with: iCloud))
      if waniKaniSources.srsFeedback {
        if let waniKaniPreferences {
          LabeledContent(
            "Scheduled review SRS changes",
            value: waniKaniPreferences.reviewsDisplaySrsIndicator ? "On" : "Off")
        }
        Text(
          "Scheduled reviews follow WaniKani when available. Lessons and Extra Study use the estimate choice below."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
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
struct FullReviewSettingsContent<Display: View, Answers: View>: View {
  @Environment(\.studyICloudPreferences) private var iCloud
  private var waniKaniSources = StudyWaniKaniSources()
  @Environment(\.waniKaniPreferences) private var waniKaniPreferences
  @Binding var preferences: ReviewPreferences
  var fonts: (() -> Void)? = nil
  var offlineAudio: (() -> Void)? = nil
  @ViewBuilder let display: Display
  @ViewBuilder let answers: Answers
  var body: some View {
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
      Toggle(
        "Use WaniKani review order",
        isOn: waniKaniSources.$reviewOrder.syncing(.waniKaniReviewOrder, with: iCloud))
      if waniKaniSources.reviewOrder {
        LabeledContent(
          "Order",
          value: preferences.reviewPolicy(
            waniKani: waniKaniPreferences, followWaniKani: waniKaniSources.reviewOrder
          ).order.description)
        if waniKaniPreferences == nil || waniKaniPreferences?.reviewOrder == nil {
          Text("Using the local order until a supported WaniKani order is available.").font(
            .caption
          ).foregroundStyle(.secondary)
        }
      } else {
        Picker("Order", selection: $preferences.policy.order) {
          ForEach(StudyReviewOrder.allCases, id: \.self) { Text($0.description).tag($0) }
        }.accessibilityIdentifier("settings.reviewOrder")
      }
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
