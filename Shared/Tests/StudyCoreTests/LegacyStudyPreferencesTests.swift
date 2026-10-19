import Foundation
import StudyCore
import Testing

@MainActor struct LegacyStudyPreferencesTests {
  private func defaults(_ test: (UserDefaults) throws -> Void) throws {
    let domain = "usagi-preferences-" + UUID().uuidString
    let values = try #require(UserDefaults(suiteName: domain))
    defer { values.removePersistentDomain(forName: domain) }
    try test(values)
  }
  @Test func originalDefaultsAndEveryOwnerReceiveTheTypedChoices() throws {
    try defaults { values in
      var source = LegacyStudyPreferences()
      source.lessons.order = [.vocabulary, .radical, .kanji]
      source.lessons.batchSize = 7
      source.lessons.prioritizeCurrentLevel = true
      source.subjects.showArtwork = true
      source.subjects.blurTranslations = false
      source.fonts = ["saved-font.ttf"]
      source.audio.enabled = true
      source.audio.cellular = true
      source.audio.voiceIDs = [2, 1]
      source.notifications = [.reviews, .sound]
      source.fallbackAvatarEmail = "original@example.invalid"
      source.showCatalogAnswers = false
      source.autoSwitchKeyboard = true
      source.showMinutesForNextLevelUpReview = true
      source.apiBaseURL = URL(string: "http://localhost:8080/v2")!
      try StudyPreferenceImport(defaults: values).apply(source, accountID: "verified")
      let review = try JSONDecoder().decode(
        ReviewPreferences.self, from: #require(values.data(forKey: "native.reviewPreferences")))
      #expect(
        review == source.review && review.stageIndicator == .none
          && review.sessionOptions.minimizePenalty)
      #expect(DefaultsStudyLessonPreferences(defaults: values).value == source.lessons)
      #expect(DefaultsStudySubjectPreferences(defaults: values).value == source.subjects)
      #expect(DefaultsStudyFontPreferences(defaults: values).selectedFiles == source.fonts)
      #expect(DefaultsStudyAudioPreferences(defaults: values).options == source.audio)
      let notices = DefaultsStudyNotificationPreferences(defaults: values)
      #expect(
        Set(NotificationPreference.allCases.filter { notices.value(for: $0) })
          == source.notifications)
      #expect(
        !values.bool(forKey: "catalog.showAnswers")
          && values.bool(forKey: "native.autoSwitchKeyboard"))
      #expect(values.bool(forKey: "native.showMinutesForNextLevelUpReview"))
      #expect(values.string(forKey: "native.apiBaseUrl") == source.apiBaseURL.absoluteString)
    }
  }
  @Test func existingValuesAndLaterEditsWinWhenTheReceiptIsAppliedAgain() throws {
    try defaults { values in
      values.set(false, forKey: "native.notificationsBadging")
      values.set("explicit@example.invalid", forKey: "native.gravatarCustomEmail")
      values.set("unrelated", forKey: "unrelated")
      let importer = StudyPreferenceImport(defaults: values)
      let source = LegacyStudyPreferences()
      try importer.apply(source, accountID: "verified")
      var changed = source.review
      changed.exactMatch = true
      changed.fontScale = 2
      let bytes = try JSONEncoder().encode(changed)
      values.set(bytes, forKey: "native.reviewPreferences")
      try importer.apply(source, accountID: "verified")
      #expect(values.data(forKey: "native.reviewPreferences") == bytes)
      #expect(!values.bool(forKey: "native.notificationsBadging"))
      #expect(values.string(forKey: "native.gravatarCustomEmail") == "explicit@example.invalid")
      #expect(values.string(forKey: "unrelated") == "unrelated")
    }
  }
  @Test func avatarFallbacksAreAccountBoundAndDoNotReplaceAnExplicitAddress() throws {
    try defaults { values in
      var first = LegacyStudyPreferences()
      first.fallbackAvatarEmail = "one@example.invalid"
      var second = first
      second.fallbackAvatarEmail = "two@example.invalid"
      let importer = StudyPreferenceImport(defaults: values)
      try importer.apply(first, accountID: "one")
      try importer.apply(second, accountID: "two")
      let data = try #require(values.data(forKey: "native.avatarFallbacks"))
      #expect(
        StudyAvatar.email(custom: "", fallbacks: data, accountID: "one")
          == first.fallbackAvatarEmail)
      #expect(
        StudyAvatar.email(custom: "", fallbacks: data, accountID: "two")
          == second.fallbackAvatarEmail)
      #expect(StudyAvatar.email(custom: "", fallbacks: data, accountID: "other").isEmpty)
      #expect(
        StudyAvatar.email(custom: "override@example.invalid", fallbacks: data, accountID: "one")
          == "override@example.invalid")
    }
  }
  @Test(arguments: ["threshold", "size", "endpoint", "voices"])
  func invalidSnapshotsDoNotWriteNativeValues(fault: String) throws {
    try defaults { values in
      var source = LegacyStudyPreferences()
      if fault == "threshold" { source.review.policy.leechThreshold = .nan }
      if fault == "size" { source.review.fontScale = .infinity }
      if fault == "endpoint" {
        source.apiBaseURL = URL(string: "https://user:secret@example.invalid/v2")!
      }
      if fault == "voices" { source.audio.voiceIDs = [-1] }
      #expect(throws: StudyPreferenceImportError.self) {
        try StudyPreferenceImport(defaults: values).apply(source, accountID: "verified")
      }
      #expect(!values.dictionaryRepresentation().keys.contains { $0.hasPrefix("native.") })
    }
  }
  @Test func existingMalformedNativeDataIsKeptForRecovery() throws {
    try defaults { values in
      let original = Data("malformed-native-setting".utf8)
      values.set(original, forKey: "native.reviewPreferences")
      #expect(throws: StudyPreferenceImportError.self) {
        try StudyPreferenceImport(defaults: values).apply(.init(), accountID: "verified")
      }
      #expect(values.data(forKey: "native.reviewPreferences") == original)
    }
  }
  @Test func mediaPathsRetainOriginalFilesAndNativeDefaultsKeepTheirOwnLocation() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let documents = root.appending(path: "documents")
    let native = root.appending(path: "native")
    let legacy = StudyMediaLayout.legacyDocuments.directories(
      nativeRoot: native, documents: documents)
    try FileManager.default.createDirectory(at: legacy.audio, withIntermediateDirectories: true)
    let original = legacy.audio.appending(path: "a42-2.mp3")
    let bytes = Data("disposable-cache-identity".utf8)
    try bytes.write(to: original)
    let downloads = StudyAudioDownloads(directory: legacy.audio)
    #expect(
      downloads.cacheURL(subjectID: 42, voiceActorID: 2) == original
        && downloads.isCached(subjectID: 42, voiceActorID: 2))
    #expect(
      try Data(contentsOf: original) == bytes && legacy.fonts == documents.appending(path: "fonts"))
    #expect(
      StudyMediaLayout.native.directories(nativeRoot: native, documents: documents).audio
        == native.appending(path: "audio"))
  }
}
