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

/// Decode a captured archive without invoking live getters or changing any source value.
@MainActor enum LegacyPreferenceImporter {
  static func read(defaults: UserDefaults) throws -> LegacyStudyPreferences {
    try capture(Archive(values: defaults.dictionaryRepresentation()))
  }
  static func token(defaults: UserDefaults) throws -> String {
    try Archive(values: defaults.dictionaryRepresentation()).value(
      LegacyPreferenceSchema.userApiToken)
  }
  static func sourceValues(defaults: UserDefaults) throws -> (
    token: String, preferences: LegacyStudyPreferences
  ) {
    let archive = Archive(values: defaults.dictionaryRepresentation())
    return try (archive.value(LegacyPreferenceSchema.userApiToken), capture(archive))
  }
  private static func capture(_ archive: Archive) throws -> LegacyStudyPreferences {
    var result = LegacyStudyPreferences()
    result.review.appearance = try archive.value(LegacyPreferenceSchema.interfaceStyle)
      .nativeAppearance
    switch try archive.value(LegacyPreferenceSchema.srsLevelIndicatorStyle) {
    case .none: result.review.stageIndicator = .none
    case .bubble: result.review.stageIndicator = .name
    case .dots: result.review.stageIndicator = .dots
    }
    if archive.values[LegacyPreferenceSchema.showSRSLevelIndicator.key] != nil,
      try archive.value(LegacyPreferenceSchema.showSRSLevelIndicator)
    {
      result.review.stageIndicator = .name
    }
    result.review.fontScale = Double(try archive.value(LegacyPreferenceSchema.fontSize))
    for (path, field) in LegacyPreferenceSchema.reviewBooleans {
      result.review[keyPath: path] = try archive.value(field)
    }
    for (path, field) in LegacyPreferenceSchema.sessionBooleans {
      result.review.sessionOptions[keyPath: path] = try archive.value(field)
    }
    for (path, field) in LegacyPreferenceSchema.sessionIntegers {
      result.review.sessionOptions[keyPath: path] = try archive.value(field)
    }
    if try archive.value(LegacyPreferenceSchema.ankiMode) {
      switch try archive.value(LegacyPreferenceSchema.ankiModeTaskType) {
      case .both: result.review.sessionOptions.ankiMode = .both
      case .readingOnly: result.review.sessionOptions.ankiMode = .reading
      case .meaningOnly: result.review.sessionOptions.ankiMode = .meaning
      }
      let combined = try archive.value(LegacyPreferenceSchema.ankiModeCombineReadingMeaning)
      result.review.sessionOptions.combinedAnki =
        result.review.sessionOptions.ankiMode == .both && combined
    }
    result.review.policy.order = StudyReviewOrder(
      rawValue: try archive.value(LegacyPreferenceSchema.reviewOrder).rawValue)!
    result.review.policy.limitEnabled = try archive.value(
      LegacyPreferenceSchema.reviewItemsLimitEnabled)
    result.review.policy.limit = try archive.value(LegacyPreferenceSchema.reviewItemsLimit)
    result.review.policy.leechThreshold = Double(
      try archive.value(LegacyPreferenceSchema.leechThreshold))
    result.lessons.batchSize = try archive.value(LegacyPreferenceSchema.lessonBatchSize)
    result.lessons.prioritizeCurrentLevel = try archive.value(
      LegacyPreferenceSchema.prioritizeCurrentLevel)
    result.lessons.apprenticeLimit = try archive.value(
      LegacyPreferenceSchema.apprenticeLessonsLimit)
    result.lessons.includeKanaVocabulary = try archive.value(
      LegacyPreferenceSchema.showKanaOnlyVocab)
    result.lessons.allowVocabularyExclusion = try archive.value(
      LegacyPreferenceSchema.allowExcludeItems)
    result.lessons.order = try archive.value(LegacyPreferenceSchema.lessonOrder).compactMap {
      switch $0 {
      case 1: SubjectKind.radical
      case 2: .kanji
      case 3: .vocabulary
      default: nil
      }
    }
    result.subjects.primaryKanjiReadingsOnly = try !archive.value(
      LegacyPreferenceSchema.showAllReadings)
    for (path, field) in LegacyPreferenceSchema.subjectBooleans {
      result.subjects[keyPath: path] = try archive.value(field)
    }
    result.fonts = try archive.value(LegacyPreferenceSchema.selectedFonts)
    result.audio.enabled = try archive.value(LegacyPreferenceSchema.offlineAudio)
    result.audio.cellular = try archive.value(LegacyPreferenceSchema.offlineAudioCellular)
    result.audio.voiceIDs = try archive.value(LegacyPreferenceSchema.offlineAudioVoiceActors)
    result.notifications = []
    for option in NotificationPreference.allCases
    where try archive.value(option.defaultValue, key: option.key) {
      result.notifications.insert(option)
    }
    result.customAvatarEmail = try archive.value(LegacyPreferenceSchema.gravatarCustomEmail)
    result.fallbackAvatarEmail = try archive.value(LegacyPreferenceSchema.userEmailAddress)
    result.showCatalogAnswers = try archive.value(
      LegacyPreferenceSchema.subjectCatalogueViewShowAnswers)
    result.autoSwitchKeyboard = try archive.value(LegacyPreferenceSchema.autoSwitchKeyboard)
    result.showMinutesForNextLevelUpReview = try archive.value(
      LegacyPreferenceSchema.showMinutesForNextLevelUpReview)
    guard
      let endpoint = DeveloperEndpoint.normalized(
        try archive.value(LegacyPreferenceSchema.apiBaseUrl),
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
    func value<Element>(_ field: LegacyPreferenceField<Set<Element>>) throws -> Set<Element> {
      guard let object = try object(for: field.key) else { return field.defaultValue }
      if let set = object as? Set<Element> { return set }
      if let array = object as? [Element] { return Set(array) }
      throw StudyPreferenceImportError.invalidSource(field.key)
    }
    func value<Value>(_ field: LegacyPreferenceField<Value>) throws -> Value {
      try value(field.defaultValue, key: field.key)
    }
    func value<Value: RawRepresentable>(_ field: LegacyPreferenceField<Value>) throws -> Value {
      guard let result = Value(rawValue: try value(field.defaultValue.rawValue, key: field.key))
      else { throw StudyPreferenceImportError.invalidSource(field.key) }
      return result
    }
  }
}
