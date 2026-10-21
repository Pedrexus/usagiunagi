import Foundation

public struct HomeDashboardData: Sendable {
  public struct Level: Identifiable, Sendable {
    public let id: Int
    public let progress: [StudyLevelProgress]
    public init(number: Int, progress: [StudyLevelProgress]) {
      id = number
      self.progress = progress
    }
  }
  public struct Metric: Identifiable, Sendable {
    public let id: String
    public let value: String
    public init(_ title: String, _ value: String) {
      id = title
      self.value = value
    }
  }
  public var notice: String?
  public var studyUnavailableMessage: String?
  public var scheduleUnavailableMessage: String?
  public var progressUnavailableMessage: String?
  public var resumeTitle: String?
  public var onVacation = false
  public var reviews = 0, lessons = 0, apprenticePractice = 0
  public var recentLessons = 0, recentMistakes = 0, leeches = 0, excluded = 0
  public var lessonsDisabledMessage: String?
  public var hourlyReviews: [Int] = []
  public var levels: [Level] = []
  public var timing: [Metric] = []
  public var stageCounts: [Int] = []
  public var recentlyUnlocked: [StudySubject] = []
  public var recentlyBurned: [StudySubject] = []
  public var date = Date.now
  public init() {}
}
