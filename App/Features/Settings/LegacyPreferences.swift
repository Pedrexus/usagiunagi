import StudyCore
import WaniKaniAPI

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
  static var currentSessionOptions: StudySessionOptions {
    var value = StudySessionOptions()
    if Settings.ankiMode {
      switch Settings.ankiModeTaskType {
      case .both: value.ankiMode = .both
      case .meaningOnly: value.ankiMode = .meaning
      case .readingOnly: value.ankiMode = .reading
      }
    }
    value.batchSize = Settings.reviewBatchSize
    value.groupMeaningReading = Settings.groupMeaningReading
    value.combinedAnki =
      Settings.ankiMode && Settings.ankiModeCombineReadingMeaning
      && Settings
        .ankiModeTaskType == .both
    value.meaningFirst = Settings.meaningFirst
    value.incorrectAnswerDelay = Settings.incorrectAnswerReturnDelay
    value.skipKanjiReadings = Settings.skipKanjiReadings
    value.minimizePenalty = Settings.minimizeReviewPenalty
    return value
  }
  private static var sessionBooleans: [(WritableKeyPath<StudySessionOptions, Bool>, Setting<Bool>)]
  {
    [
      (\.groupMeaningReading, Settings.$groupMeaningReading),
      (\.meaningFirst, Settings.$meaningFirst),
      (\.skipKanjiReadings, Settings.$skipKanjiReadings),
      (\.minimizePenalty, Settings.$minimizeReviewPenalty),
    ]
  }
  private static var sessionIntegers: [(WritableKeyPath<StudySessionOptions, Int>, Setting<Int>)] {
    [
      (\.batchSize, Settings.$reviewBatchSize),
      (\.incorrectAnswerDelay, Settings.$incorrectAnswerReturnDelay),
    ]
  }
  static var currentPolicy: StudyReviewPolicy {
    var value = StudyReviewPolicy()
    value.order = StudyReviewOrder(rawValue: Settings.reviewOrder.rawValue)!
    value.limitEnabled = Settings.reviewItemsLimitEnabled
    value.limit = Settings.reviewItemsLimit
    value.leechThreshold = Double(Settings.leechThreshold)
    return value.normalized
  }
  static var current: ReviewPreferences {
    var value = ReviewPreferences()
    value.sessionOptions = currentSessionOptions
    value.policy = currentPolicy
    value.appearance = Settings.interfaceStyle.nativeAppearance
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
    if value.policy.order != old.policy.order {
      Settings.reviewOrder = ReviewOrder(rawValue: value.policy.order.rawValue)!
    }
    if value.policy.limitEnabled != old.policy.limitEnabled {
      Settings.reviewItemsLimitEnabled = value.policy.limitEnabled
    }
    if value.policy.limit != old.policy.limit {
      Settings.reviewItemsLimit = value.policy.normalized.limit
    }
    if value.policy.leechThreshold != old.policy.leechThreshold {
      Settings.leechThreshold = Float(value.policy.normalized.leechThreshold)
    }
    let options = value.sessionOptions
    let previous = old.sessionOptions
    if options.ankiMode != previous.ankiMode {
      Settings.ankiMode = options.ankiMode != .off
      switch options.ankiMode {
      case .both: Settings.ankiModeTaskType = .both
      case .reading: Settings.ankiModeTaskType = .readingOnly
      case .meaning: Settings.ankiModeTaskType = .meaningOnly
      case .off: break  // Preserve the archived task preference while Anki is disabled.
      }
    }
    if options.combinedAnki != previous.combinedAnki || options.ankiMode != previous.ankiMode {
      Settings.ankiModeCombineReadingMeaning = options.ankiMode == .both && options.combinedAnki
    }
    for (path, stored) in sessionBooleans where options[keyPath: path] != previous[keyPath: path] {
      var setting = stored
      setting.wrappedValue = options[keyPath: path]
    }
    for (path, stored) in sessionIntegers where options[keyPath: path] != previous[keyPath: path] {
      var setting = stored
      setting.wrappedValue = options[keyPath: path]
    }
    if value.appearance != old.appearance {

      Settings.interfaceStyle = InterfaceStyle(value.appearance)
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

/// Keep the original iPhone archives while native audio uses the shared typed owner.
@MainActor final class LegacyAudioPreferences: StudyAudioPreferences {
  var options: StudyAudioOptions {
    get {
      var value = StudyAudioOptions()
      value.enabled = Settings.offlineAudio
      value.cellular = Settings.offlineAudioCellular
      value.voiceIDs = Settings.offlineAudioVoiceActors
      return value
    }
    set {
      Settings.offlineAudio = newValue.enabled
      Settings.offlineAudioCellular = newValue.cellular
      Settings.offlineAudioVoiceActors = newValue.voiceIDs

    }
  }
}

@MainActor final class LegacyLessonPreferences: StudyLessonPreferenceStore {
  var value: StudyLessonPreferences {
    get {
      var value = StudyLessonPreferences()
      value.batchSize = Settings.lessonBatchSize
      value.prioritizeCurrentLevel = Settings.prioritizeCurrentLevel
      value.apprenticeLimit = Settings.apprenticeLessonsLimit
      value.includeKanaVocabulary = Settings.showKanaOnlyVocab
      value.allowVocabularyExclusion = Settings.allowExcludeItems
      value.order = Settings.lessonOrder.compactMap { kind in
        switch kind {
        case .radical: .radical
        case .kanji: .kanji
        case .vocabulary: .vocabulary
        default: nil
        }
      }
      return value.normalized
    }
    set {
      let value = newValue.normalized
      Settings.lessonBatchSize = value.batchSize
      Settings.prioritizeCurrentLevel = value.prioritizeCurrentLevel
      Settings.apprenticeLessonsLimit = value.apprenticeLimit
      Settings.showKanaOnlyVocab = value.includeKanaVocabulary
      Settings.allowExcludeItems = value.allowVocabularyExclusion
      Settings.lessonOrder = value.order.map { kind in
        switch kind {
        case .radical: .radical
        case .kanji: .kanji
        case .vocabulary: .vocabulary
        }
      }
    }
  }
}

/// The same display policy, backed by the original archived iOS keys until writer handoff.
@MainActor final class LegacySubjectPreferences: StudySubjectPreferenceStore {
  private var fields: [(WritableKeyPath<SubjectDetailsPreferences, Bool>, Setting<Bool>)] {
    [
      (\.useKatakanaForOnyomi, Settings.$useKatakanaForOnyomi),
      (\.showDeprecatedMnemonic, Settings.$showOldMnemonic),
      (\.blurTranslations, Settings.$blurContextSentences),
      (\.showStatistics, Settings.$showStatsSection), (\.showArtwork, Settings.$showArtwork),
      (\.showPreviousLevelGraph, Settings.$showPreviousLevelGraph),
      (\.showSimilarKanjiAboveCurrentLevel, Settings.$showSimilarKanjiAboveLevel),
    ]
  }
  var value: SubjectDetailsPreferences {
    get {
      var value = SubjectDetailsPreferences()
      value.primaryKanjiReadingsOnly = !Settings.showAllReadings
      for (path, stored) in fields { value[keyPath: path] = stored.wrappedValue }
      return value
    }
    set {
      Settings.showAllReadings = !newValue.primaryKanjiReadingsOnly
      for (path, stored) in fields {
        var setting = stored
        setting.wrappedValue = newValue[keyPath: path]
      }
    }
  }
}

/// Keep archived iOS notification keys until the native writer/preference handoff.
@MainActor final class LegacyNotificationPreferences: StudyNotificationPreferences {
  func value(for option: NotificationPreference) -> Bool {
    Setting(option.defaultValue, option.key).wrappedValue
  }
  func set(_ value: Bool, for option: NotificationPreference) {
    var setting = Setting(option.defaultValue, option.key)
    setting.wrappedValue = value
  }
}

extension InterfaceStyle {
  var nativeAppearance: ReviewPreferences.Appearance {
    switch self {
    case .system: .system
    case .light: .light
    case .dark: .dark
    }
  }
  init(_ appearance: ReviewPreferences.Appearance) {
    switch appearance {
    case .system: self = .system
    case .light: self = .light
    case .dark: self = .dark
    }
  }
}
