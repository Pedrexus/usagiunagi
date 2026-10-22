import Foundation

/// Frozen V1 receipt payload. Runtime settings use their native preference stores.
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
}
