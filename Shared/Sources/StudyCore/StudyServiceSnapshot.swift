import Foundation

/// One account-bound projection for reminders and companion delivery, independent of permissions.
public struct StudyServiceSnapshot: Sendable {
  public var reviewDates: [Date]
  public var onVacation: Bool
  public var currentLevel: HomeDashboardData.Level?
  public var previousLevel: HomeDashboardData.Level?
  public init(
    reviewDates: [Date] = [], onVacation: Bool = true,
    currentLevel: HomeDashboardData.Level? = nil, previousLevel: HomeDashboardData.Level? = nil
  ) {
    self.reviewDates = reviewDates
    self.onVacation = onVacation
    self.currentLevel = currentLevel
    self.previousLevel = previousLevel
  }
}

public struct StudyCompanionSnapshot: Equatable, Sendable {
  public let reviews: Int
  public let upcoming: [Int]
  public let nextReview: Int64
  public let level: Int
  public let learned: Int
  public let total: Int
  public let halfLevel: Bool
  public init(_ source: StudyServiceSnapshot, now: Date = .now) {
    let dates = source.onVacation ? [] : source.reviewDates
    reviews = dates.filter { $0 <= now }.count
    var hours = source.onVacation ? [] : Array(repeating: 0, count: 24)
    for date in dates where date > now {
      let hour = ceil(date.timeIntervalSince(now) / 3600)
      if hour >= 1 && hour <= 24 { hours[Int(hour) - 1] += 1 }
    }
    upcoming = hours
    nextReview =
      dates.filter { $0 > now }.min().flatMap {
        Int64(exactly: $0.timeIntervalSince1970.rounded(.down))
      } ?? 0
    var progress = source.currentLevel
    let currentLearned = progress?.progress.reduce(0) { $0 + $1.guru } ?? 0
    if let current = progress, current.id > 1, currentLearned == 0,
      let previous = source.previousLevel, previous.id == current.id - 1,
      previous.progress.contains(where: { $0.total > 0 })
    {
      progress = previous
      halfLevel = true
    } else {
      halfLevel = false
    }
    level = progress?.id ?? 0
    learned = progress?.progress.reduce(0) { $0 + $1.guru } ?? 0
    total = progress?.progress.reduce(0) { $0 + $1.total } ?? 0
  }
}

extension StudyAvailability {
  public var serviceSnapshot: StudyServiceSnapshot {
    let known = Set(subjects.map(\.id))
    let level = account.profile.level
    return .init(
      reviewDates: scheduledFuture.filter { known.contains($0.subjectID) }.compactMap {
        $0.availableAt.map { Date(timeIntervalSince1970: Double($0)) }
      }, onVacation: account.profile.vacationStartedAt != nil,
      currentLevel: .init(number: level, progress: progress(level: level)),
      previousLevel: level > 1
        ? .init(number: level - 1, progress: progress(level: level - 1)) : nil)
  }
}
