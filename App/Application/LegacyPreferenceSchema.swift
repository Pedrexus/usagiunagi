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

import Foundation
import StudyCore

typealias SettingEnum = CaseIterable & Codable & CustomStringConvertible & RawRepresentable
  & Sendable

enum ReviewOrder: UInt, SettingEnum {
  case random = 1
  case ascendingSRSStage = 2
  case descendingSRSStage = 7
  case alternatingSRSStage = 9
  case currentLevelFirst = 3
  case lowestLevelFirst = 4
  case newestAvailableFirst = 5
  case oldestAvailableFirst = 6
  case longestRelativeWait = 8

  var description: String { StudyReviewOrder(rawValue: rawValue)!.description }
}

enum InterfaceStyle: UInt, SettingEnum {
  case system = 1
  case light = 2
  case dark = 3

  var description: String {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }
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

enum AnkiModeTaskType: UInt, SettingEnum {
  case both = 1
  case readingOnly = 2
  case meaningOnly = 3

  var description: String {
    switch self {
    case .both: return "Both"
    case .readingOnly: return "Reading only"
    case .meaningOnly: return "Meaning only"
    }
  }
}

enum SRSLevelIndicatorStyle: UInt, SettingEnum {
  case none = 1
  case bubble = 2
  case dots = 3

  var description: String {
    switch self {
    case .none: return "None"
    case .bubble: return "Bubble"
    case .dots: return "Dots"
    }
  }
}

/// Metadata only: reading a field cannot initialize, migrate or rewrite UserDefaults.
struct LegacyPreferenceField<Value> {
  let defaultValue: Value
  let key: String
  init(_ defaultValue: Value, _ key: String) {
    self.defaultValue = defaultValue
    self.key = key
  }
}
extension LegacyPreferenceField: Sendable where Value: Sendable {}

enum LegacyPreferenceSchema {
  static let userEmailAddress = LegacyPreferenceField("", "userEmailAddress")
  static let userApiToken = LegacyPreferenceField("", "userApiToken")
  static let apiBaseUrl = LegacyPreferenceField(
    WaniKaniClient.defaultBaseURL.absoluteString, "apiBaseUrl")
  static let interfaceStyle = LegacyPreferenceField(InterfaceStyle.system, "interfaceStyle")
  static let notificationsAllReviews = LegacyPreferenceField(false, "notificationsAllReviews")
  static let notificationsBadging = LegacyPreferenceField(true, "notificationsBadging")
  static let notificationSounds = LegacyPreferenceField(false, "notificationSounds")
  static let prioritizeCurrentLevel = LegacyPreferenceField(false, "prioritizeCurrentLevel")
  // Original protobuf codes; unknown future codes are ignored by the native subject-kind projection.
  static let lessonOrder = LegacyPreferenceField([1, 2, 3], "lessonOrder")
  static let lessonBatchSize = LegacyPreferenceField(5, "lessonBatchSize")
  static let showStatsSection = LegacyPreferenceField(true, "showStatsSection")
  static let showArtwork = LegacyPreferenceField(false, "showArtwork")
  static let reviewOrder = LegacyPreferenceField(ReviewOrder.random, "reviewOrder")
  static let reviewBatchSize = LegacyPreferenceField(5, "reviewBatchSize")
  static let incorrectAnswerReturnDelay = LegacyPreferenceField(5, "incorrectAnswerReturnDelay")
  static let reviewItemsLimit = LegacyPreferenceField(15, "reviewItemsLimit")
  static let apprenticeLessonsLimit = LegacyPreferenceField(Int.max, "apprenticeLessonsLimit")
  static let groupMeaningReading = LegacyPreferenceField(false, "groupMeaningReading")
  static let reviewItemsLimitEnabled = LegacyPreferenceField(false, "reviewItemsLimitEnabled")
  static let meaningFirst = LegacyPreferenceField(true, "meaningFirst")
  static let showAnswerImmediately = LegacyPreferenceField(true, "showAnswerImmediately")
  static let showFullAnswer = LegacyPreferenceField(false, "showFullAnswer")
  static let selectedFonts = LegacyPreferenceField(Set<String>(), "selectedFonts")
  static let fontSize = LegacyPreferenceField<Float>(1.0, "fontSize")
  static let exactMatch = LegacyPreferenceField(false, "exactMatch")
  static let enableCheats = LegacyPreferenceField(true, "enableCheats")
  static let skipKanjiReadings = LegacyPreferenceField(false, "skipKanjiReadings")
  static let showOldMnemonic = LegacyPreferenceField(true, "showOldMnemonic")
  static let blurContextSentences = LegacyPreferenceField(true, "blurContextSentences")
  static let useKatakanaForOnyomi = LegacyPreferenceField(false, "useKatakanaForOnyomi")
  static let srsLevelIndicatorStyle = LegacyPreferenceField(
    SRSLevelIndicatorStyle.none, "srsLevelIndicatorStyle")
  static let showSRSLevelIndicator = LegacyPreferenceField(false, "showSRSLevelIndicator")
  static let showMinutesForNextLevelUpReview = LegacyPreferenceField(
    false, "showMinutesForNextLevelUpReview")
  static let showAllReadings = LegacyPreferenceField(false, "showAllReadings")
  static let autoSwitchKeyboard = LegacyPreferenceField(false, "autoSwitchKeyboard")
  static let allowSkippingReviews = LegacyPreferenceField(false, "allowSkippingReviews")
  static let minimizeReviewPenalty = LegacyPreferenceField(true, "minimizeReviewPenalty")
  static let ankiMode = LegacyPreferenceField(false, "ankiMode")
  static let ankiModeTaskType = LegacyPreferenceField(AnkiModeTaskType.both, "ankiModeTaskType")
  static let ankiModeCombineReadingMeaning = LegacyPreferenceField(
    false, "ankiModeCombineReadingMeaning")
  static let showPreviousLevelGraph = LegacyPreferenceField(true, "showPreviousLevelGraph")
  static let showKanaOnlyVocab = LegacyPreferenceField(true, "showKanaOnlyVocab")
  static let showSimilarKanjiAboveLevel = LegacyPreferenceField(false, "showSimilarKanjiAboveLevel")
  static let leechThreshold = LegacyPreferenceField<Float>(1.0, "leechThreshold")
  static let seenFullAnswerPrompt = LegacyPreferenceField(false, "seenFullAnswerPrompt")
  static let playAudioAutomatically = LegacyPreferenceField(false, "playAudioAutomatically")
  static let interruptBackgroundAudio = LegacyPreferenceField(false, "interruptBackgroundAudio")
  static let offlineAudio = LegacyPreferenceField(false, "offlineAudio")
  static let offlineAudioCellular = LegacyPreferenceField(false, "offlineAudioCellular")
  static let offlineAudioVoiceActors = LegacyPreferenceField(
    Set<Int64>(), "offlineAudioVoiceActors")
  static let gravatarCustomEmail = LegacyPreferenceField("", "gravatarCustomEmail")
  static let animateParticleExplosion = LegacyPreferenceField(true, "animateParticleExplosion")
  static let animateLevelUpPopup = LegacyPreferenceField(true, "animateLevelUpPopup")
  static let animatePlusOne = LegacyPreferenceField(true, "animatePlusOne")
  static let subjectCatalogueViewShowAnswers = LegacyPreferenceField(
    true, "subjectCatalogueViewShowAnswers")
  static let allowExcludeItems = LegacyPreferenceField(true, "allowExcludeItems")

  static var reviewBooleans:
    [(WritableKeyPath<ReviewPreferences, Bool>, LegacyPreferenceField<Bool>)]
  {
    [
      (\.revealAnswers, showAnswerImmediately), (\.revealFullAnswer, showFullAnswer),
      (\.exactMatch, exactMatch), (\.allowCorrections, enableCheats),
      (\.allowSkipping, allowSkippingReviews), (\.autoplayAudio, playAudioAutomatically),
      (\.interruptBackgroundAudio, interruptBackgroundAudio),
      (\.correctAnswerFeedback, animateParticleExplosion),
      (\.completedItemFeedback, animatePlusOne),
      (\.srsMilestoneFeedback, animateLevelUpPopup),
    ]
  }
  static var sessionBooleans:
    [(WritableKeyPath<StudySessionOptions, Bool>, LegacyPreferenceField<Bool>)]
  {
    [
      (\.groupMeaningReading, groupMeaningReading), (\.meaningFirst, meaningFirst),
      (\.skipKanjiReadings, skipKanjiReadings), (\.minimizePenalty, minimizeReviewPenalty),
    ]
  }
  static var sessionIntegers:
    [(WritableKeyPath<StudySessionOptions, Int>, LegacyPreferenceField<Int>)]
  {
    [(\.batchSize, reviewBatchSize), (\.incorrectAnswerDelay, incorrectAnswerReturnDelay)]
  }
  static var subjectBooleans:
    [(WritableKeyPath<SubjectDetailsPreferences, Bool>, LegacyPreferenceField<Bool>)]
  {
    [
      (\.useKatakanaForOnyomi, useKatakanaForOnyomi), (\.showDeprecatedMnemonic, showOldMnemonic),
      (\.blurTranslations, blurContextSentences), (\.showStatistics, showStatsSection),
      (\.showArtwork, showArtwork), (\.showPreviousLevelGraph, showPreviousLevelGraph),
      (\.showSimilarKanjiAboveCurrentLevel, showSimilarKanjiAboveLevel),
    ]
  }
}
