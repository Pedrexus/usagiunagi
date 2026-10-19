import Foundation
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
  static var booleans: [(WritableKeyPath<ReviewPreferences, Bool>, Setting<Bool>)] {
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
  static var sessionBooleans: [(WritableKeyPath<StudySessionOptions, Bool>, Setting<Bool>)] {
    [
      (\.groupMeaningReading, Settings.$groupMeaningReading),
      (\.meaningFirst, Settings.$meaningFirst),
      (\.skipKanjiReadings, Settings.$skipKanjiReadings),
      (\.minimizePenalty, Settings.$minimizeReviewPenalty),
    ]
  }
  static var sessionIntegers: [(WritableKeyPath<StudySessionOptions, Int>, Setting<Int>)] {
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
  static var fields: [(WritableKeyPath<SubjectDetailsPreferences, Bool>, Setting<Bool>)] {
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
      for (path, stored) in Self.fields { value[keyPath: path] = stored.wrappedValue }
      return value
    }
    set {
      Settings.showAllReadings = !newValue.primaryKanjiReadingsOnly
      for (path, stored) in Self.fields {
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

/// A cold read never invokes Setting getters, which can rewrite missing/raw source values.
@MainActor enum LegacyPreferenceImporter {
  static func read(defaults: UserDefaults) throws -> LegacyStudyPreferences {
    try capture(Archive(values: defaults.dictionaryRepresentation()))
  }
  static func token(defaults: UserDefaults) throws -> String {
    try Archive(values: defaults.dictionaryRepresentation()).value(Settings.$userApiToken)
  }
  static func sourceValues(defaults: UserDefaults) throws -> (
    token: String, preferences: LegacyStudyPreferences
  ) {
    let archive = Archive(values: defaults.dictionaryRepresentation())
    return try (archive.value(Settings.$userApiToken), capture(archive))
  }
  private static func capture(_ archive: Archive) throws -> LegacyStudyPreferences {
    var result = LegacyStudyPreferences()
    result.review.appearance = try archive.value(Settings.$interfaceStyle).nativeAppearance
    switch try archive.value(Settings.$srsLevelIndicatorStyle) {
    case .none: result.review.stageIndicator = .none
    case .bubble: result.review.stageIndicator = .name
    case .dots: result.review.stageIndicator = .dots
    }
    if archive.values["showSRSLevelIndicator"] != nil,
      try archive.value(false, key: "showSRSLevelIndicator")
    {
      result.review.stageIndicator = .name
    }
    result.review.fontScale = Double(try archive.value(Settings.$fontSize))
    for (path, field) in ReviewPreferencesAdapter.booleans {
      result.review[keyPath: path] = try archive.value(field)
    }
    for (path, field) in ReviewPreferencesAdapter.sessionBooleans {
      result.review.sessionOptions[keyPath: path] = try archive.value(field)
    }
    for (path, field) in ReviewPreferencesAdapter.sessionIntegers {
      result.review.sessionOptions[keyPath: path] = try archive.value(field)
    }
    if try archive.value(Settings.$ankiMode) {
      switch try archive.value(Settings.$ankiModeTaskType) {
      case .both: result.review.sessionOptions.ankiMode = .both
      case .readingOnly: result.review.sessionOptions.ankiMode = .reading
      case .meaningOnly: result.review.sessionOptions.ankiMode = .meaning
      }
      let combined = try archive.value(Settings.$ankiModeCombineReadingMeaning)
      result.review.sessionOptions.combinedAnki =
        result.review.sessionOptions.ankiMode == .both && combined
    }
    result.review.policy.order = StudyReviewOrder(
      rawValue: try archive.value(Settings.$reviewOrder).rawValue)!
    result.review.policy.limitEnabled = try archive.value(Settings.$reviewItemsLimitEnabled)
    result.review.policy.limit = try archive.value(Settings.$reviewItemsLimit)
    result.review.policy.leechThreshold = Double(try archive.value(Settings.$leechThreshold))
    result.lessons.batchSize = try archive.value(Settings.$lessonBatchSize)
    result.lessons.prioritizeCurrentLevel = try archive.value(Settings.$prioritizeCurrentLevel)
    result.lessons.apprenticeLimit = try archive.value(Settings.$apprenticeLessonsLimit)
    result.lessons.includeKanaVocabulary = try archive.value(Settings.$showKanaOnlyVocab)
    result.lessons.allowVocabularyExclusion = try archive.value(Settings.$allowExcludeItems)
    result.lessons.order = try archive.value(Settings.$lessonOrder).compactMap {
      switch $0 {
      case .radical: SubjectKind.radical
      case .kanji: .kanji
      case .vocabulary: .vocabulary
      default: nil
      }
    }
    result.subjects.primaryKanjiReadingsOnly = try !archive.value(Settings.$showAllReadings)
    for (path, field) in LegacySubjectPreferences.fields {
      result.subjects[keyPath: path] = try archive.value(field)
    }
    result.fonts = try archive.value(Settings.$selectedFonts)
    result.audio.enabled = try archive.value(Settings.$offlineAudio)
    result.audio.cellular = try archive.value(Settings.$offlineAudioCellular)
    result.audio.voiceIDs = try archive.value(Settings.$offlineAudioVoiceActors)
    result.notifications = []
    for option in NotificationPreference.allCases
    where try archive.value(option.defaultValue, key: option.key) {
      result.notifications.insert(option)
    }
    result.customAvatarEmail = try archive.value(Settings.$gravatarCustomEmail)
    result.fallbackAvatarEmail = try archive.value(Settings.$userEmailAddress)
    result.showCatalogAnswers = try archive.value(Settings.$subjectCatalogueViewShowAnswers)
    result.autoSwitchKeyboard = try archive.value(Settings.$autoSwitchKeyboard)
    result.showMinutesForNextLevelUpReview = try archive.value(
      Settings.$showMinutesForNextLevelUpReview)
    guard
      let endpoint = DeveloperEndpoint.normalized(
        try archive.value(Settings.$apiBaseUrl),
        defaultURL: WaniKaniClient.defaultBaseURL.absoluteString),
      let url = URL(string: endpoint)
    else { throw StudyPreferenceImportError.invalidSource("apiBaseUrl") }
    result.apiBaseURL = url
    result.lessons = result.lessons.normalized
    try result.validate()
    return result
  }
  private struct Archive {
    let values: [String: Any]
    private func object(for key: String) throws -> Any? {
      guard let stored = values[key] else { return nil }
      guard let data = stored as? Data else { return stored }
      do {
        guard
          let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSString.self, NSNumber.self, NSArray.self, NSSet.self], from: data)
        else { throw StudyPreferenceImportError.invalidSource(key) }
        return decoded
      } catch { throw StudyPreferenceImportError.invalidSource(key) }
    }
    func value<Value>(_ fallback: Value, key: String) throws -> Value {
      guard let object = try object(for: key) else { return fallback }
      guard let result = object as? Value else {
        throw StudyPreferenceImportError.invalidSource(key)
      }
      return result
    }
    func value<Element>(_ field: Setting<Set<Element>>) throws -> Set<Element> {
      guard let object = try object(for: field.key) else { return field.defaultValue }
      if let set = object as? Set<Element> { return set }
      if let array = object as? [Element] { return Set(array) }
      throw StudyPreferenceImportError.invalidSource(field.key)
    }
    func value<Value>(_ field: Setting<Value>) throws -> Value {
      try value(field.defaultValue, key: field.key)
    }
    func value<Value>(_ field: EnumSetting<Value>) throws -> Value {
      guard let result = Value(rawValue: try value(field.defaultValue.rawValue, key: field.key))
      else { throw StudyPreferenceImportError.invalidSource(field.key) }
      return result
    }
    func value<Value>(_ field: EnumArraySetting<Value>) throws -> [Value] {
      try value(field.defaultValue, key: field.key).map {
        guard let result = Value(rawValue: $0) else {
          throw StudyPreferenceImportError.invalidSource(field.key)
        }
        return result
      }
    }
  }
}
