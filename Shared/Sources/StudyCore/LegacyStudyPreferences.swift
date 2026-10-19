import Foundation

/// Effective original-app choices; tokens and database contents never belong in this value.
public struct LegacyStudyPreferences: Codable, Equatable, Sendable {
  public var review = ReviewPreferences()
  public var lessons = StudyLessonPreferences()
  public var subjects = SubjectDetailsPreferences()
  public var fonts: Set<String> = []
  public var audio = StudyAudioOptions()
  public var notifications: Set<NotificationPreference> = [.badge]
  public var customAvatarEmail = ""
  public var fallbackAvatarEmail = ""
  public var showCatalogAnswers = true
  public var autoSwitchKeyboard = false
  public var showMinutesForNextLevelUpReview = false
  public var apiBaseURL = WaniKaniClient.defaultBaseURL
  public init() {
    review.stageIndicator = .none
    review.sessionOptions.minimizePenalty = true
  }
  public func validate() throws {
    guard review.fontScale.isFinite, review.fontScale > 0 else {
      throw StudyPreferenceImportError.invalidSource("fontSize")
    }
    guard review.policy.leechThreshold.isFinite, review.policy.leechThreshold > 0 else {
      throw StudyPreferenceImportError.invalidSource("leechThreshold")
    }
    guard review.policy.limit > 0, review.sessionOptions.batchSize > 0,
      review.sessionOptions.incorrectAnswerDelay >= 0
    else { throw StudyPreferenceImportError.invalidSource("review session") }
    guard ["http", "https"].contains(apiBaseURL.scheme?.lowercased()),
      apiBaseURL.host?.isEmpty == false,
      apiBaseURL.user == nil, apiBaseURL.password == nil, apiBaseURL.query == nil,
      apiBaseURL.fragment == nil
    else { throw StudyPreferenceImportError.invalidSource("apiBaseUrl") }
    guard audio.voiceIDs.allSatisfy({ $0 > 0 }) else {
      throw StudyPreferenceImportError.invalidSource("offlineAudioVoiceActors")
    }
  }
}

public enum StudyPreferenceImportError: Error, LocalizedError {
  case invalidSource(String)
  case invalidDestination(String)
  public var errorDescription: String? {
    switch self {
    case .invalidSource(let key):
      "The old setting ‘\(key)’ could not be read. Its original value has been kept."
    case .invalidDestination(let key):
      "The saved native setting ‘\(key)’ could not be verified. Its value has been kept."
    }
  }
}

/// Reuse compatible original caches; no copying, deletion or second media owner is needed.
public enum StudyMediaLayout: String, Codable, Sendable {
  case native, legacyDocuments
  public func directories(nativeRoot: URL, documents: URL = .documentsDirectory) -> (
    fonts: URL, audio: URL
  ) {
    let root = self == .legacyDocuments ? documents : nativeRoot
    return (root.appending(path: "fonts"), root.appending(path: "audio"))
  }
}

/// Hydrate absent native keys from the durable receipt on every cold bootstrap.
/// Existing choices win, including changes made after the writer was activated.
@MainActor public struct StudyPreferenceImport {
  private let defaults: UserDefaults
  public init(defaults: UserDefaults) { self.defaults = defaults }
  public func apply(_ source: LegacyStudyPreferences, accountID: String) throws {
    try source.validate()
    guard !accountID.isEmpty else { throw StudyPreferenceImportError.invalidDestination("account") }
    try document(source.review, key: "native.reviewPreferences")
    try document(source.lessons, key: "native.lessonPreferences")
    try document(source.subjects, key: "native.subjectPreferences")
    try scalar(source.fonts.sorted(), key: "native.selectedFonts")
    try scalar(source.audio.enabled, key: "native.offlineAudio")
    try scalar(source.audio.cellular, key: "native.offlineAudioCellular")
    try scalar(source.audio.voiceIDs.sorted(), key: "native.offlineAudioVoices")
    for option in NotificationPreference.allCases {
      try scalar(source.notifications.contains(option), key: "native.\(option.key)")
    }
    try scalar(source.customAvatarEmail, key: "native.gravatarCustomEmail")
    try scalar(source.showCatalogAnswers, key: "catalog.showAnswers")
    try scalar(source.autoSwitchKeyboard, key: "native.autoSwitchKeyboard")
    try scalar(
      source.showMinutesForNextLevelUpReview, key: "native.showMinutesForNextLevelUpReview")
    try scalar(source.apiBaseURL.absoluteString, key: "native.apiBaseUrl")
    let key = "native.avatarFallbacks"
    var fallbacks: [String: String] = [:]
    if let existing = defaults.object(forKey: key) {
      guard let data = existing as? Data,
        let saved = try? PropertyListDecoder().decode([String: String].self, from: data)
      else { throw StudyPreferenceImportError.invalidDestination(key) }
      fallbacks = saved
    }
    if fallbacks[accountID] == nil, !source.fallbackAvatarEmail.isEmpty {
      fallbacks[accountID] = source.fallbackAvatarEmail
      defaults.set(try PropertyListEncoder().encode(fallbacks), forKey: key)
    }
  }
  private func document<Value: Codable>(_ value: Value, key: String) throws {
    if let existing = defaults.object(forKey: key) {
      guard let data = existing as? Data,
        (try? JSONDecoder().decode(Value.self, from: data)) != nil
      else { throw StudyPreferenceImportError.invalidDestination(key) }
    } else {
      defaults.set(try JSONEncoder().encode(value), forKey: key)
    }
  }
  private func scalar<Value>(_ value: Value, key: String) throws {
    if let existing = defaults.object(forKey: key) {
      guard existing is Value else { throw StudyPreferenceImportError.invalidDestination(key) }
    } else {
      defaults.set(value, forKey: key)
    }
  }
}
