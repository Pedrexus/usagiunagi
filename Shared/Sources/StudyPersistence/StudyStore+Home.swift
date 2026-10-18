import Foundation
import StudyCore
import SwiftData

extension StudyStore {
  public func availability(
    accountID: String, now: Date = .now, calendar: Calendar = .current,
    leechThreshold: Double = 1, lessonPreferences: StudyLessonPreferences = .init()
  ) throws -> StudyAvailability {
    try requireAccount(accountID)
    guard let account = try accountState(accountID: accountID) else {
      throw NativeReviewError.unavailableAccount
    }
    return try StudyAvailability(
      account: account, subjects: catalog(accountID: accountID),
      assignments: assignments(accountID: accountID),
      pending: Set(pendingReviews(accountID: accountID).map(\.subjectID)),
      excluded: Set(
        materials(accountID: accountID).filter { $0.material.isExcluded }.map {
          $0.material.subjectID
        }),
      now: now, calendar: calendar, leechThreshold: leechThreshold,
      lessonPreferences: lessonPreferences)
  }

  public func homeData(
    accountID: String, now: Date = .now, calendar: Calendar = .current,
    lessonPreferences: StudyLessonPreferences = .init()
  ) throws
    -> HomeDashboardData
  {
    let available = try availability(
      accountID: accountID, now: now, calendar: calendar, lessonPreferences: lessonPreferences)
    let snapshot = try snapshotForHome(accountID)
    var data = HomeDashboardData()
    data.date = now
    data.onVacation = available.account.profile.vacationStartedAt != nil
    data.reviews = available.scheduled.count
    data.lessons = available.lessons.count
    data.lessonsDisabledMessage =
      available.apprenticeLimitReached ? "Apprentice limit reached" : nil
    data.apprenticePractice = available.practice(.apprentice).count
    data.recentLessons = available.practice(.recentLessons).count
    data.recentMistakes = available.practice(.recentMistakes).count
    data.leeches = available.practice(.leeches).count
    data.excluded =
      available.subjects.filter {
        $0.hiddenAt == nil && $0.level <= available.account.profile.maxLevelGranted
          && available.excluded.contains($0.id)
      }.count
    data.hourlyReviews = available.hourlyReviews
    data.stageCounts = available.stageCounts
    if !available.pending.isEmpty {
      data.notice = "\(available.pending.count) uploads pending. Progress updates after syncing."
      data.scheduleUnavailableMessage = "Sync saved work to update the forecast."
    }
    if snapshot.requiresAssignmentRefresh {
      data.notice = "Refresh WaniKani to reload progress for archived answers."
      data.scheduleUnavailableMessage = "Refresh to update the forecast."
      data.progressUnavailableMessage = "Refresh to update study progress."
    } else {
      let current = max(1, available.account.profile.level)
      let previous = current > 1 ? available.progress(level: current - 1) : []
      if previous.contains(where: { $0.guru < $0.total }) {
        data.levels.append(.init(number: current - 1, progress: previous))
      }
      data.levels.append(.init(number: current, progress: available.progress(level: current)))
    }
    if let saved = try session(accountID: accountID) {
      let title =
        saved.session.isPractice
        ? saved.session.practiceScope?.title ?? "Practice"
        : saved.session.items.values.first?.isLesson == true ? "Lesson quiz" : "Reviews"
      data.resumeTitle =
        "\(saved.session.question == nil ? "Finish" : "Resume") \(title.lowercased())"
    }
    return data
  }

  // A verified account may have several credential mappings; all share this account's revisions.
  private func snapshotForHome(_ accountID: String) throws -> StudySnapshot {
    let rows = try modelContext.fetch(FetchDescriptor<SnapshotRecord>())
    guard
      let snapshot = rows.first(where: {
        $0.snapshot.accountID == accountID && !$0.snapshot.isSample
      })?.snapshot
    else { throw StudyStoreError.invalidIdentity }
    return snapshot
  }
}
