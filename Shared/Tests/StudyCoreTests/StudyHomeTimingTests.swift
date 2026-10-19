import Foundation
import StudyCore
import Testing

struct StudyHomeTimingTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func subject(_ id: Int64, kind: SubjectKind = .kanji) -> CatalogSubject {
    var value = CatalogSubject(id: id, kind: kind)
    value.level = 12
    return value
  }
  private func assignment(
    _ id: Int64, stage: Int = 3, due: Int64 = 3600,
    kind: SubjectKind = .kanji
  ) -> CatalogAssignment {
    var value = CatalogAssignment(id: id + 100, subjectID: id, kind: kind)
    value.level = 12
    value.srsStage = stage
    value.availableAt = stage > 0 ? Int64(now.timeIntervalSince1970) + due : nil
    value.startedAt = stage > 0 ? 1 : nil
    value.passedAt = stage >= 5 ? 1 : nil
    return value
  }
  private var account: StudyAccountState {
    var profile = StudyAccountProfile(username: "timing fixture")
    profile.level = 12
    profile.maxLevelGranted = 60
    return .init(legacy: .init(schemaVersion: 15, profile: profile))
  }
  @Test func nextReviewAndMinimumGuruTimeUseTheActualDueDate() throws {
    let rows = try StudyAvailability(
      account: account, subjects: [subject(1)],
      assignments: [assignment(1)], now: now
    ).homeTiming()
    #expect(rows.map(\.id) == ["Next level-up review", "Time remaining"])
    #expect(rows[0].value == StudyHomeTiming.interval(now.addingTimeInterval(3600), now: now))
    #expect(
      rows[1].value == StudyHomeTiming.interval(now.addingTimeInterval(3600 + 169200), now: now))
  }
  @Test func passedNinetyPercentDoesNotWaitForTheLastLockedKanjiOrItsRadicals() throws {
    let subjects = (1...10).map { subject(Int64($0)) } + [subject(11, kind: .radical)]
    let assignments =
      (1...9).map { assignment(Int64($0), stage: 5) }
      + [assignment(11, stage: 4, due: 600, kind: .radical)]
    let rows = try StudyAvailability(
      account: account, subjects: subjects,
      assignments: assignments, now: now
    ).homeTiming()
    #expect(rows[0].value == "N/A" && rows[1].value == "Now")
  }
  @Test func requiredLockedKanjiIncludeRadicalWorkAndAFreshSRSPath() throws {
    let subjects = (1...9).map { subject(Int64($0)) } + [subject(10, kind: .radical)]
    let assignments =
      (1...8).map { assignment(Int64($0), stage: 5) }
      + [assignment(10, stage: 4, due: 600, kind: .radical)]
    let rows = try StudyAvailability(
      account: account, subjects: subjects,
      assignments: assignments, now: now
    ).homeTiming()
    #expect(rows[1].id == "Time remaining (estimated)")
    #expect(rows[0].value == StudyHomeTiming.interval(now.addingTimeInterval(600), now: now))
    #expect(
      rows[1].value == StudyHomeTiming.interval(now.addingTimeInterval(600 + 295200), now: now))
  }
  @Test func historyUsesTheMedianOfCompletedUnabandonedLevels() throws {
    var state = account
    state.levels = [1_000_000, 2_000_000, 100_000_000].enumerated().map { index, duration in
      var level = CatalogLevelProgression(id: Int64(index + 1))
      level.level = index + 3
      level.unlockedAt = 1
      level.passedAt = Int64(duration + 1)
      return level
    }
    var current = CatalogLevelProgression(id: 12)
    current.level = 12
    current.unlockedAt = Int64(now.timeIntervalSince1970) - 1000
    state.levels.append(current)
    let rows = try StudyAvailability(
      account: state, subjects: [subject(1)],
      assignments: [], now: now
    ).homeTiming()
    #expect(rows[1].value == StudyHomeTiming.interval(now.addingTimeInterval(1_999_000), now: now))
  }
  @Test func serverSRSIntervalsReplaceHardcodedTimingAndMissingSystemsDoNotInventDates() throws {
    var kanji = subject(1)
    kanji.spacedRepetitionSystemID = 99
    var state = account
    state.systems = [
      .init(
        id: 99, name: "Fixture", unlockingStage: 0, startingStage: 1,
        passingStage: 5, burningStage: 9,
        stages: (1...4).map { .init(position: $0, interval: Double($0 * 10)) })
    ]
    let rows = try StudyAvailability(
      account: state, subjects: [kanji],
      assignments: [assignment(1, stage: 0)], now: now
    ).homeTiming()
    #expect(rows[1].value == StudyHomeTiming.interval(now.addingTimeInterval(100), now: now))
    #expect(throws: StudySRSSystem.MissingInterval.self) {
      try StudyAvailability(account: account, subjects: [kanji], assignments: [], now: now)
        .homeTiming()
    }
  }
  @Test func vacationPendingWorkAndInaccessibleLevelsDoNotPublishTiming() throws {
    var state = account
    state.profile.vacationStartedAt = 1
    #expect(
      try StudyAvailability(
        account: state, subjects: [subject(1)],
        assignments: [assignment(1)], now: now
      ).homeTiming().isEmpty)
    #expect(
      try StudyAvailability(
        account: account, subjects: [subject(1)],
        assignments: [assignment(1)], pending: [1], now: now
      ).homeTiming().isEmpty)
    state.profile.vacationStartedAt = nil
    state.profile.maxLevelGranted = 3
    #expect(
      try StudyAvailability(
        account: state, subjects: [subject(1)],
        assignments: [assignment(1)], now: now
      ).homeTiming().isEmpty)
  }
  @Test func minutePreferenceAndOverdueClampingUseTheStudyClock() throws {
    let available = StudyAvailability(
      account: account, subjects: [subject(1)],
      assignments: [assignment(1, due: 5400)], now: now)
    #expect(try available.homeTiming()[0].value != available.homeTiming(showMinutes: true)[0].value)
    let late = try StudyAvailability(
      account: account, subjects: [subject(1)],
      assignments: [assignment(1, stage: 4, due: -3600)], now: now
    ).homeTiming()
    #expect(late[0].value == "Now" && late[1].value == "Now")
  }
}
