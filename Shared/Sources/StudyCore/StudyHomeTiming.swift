import Foundation

extension StudyAvailability {
  /// Original Home timing, using cached server SRS definitions and an explicit study clock.
  /// These are correct/on-time-review scenarios, never a promise about the learner's pace.
  public func homeTiming(showMinutes: Bool = false, calendar: Calendar = .current) throws
    -> [HomeDashboardData.Metric]
  {
    guard account.profile.vacationStartedAt == nil, pending.isEmpty,
      account.profile.level > 0, account.profile.level <= account.profile.maxLevelGranted
    else { return [] }
    let current = subjects.filter {
      $0.level == account.profile.level && $0.hiddenAt == nil && $0.kind != .vocabulary
    }
    let kanji = current.filter { $0.kind == .kanji }
    guard !kanji.isEmpty else { return [] }
    let byID = Dictionary(
      assignments.filter { $0.hidden != true }.map { ($0.subjectID, $0) },
      uniquingKeysWith: { first, _ in first })
    func remainingIntervals(_ subject: CatalogSubject, after stage: Int) throws -> TimeInterval {
      let system = account.systems?.first { $0.id == subject.spacedRepetitionSystemID }
      let passing = system?.passingStage ?? 5
      guard stage < passing - 1 else { return 0 }
      return try ((stage + 1)..<passing).reduce(0) {
        try $0 + StudySRSSystem.interval(subject: subject, stage: $1, systems: account.systems)
      }
    }
    func guru(_ subject: CatalogSubject) throws -> Date {
      guard let item = byID[subject.id] else { return .distantFuture }
      let passing =
        account.systems?.first { $0.id == subject.spacedRepetitionSystemID }?.passingStage ?? 5
      if let passed = item.passedAt { return Date(timeIntervalSince1970: Double(passed)) }
      if item.srsStage >= passing { return .distantPast }
      let due = item.availableAt.map { Date(timeIntervalSince1970: Double($0)) } ?? now
      return max(now, due).addingTimeInterval(try remainingIntervals(subject, after: item.srsStage))
    }
    func requiredDate(_ dates: [Date]) -> Date {
      dates.sorted()[dates.count - Int(Double(dates.count) * 0.1) - 1]
    }
    let known = try kanji.map(guru)
    let lockedNeeded = requiredDate(known) == .distantFuture
    let next = current.compactMap { subject -> Date? in
      guard subject.kind == .kanji || lockedNeeded,
        let item = byID[subject.id], item.passedAt == nil, item.srsStage > 0,
        let due = item.availableAt
      else { return nil }
      return Date(timeIntervalSince1970: Double(due))
    }.min()
    var finish = requiredDate(known)
    if lockedNeeded {
      let radicalFinish =
        try current.filter { $0.kind == .radical }.map(guru)
        .filter { $0 != .distantFuture }.max() ?? now
      let earliest = try kanji.map { subject in
        if byID[subject.id] != nil { return try guru(subject) }
        return max(now, radicalFinish).addingTimeInterval(try remainingIntervals(subject, after: 0))
      }
      finish = requiredDate(earliest)
      let history = account.levels.filter { $0.abandonedAt == nil }
      let durations = history.compactMap { level -> TimeInterval? in
        guard let unlocked = level.unlockedAt, let passed = level.passedAt, passed > unlocked,
          level.level != account.profile.level
        else { return nil }
        return Double(passed - unlocked)
      }.sorted()
      if !durations.isEmpty {
        let middle = durations.count / 2
        let median =
          durations.count.isMultiple(of: 2)
          ? (durations[middle - 1] + durations[middle]) / 2 : durations[middle]
        let started = history.filter { $0.level == account.profile.level }.compactMap(\.unlockedAt)
          .max()
        let elapsed = started.map { max(0, now.timeIntervalSince1970 - Double($0)) } ?? 0
        finish = max(finish, now.addingTimeInterval(max(0, median - elapsed)))
      }
    }
    return [
      .init(
        "Next level-up review",
        next.map {
          StudyHomeTiming.interval($0, now: now, calendar: calendar, showMinutes: showMinutes)
        } ?? "N/A"),
      .init(
        lockedNeeded ? "Time remaining (estimated)" : "Time remaining",
        StudyHomeTiming.interval(finish, now: now, calendar: calendar)),
    ]
  }
}

public enum StudyHomeTiming {
  public static func interval(
    _ date: Date, now: Date, calendar: Calendar = .current,
    showMinutes: Bool = false
  ) -> String {
    guard date > now else { return "Now" }
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    var parts = calendar.dateComponents([.day, .hour, .minute], from: now, to: date)
    if !showMinutes, (parts.day ?? 0) > 0 || (parts.hour ?? 0) > 0 { parts.minute = 0 }
    return formatter.string(from: parts) ?? "N/A"
  }
}
