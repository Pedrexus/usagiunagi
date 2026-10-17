// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import StudyCore

/// Preserve archived keys and enum meanings; no user-defaults migration is needed.
enum ReviewPreferencesAdapter {
  static var current: ReviewPreferences {
    var value = ReviewPreferences()
    switch Settings.interfaceStyle {
    case .system: value.appearance = .system
    case .light: value.appearance = .light
    case .dark: value.appearance = .dark
    }
    switch Settings.srsLevelIndicatorStyle {
    case .none: value.stageIndicator = .none
    case .bubble: value.stageIndicator = .name
    case .dots: value.stageIndicator = .dots
    }
    value.fontScale = Double(Settings.fontSize)
    value.revealAnswers = Settings.showAnswerImmediately
    value.revealFullAnswer = Settings.showFullAnswer
    value.exactMatch = Settings.exactMatch
    value.allowCorrections = Settings.enableCheats
    value.allowSkipping = Settings.allowSkippingReviews
    value.autoplayAudio = Settings.playAudioAutomatically
    value.interruptBackgroundAudio = Settings.interruptBackgroundAudio
    return value
  }

  static func apply(_ value: ReviewPreferences, replacing old: ReviewPreferences) {
    if value.appearance != old.appearance {
      switch value.appearance {
      case .system: Settings.interfaceStyle = .system
      case .light: Settings.interfaceStyle = .light
      case .dark: Settings.interfaceStyle = .dark
      }
    }
    if value.stageIndicator != old.stageIndicator {
      switch value.stageIndicator {
      case .none: Settings.srsLevelIndicatorStyle = .none
      case .name: Settings.srsLevelIndicatorStyle = .bubble
      case .dots: Settings.srsLevelIndicatorStyle = .dots
      }
    }
    if value.fontScale != old.fontScale { Settings.fontSize = Float(min(2.5,
                                                                        max(1, value.fontScale))) }
    if value.revealAnswers != old
      .revealAnswers { Settings.showAnswerImmediately = value.revealAnswers }
    if value.revealFullAnswer != old
      .revealFullAnswer { Settings.showFullAnswer = value.revealFullAnswer }
    if value.exactMatch != old.exactMatch { Settings.exactMatch = value.exactMatch }
    if value.allowCorrections != old
      .allowCorrections { Settings.enableCheats = value.allowCorrections }
    if value.allowSkipping != old
      .allowSkipping { Settings.allowSkippingReviews = value.allowSkipping }
    if value.autoplayAudio != old
      .autoplayAudio { Settings.playAudioAutomatically = value.autoplayAudio }
    if value.interruptBackgroundAudio != old
      .interruptBackgroundAudio {
      Settings.interruptBackgroundAudio = value.interruptBackgroundAudio
    }
  }
}
