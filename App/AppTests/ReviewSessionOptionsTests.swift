import Foundation
import StudyCore
import Testing

@testable import Tsurukame

@MainActor enum PreferenceTestValues {
  static func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
    let domain = "usagi-legacy-preferences-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    try test(defaults)
  }
  static func archive(_ value: Any, key: String, in defaults: UserDefaults) throws {
    defaults.set(
      try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true),
      forKey: key)
  }
}

@Suite(.serialized) @MainActor
struct ReviewSessionOptionsTests {
  @Test func legacySettingsProducePortableAnkiModes() throws {
    let modes: [(AnkiModeTaskType, StudySessionOptions.AnkiMode)] = [
      (.both, .both), (.meaningOnly, .meaning), (.readingOnly, .reading),
    ]
    for enabled in [true, false] {
      for (legacy, portable) in modes {
        try PreferenceTestValues.withDefaults { defaults in
          try PreferenceTestValues.archive(enabled, key: "ankiMode", in: defaults)
          try PreferenceTestValues.archive(legacy.rawValue, key: "ankiModeTaskType", in: defaults)
          try PreferenceTestValues.archive(true, key: "ankiModeCombineReadingMeaning", in: defaults)
          let keys = ["ankiMode", "ankiModeTaskType", "ankiModeCombineReadingMeaning"]
          let before = keys.map { defaults.data(forKey: $0) }
          let source = try LegacyPreferenceImporter.read(defaults: defaults)
          try StudyPreferenceImport(defaults: defaults).apply(source, accountID: "fixture")
          let options = try JSONDecoder().decode(
            ReviewPreferences.self,
            from: #require(defaults.data(forKey: "native.reviewPreferences"))
          )
          .sessionOptions
          #expect(options.ankiMode == (enabled ? portable : .off))
          #expect(options.combinedAnki == (enabled && legacy == .both))
          #expect(keys.map { defaults.data(forKey: $0) } == before)
        }
      }
    }
  }
}

@Suite(.serialized) @MainActor struct LegacyPreferenceImportTests {
  private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
    try PreferenceTestValues.withDefaults(test)
  }
  private func archive(_ value: Any, key: String, in defaults: UserDefaults) throws {
    try PreferenceTestValues.archive(value, key: key, in: defaults)
  }
  @Test func missingSourceValuesUseOriginalDefaultsWithoutWritingArchives() throws {
    try withDefaults { defaults in
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let value = try LegacyPreferenceImporter.read(defaults: defaults)
      #expect(value == LegacyStudyPreferences())
      #expect(value.review.stageIndicator == .none && value.review.sessionOptions.minimizePenalty)
      #expect(defaults.dictionaryRepresentation() as NSDictionary == before)
    }
  }
  @Test(arguments: StudyReviewOrder.allCases)
  func originalOrderingCodesSurviveReadOnlyImportAndNativeRoundTrip(order: StudyReviewOrder) throws
  {
    try withDefaults { defaults in
      try archive(order.rawValue, key: "reviewOrder", in: defaults)
      let original = defaults.data(forKey: "reviewOrder")
      let source = try LegacyPreferenceImporter.read(defaults: defaults)
      #expect(source.review.policy.order == order)
      #expect(ReviewOrder(rawValue: order.rawValue)?.description == order.description)
      try StudyPreferenceImport(defaults: defaults).apply(source, accountID: "fixture")
      let restored = try JSONDecoder().decode(
        ReviewPreferences.self, from: #require(defaults.data(forKey: "native.reviewPreferences")))
      #expect(restored.policy.order == order)
      #expect(defaults.data(forKey: "reviewOrder") == original)
    }
  }
  @Test func everyOriginalReviewBooleanReachesItsNativePropertyWithoutRewritingTheArchive() throws {
    let fields: [(String, WritableKeyPath<ReviewPreferences, Bool>)] = [
      ("showAnswerImmediately", \.revealAnswers), ("showFullAnswer", \.revealFullAnswer),
      ("exactMatch", \.exactMatch), ("enableCheats", \.allowCorrections),
      ("allowSkippingReviews", \.allowSkipping), ("playAudioAutomatically", \.autoplayAudio),
      ("interruptBackgroundAudio", \.interruptBackgroundAudio),
      ("animateParticleExplosion", \.correctAnswerFeedback),
      ("animatePlusOne", \.completedItemFeedback), ("animateLevelUpPopup", \.srsMilestoneFeedback),
    ]
    for (key, property) in fields {
      for enabled in [false, true] {
        try withDefaults { defaults in
          try archive(enabled, key: key, in: defaults)
          let original = try #require(defaults.data(forKey: key))
          let source = try LegacyPreferenceImporter.read(defaults: defaults)
          #expect(source.review[keyPath: property] == enabled, "\(key)")
          try StudyPreferenceImport(defaults: defaults).apply(source, accountID: "fixture")
          let restored = try JSONDecoder().decode(
            ReviewPreferences.self,
            from: #require(defaults.data(forKey: "native.reviewPreferences")))
          #expect(restored[keyPath: property] == enabled, "\(key)")
          #expect(defaults.data(forKey: key) == original, "\(key)")
        }
      }
    }
  }
  @Test func actualKeyedArchivesMapEveryPreferenceGroupWithoutCopyingTheToken() throws {
    try withDefaults { defaults in
      let booleans: [String: Bool] = [
        "showAnswerImmediately": false, "exactMatch": true, "allowSkippingReviews": true,
        "groupMeaningReading": true, "meaningFirst": false, "minimizeReviewPenalty": false,
        "ankiMode": true, "ankiModeCombineReadingMeaning": true, "reviewItemsLimitEnabled": true,
        "prioritizeCurrentLevel": true, "showKanaOnlyVocab": false, "allowExcludeItems": false,
        "showAllReadings": true, "showArtwork": true, "showPreviousLevelGraph": false,
        "offlineAudio": true, "offlineAudioCellular": true, "notificationsAllReviews": true,
        "notificationsBadging": false, "notificationSounds": true,
        "subjectCatalogueViewShowAnswers": false,
        "autoSwitchKeyboard": true, "showMinutesForNextLevelUpReview": true,
      ]
      for (key, value) in booleans { try archive(value, key: key, in: defaults) }
      try archive(InterfaceStyle.dark.rawValue, key: "interfaceStyle", in: defaults)
      try archive(SRSLevelIndicatorStyle.dots.rawValue, key: "srsLevelIndicatorStyle", in: defaults)
      try archive(ReviewOrder.alternatingSRSStage.rawValue, key: "reviewOrder", in: defaults)
      try archive(AnkiModeTaskType.readingOnly.rawValue, key: "ankiModeTaskType", in: defaults)
      try archive(Float(1.75), key: "fontSize", in: defaults)
      try archive(Float(2.75), key: "leechThreshold", in: defaults)
      for (key, value) in [
        "reviewBatchSize": 8, "incorrectAnswerReturnDelay": 2, "reviewItemsLimit": 25,
        "lessonBatchSize": 9, "apprenticeLessonsLimit": 120,
      ] { try archive(value, key: key, in: defaults) }
      try archive(
        Array(LegacyPreferenceSchema.lessonOrder.defaultValue.reversed()), key: "lessonOrder",
        in: defaults)
      try archive(Set(["saved-font.ttf"]), key: "selectedFonts", in: defaults)
      try archive(Set<Int64>([1, 2]), key: "offlineAudioVoiceActors", in: defaults)
      try archive("custom@example.invalid", key: "gravatarCustomEmail", in: defaults)
      try archive("fallback@example.invalid", key: "userEmailAddress", in: defaults)
      try archive("http://localhost:8080/v2///", key: "apiBaseUrl", in: defaults)
      try archive("not-in-the-preference-payload", key: "userApiToken", in: defaults)
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let value = try LegacyPreferenceImporter.read(defaults: defaults)
      #expect(
        value.review.appearance == .dark && value.review.stageIndicator == .dots
          && value.review.fontScale == 1.75)
      #expect(!value.review.revealAnswers && value.review.exactMatch && value.review.allowSkipping)
      #expect(
        value.review.sessionOptions.ankiMode == .reading
          && !value.review.sessionOptions.combinedAnki)
      #expect(
        value.review.sessionOptions.batchSize == 8
          && value.review.sessionOptions.groupMeaningReading)
      #expect(
        !value.review.sessionOptions.meaningFirst && !value.review.sessionOptions.minimizePenalty
          && value.review.sessionOptions.incorrectAnswerDelay == 2)
      #expect(
        value.review.policy.order == .alternatingSRSStage && value.review.policy.limitEnabled
          && value.review.policy.limit == 25 && value.review.policy.leechThreshold == 2.75)
      #expect(
        value.lessons.order == [.vocabulary, .kanji, .radical] && value.lessons.batchSize == 9
          && value.lessons.prioritizeCurrentLevel)
      #expect(
        value.lessons.apprenticeLimit == 120 && !value.lessons.includeKanaVocabulary
          && !value.lessons.allowVocabularyExclusion)
      #expect(
        !value.subjects.primaryKanjiReadingsOnly && value.subjects.showArtwork
          && !value.subjects.showPreviousLevelGraph)
      #expect(
        value.fonts == ["saved-font.ttf"] && value.audio.enabled && value.audio.cellular
          && value.audio.voiceIDs == [1, 2])
      #expect(value.notifications == [.reviews, .sound] && !value.showCatalogAnswers)
      #expect(value.autoSwitchKeyboard && value.showMinutesForNextLevelUpReview)
      #expect(
        value.customAvatarEmail == "custom@example.invalid"
          && value.fallbackAvatarEmail == "fallback@example.invalid")
      #expect(value.apiBaseURL.absoluteString == "http://localhost:8080/v2")
      #expect(
        !String(decoding: try JSONEncoder().encode(value), as: UTF8.self).contains(
          "not-in-the-preference-payload"))
      #expect(defaults.dictionaryRepresentation() as NSDictionary == before)
    }
  }
  @Test func oldUnarchivedValuesAndIndicatorMigrationAreReadWithoutRewritingTheSource() throws {
    try withDefaults { defaults in
      defaults.set(true, forKey: "showSRSLevelIndicator")
      defaults.set(false, forKey: "notificationsBadging")
      defaults.set(["saved-font.ttf"], forKey: "selectedFonts")
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let value = try LegacyPreferenceImporter.read(defaults: defaults)
      #expect(value.review.stageIndicator == .name && !value.notifications.contains(.badge))
      #expect(value.fonts == ["saved-font.ttf"])
      #expect(defaults.dictionaryRepresentation() as NSDictionary == before)
    }
  }
  @Test(arguments: ["enum", "array", "bytes", "type", "class", "endpoint"])
  func malformedSourceValuesFailWithoutChangingAnySourceKey(fault: String) throws {
    try withDefaults { defaults in
      if fault == "enum" { try archive(UInt.max, key: "reviewOrder", in: defaults) }
      if fault == "array" { try archive(["not-enum-codes"], key: "lessonOrder", in: defaults) }
      if fault == "bytes" { defaults.set(Data("not-an-archive".utf8), forKey: "fontSize") }
      if fault == "type" { try archive("not-a-number", key: "fontSize", in: defaults) }
      if fault == "class" {
        try archive(NSURL(string: "https://example.invalid")!, key: "fontSize", in: defaults)
      }
      if fault == "endpoint" {
        try archive("https://user:secret@example.invalid/v2", key: "apiBaseUrl", in: defaults)
      }
      let before = defaults.dictionaryRepresentation() as NSDictionary
      #expect(throws: StudyPreferenceImportError.self) {
        try LegacyPreferenceImporter.read(defaults: defaults)
      }
      #expect(defaults.dictionaryRepresentation() as NSDictionary == before)
    }
  }
}
