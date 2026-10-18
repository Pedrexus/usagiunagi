// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import StudyCore
import StudyUI
import SwiftUI

struct ReviewSettings: View {
  let fonts: () -> Void
  let offlineAudio: () -> Void
  let appearanceChanged: (InterfaceStyle) -> Void
  @State private var preferences = ReviewPreferencesAdapter.current
  @State private var missingKeyboard = false
  @ArchivedPreference(Settings.$reviewItemsLimitEnabled) private var limited: Bool
  @ArchivedPreference(Settings.$reviewItemsLimit) private var limit: Int
  @ArchivedPreference(Settings.$leechThreshold) private var leechThreshold: Float
  @ArchivedPreference(Settings.$reviewOrder) private var order: ReviewOrder
  @ArchivedPreference(Settings.$groupMeaningReading) private var backToBack: Bool
  @ArchivedPreference(Settings.$meaningFirst) private var meaningFirst: Bool
  @ArchivedPreference(Settings.$reviewBatchSize) private var batchSize: Int
  @ArchivedPreference(Settings.$incorrectAnswerReturnDelay) private var incorrectDelay: Int
  @ArchivedPreference(Settings.$autoSwitchKeyboard) private var keyboard: Bool
  @ArchivedPreference(Settings.$ankiMode) private var anki: Bool
  @ArchivedPreference(Settings.$ankiModeTaskType) private var ankiTasks: AnkiModeTaskType
  @ArchivedPreference(Settings.$ankiModeCombineReadingMeaning) private var combineAnki: Bool

  private var reviewBinding: Binding<ReviewPreferences> {
    Binding(
      get: { preferences },
      set: { value in
        let old = preferences
        ReviewPreferencesAdapter.apply(value, replacing: old)
        preferences = ReviewPreferencesAdapter.current
        if old.appearance != value.appearance { appearanceChanged(Settings.interfaceStyle) }
      })
  }
  var body: some View {
    Form {
      Section("Review session") {
        Toggle("Review items in batches", isOn: $limited)
          .accessibilityIdentifier("settings.reviewItemsLimitEnabled")
        if limited {
          Picker("Batch size", selection: $limit) {
            ForEach([5, 10, 15, 20, 25, 30, 50, 75, 100], id: \.self) {
              Text("\($0) reviews").tag($0)
            }
          }.accessibilityIdentifier("settings.reviewItemsLimit")
        }
        Picker("Leech threshold", selection: $leechThreshold) {
          ForEach(4...20, id: \.self) {
            let value = Float($0) / 4
            Text(value.formatted()).tag(value)
          }
        }.accessibilityIdentifier("settings.leechThreshold")
        Text(
          "A lower leech threshold includes more repeatedly missed items. The existing score is errors / correct streak¹·⁵."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Order") {
        EnumSettingPicker(title: "Order", selection: $order)
          .accessibilityIdentifier("settings.reviewOrder")
        Toggle("Back-to-back", isOn: $backToBack)
          .accessibilityIdentifier("settings.groupMeaningReading")
        if backToBack {
          Picker("Back-to-back order", selection: $meaningFirst) {
            Text("Meaning then Reading").tag(true)
            Text("Reading then Meaning").tag(false)
          }.accessibilityIdentifier("settings.meaningFirst")
        } else {
          Picker("Reviews between meaning & reading", selection: $batchSize) {
            ForEach(3...10, id: \.self) { Text("\($0) reviews").tag($0) }
          }.accessibilityIdentifier("settings.reviewBatchSize")
        }
        Picker("Repeat incorrect answers", selection: $incorrectDelay) {
          ForEach(0...10, id: \.self) {
            Text($0 == 0 ? "Immediately" : $0 == 1 ? "After 1 item" : "After \($0) items").tag($0)
          }
        }.accessibilityIdentifier("settings.incorrectAnswerReturnDelay")
      }
      ReviewSettingsContent(preferences: reviewBinding, fonts: fonts) {
        SettingToggle(
          "Show minutes for next level-up review", Settings.$showMinutesForNextLevelUpReview)
      } answers: {
        Toggle(
          "Switch to Japanese keyboard",
          isOn: Binding(
            get: { keyboard },
            set: { value in
              if value && AnswerTextField.japaneseTextInputMode == nil {
                missingKeyboard = true
              } else {
                keyboard = value
              }
            })
        ).accessibilityIdentifier("settings.autoSwitchKeyboard")
        SettingToggle(
          "Minimize review penalty", Settings.$minimizeReviewPenalty,
          help: "Count repeated errors on an item as one incorrect review")
        Toggle("Anki mode", isOn: $anki).accessibilityIdentifier("settings.ankiMode")
        if anki {
          EnumSettingPicker(title: "Anki mode applies to", selection: $ankiTasks)
            .accessibilityIdentifier("settings.ankiModeTaskType")
          if ankiTasks == .both {
            Toggle("Combine Reading + Meaning", isOn: $combineAnki)
              .accessibilityIdentifier("settings.ankiModeCombineReadingMeaning")
          }
        }
      } audio: {
        Button("Offline audio", systemImage: "arrow.down.circle", action: offlineAudio)
          .accessibilityIdentifier("settings.offlineAudio")
      }
      Section("Animations") {
        SettingToggle("Particle explosion", Settings.$animateParticleExplosion)
        SettingToggle("Level up popup", Settings.$animateLevelUpPopup)
        SettingToggle("+1", Settings.$animatePlusOne)
      }
    }
    .navigationTitle("Reviews")
    .onAppear {
      preferences = ReviewPreferencesAdapter.current
      if ankiTasks != .both { combineAnki = false }
    }
    .onChange(of: anki) { _, _ in combineAnki = false }
    .onChange(of: ankiTasks) { _, value in if value != .both { combineAnki = false } }
    .alert("No Japanese keyboard", isPresented: $missingKeyboard) {
      Button("Close", role: .cancel) {}
    } message: {
      Text(
        "Add a Japanese keyboard in Settings → General → Keyboard → Keyboards → Add New Keyboard.")
    }
  }
}
