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
  @ArchivedPreference(Settings.$autoSwitchKeyboard) private var keyboard: Bool
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
      FullReviewSettingsContent(
        preferences: reviewBinding, fonts: fonts, offlineAudio: offlineAudio
      ) {
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
      }
    }
    .navigationTitle("Reviews")
    .onAppear { preferences = ReviewPreferencesAdapter.current }
    .alert("No Japanese keyboard", isPresented: $missingKeyboard) {
      Button("Close", role: .cancel) {}
    } message: {
      Text(
        "Add a Japanese keyboard in Settings → General → Keyboard → Keyboards → Add New Keyboard.")
    }
  }
}
