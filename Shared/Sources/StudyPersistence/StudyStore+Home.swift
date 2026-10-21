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
    lessonPreferences: StudyLessonPreferences = .init(),
    subjectPreferences: SubjectDetailsPreferences = .init(), policy: StudyReviewPolicy = .init(),
    showMinutes: Bool = false
  ) throws
    -> HomeDashboardData
  {
    let available = try availability(
      accountID: accountID, now: now, calendar: calendar,
      leechThreshold: policy.normalized.leechThreshold, lessonPreferences: lessonPreferences)
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
    do {
      data.timing = try available.homeTiming(showMinutes: showMinutes, calendar: calendar)
    } catch { data.timing = [.init("Level timing", error.localizedDescription)] }
    if !available.pending.isEmpty {
      data.notice =
        "\(available.pending.count) uploads pending. Completed work syncs automatically when online."
      data.scheduleUnavailableMessage =
        "The forecast updates after saved work syncs. Check Saved work for items needing attention."
    }
    if snapshot.requiresAssignmentRefresh {
      data.notice = "Refresh WaniKani to reload progress for archived answers."
      data.scheduleUnavailableMessage = "Refresh to update the forecast."
      data.progressUnavailableMessage = "Refresh to update study progress."
    } else {
      let current = max(1, available.account.profile.level)
      let previous = current > 1 ? available.progress(level: current - 1) : []
      if subjectPreferences.showPreviousLevelGraph, previous.contains(where: { $0.guru < $0.total })
      {
        data.levels.append(.init(number: current - 1, progress: previous))
      }
      data.levels.append(.init(number: current, progress: available.progress(level: current)))
      let byID = Dictionary(
        uniqueKeysWithValues: available.subjects.filter {
          $0.hiddenAt == nil && $0.level <= available.account.profile.maxLevelGranted
        }.map { ($0.id, $0) })
      let confirmed = available.assignments.filter {
        $0.hidden != true && !available.pending.contains($0.subjectID)
          && byID[$0.subjectID] != nil
      }
      let cutoff =
        calendar.date(byAdding: .day, value: -30, to: now)
        ?? now.addingTimeInterval(-30 * 86400)
      let window = Int64(cutoff.timeIntervalSince1970)...Int64(now.timeIntervalSince1970)
      data.recentlyUnlocked = confirmed.filter {
        $0.unlockedAt.map(window.contains) == true
      }.sorted { ($0.unlockedAt ?? 0, $0.subjectID) > ($1.unlockedAt ?? 0, $1.subjectID) }
        .compactMap { byID[$0.subjectID]?.summary }
      data.recentlyBurned = confirmed.filter {
        $0.srsStage == 9 && $0.burnedAt.map(window.contains) == true
      }.sorted { ($0.burnedAt ?? 0, $0.subjectID) > ($1.burnedAt ?? 0, $1.subjectID) }
        .compactMap { byID[$0.subjectID]?.summary }
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
