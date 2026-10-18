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
  private static var booleans: [(WritableKeyPath<ReviewPreferences, Bool>, Setting<Bool>)] {
    [
      (\.revealAnswers, Settings.$showAnswerImmediately),
      (\.revealFullAnswer, Settings.$showFullAnswer),
      (\.exactMatch, Settings.$exactMatch),
      (\.allowCorrections, Settings.$enableCheats),
      (\.allowSkipping, Settings.$allowSkippingReviews),
      (\.autoplayAudio, Settings.$playAudioAutomatically),
      (\.interruptBackgroundAudio, Settings.$interruptBackgroundAudio),
      (\.correctAnswerFeedback, Settings.$animateParticleExplosion),
      (\.completedItemFeedback, Settings.$animatePlusOne),
      (\.srsMilestoneFeedback, Settings.$animateLevelUpPopup),
    ]
  }
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
    for (path, setting) in booleans { value[keyPath: path] = setting.wrappedValue }
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
    if value.fontScale != old.fontScale {
      Settings.fontSize = Float(min(2.5, max(1, value.fontScale)))
    }
    for (path, stored) in booleans where value[keyPath: path] != old[keyPath: path] {
      var setting = stored
      setting.wrappedValue = value[keyPath: path]
    }
  }
}

/// Keep the existing iPhone archive until the single-writer migration adopts native preferences.
@MainActor final class LegacyFontPreferences: StudyFontPreferences {
  var selectedFiles: Set<String> {
    get { Settings.selectedFonts }
    set { Settings.selectedFonts = newValue }
  }
}
