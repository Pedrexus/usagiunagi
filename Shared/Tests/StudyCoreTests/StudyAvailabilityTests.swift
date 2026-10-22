import Foundation
import StudyCore
import Testing

struct StudyAvailabilityTests {
  private let now = Date(timeIntervalSince1970: 1_792_300_000)
  private func subject(_ id: Int64, kind: SubjectKind = .kanji) -> CatalogSubject {
    var value = CatalogSubject(id: id, kind: kind)
    value.level = 1
    return value
  }
  private func assignment(_ id: Int64, stage: Int = 3, kind: SubjectKind = .kanji)
    -> CatalogAssignment
  {
    var value = CatalogAssignment(id: id + 100, subjectID: id, kind: kind)
    value.level = 1
    value.srsStage = stage
    value.startedAt = 1
    value.availableAt = Int64(now.timeIntervalSince1970)
    return value
  }
  private var account: StudyAccountState {
    var profile = StudyAccountProfile(username: "fixture")
    profile.level = 1
    profile.maxLevelGranted = 3
    return .init(download: .init(accountID: "fixture", profile: profile))
  }
  @Test func notificationProjectionRetainsExactDatesAndOmitsMissingContent() {
    var item = assignment(1)
    item.availableAt = Int64(now.timeIntervalSince1970) + 1801
    let available = StudyAvailability(
      account: account, subjects: [subject(1)],
      assignments: [item, assignment(2)], now: now)
    #expect(available.serviceSnapshot.reviewDates == [now.addingTimeInterval(1801)])
    #expect(!available.serviceSnapshot.onVacation)
    var vacation = account
    vacation.profile.vacationStartedAt = 1
    #expect(
      StudyAvailability(
        account: vacation, subjects: [subject(1)],
        assignments: [item], now: now
      ).serviceSnapshot.onVacation)
  }
  @Test func queuesShareVisibilityAccessExclusionAndPendingRules() {
    var subjects = (1...8).map { subject(Int64($0)) }
    subjects[2].hiddenAt = 1
    subjects[3].level = 4
    subjects[4].kind = .vocabulary
    var assignments = (1...8).map { assignment(Int64($0)) }
    assignments[1].hidden = true
    assignments[4].kind = .vocabulary
    assignments[6].srsStage = 0
    assignments[6].startedAt = nil
    assignments[6].unlockedAt = 1
    assignments[7].srsStage = 0
    assignments[7].startedAt = nil
    assignments[7].unlockedAt = nil
    let available = StudyAvailability(
      account: account, subjects: subjects, assignments: assignments,
      pending: [6], excluded: [5], now: now)
    #expect(available.scheduled.map(\.subjectID) == [1])
    #expect(available.serviceSnapshot.reviewDates == [now])
    #expect(available.lessons.map(\.subjectID) == [7])
    #expect(available.practice(.recentLessons).map(\.subjectID) == [1, 5])
    #expect(available.stageCounts == [2, 0, 0, 0, 0])
  }
  @Test func extraStudySeparatesUnguruedLessonsPassedApprenticesAndBurnedItems() {
    var items = [assignment(1), assignment(2), assignment(3, stage: 9), assignment(4, stage: 5)]
    items[0].startedAt = 1  // Recent lessons means not yet Guru, regardless of age.
    items[1].passedAt = 1
    items[2].passedAt = 1
    items[2].burnedAt = 1
    items[2].availableAt = nil
    items[3].passedAt = 1
    let available = StudyAvailability(
      account: account, subjects: (1...4).map { subject(Int64($0)) }, assignments: items, now: now)
    #expect(available.practice(.recentLessons).map(\.subjectID) == [1])
    #expect(available.practice(.apprentice).map(\.subjectID) == [2])
    #expect(available.practice(.burned).map(\.subjectID) == [3])
  }
  @Test func recentMistakesUseEpochWithAnExactDayBoundary() {
    var account = account
    let offsets: [Int64] = [0, -86400, -86401, 1, -3600]
    account.progress = (1...5).map { id in
      SubjectProgress(
        subjectID: Int64(id), level: 1, srsStage: 3, kind: .kanji,
        lastMistakeAt: Int64(now.timeIntervalSince1970) + offsets[id - 1])
    }
    let available = StudyAvailability(
      account: account, subjects: (1...5).map { subject(Int64($0)) },
      assignments: (1...5).map { assignment(Int64($0)) }, now: now)
    #expect(available.practice(.recentMistakes).map(\.subjectID) == [1, 2, 5])
  }
  @Test func leechesNeedPassedItemsAndUseOnlyMeaningStatisticsForRadicals() {
    var account = account
    account.statistics = [
      .init(
        id: 1,
        answers: .init(
          subjectID: 1, meaningIncorrect: 8, meaningCurrentStreak: 2, readingIncorrect: 4,
          readingCurrentStreak: 2)),
      .init(
        id: 2,
        answers: .init(subjectID: 2, type: .radical, meaningIncorrect: 2, meaningCurrentStreak: 1)),
      .init(
        id: 3,
        answers: .init(
          subjectID: 3, meaningIncorrect: 20, meaningCurrentStreak: 0, readingIncorrect: 20,
          readingCurrentStreak: 0)),
    ]
    var assignments = [assignment(1), assignment(2, kind: .radical), assignment(3)]
    for index in assignments.indices { assignments[index].passedAt = 1 }
    let available = StudyAvailability(
      account: account, subjects: [subject(1), subject(2, kind: .radical), subject(3)],
      assignments: assignments, now: now)
    #expect(available.practice(.leeches).map(\.subjectID) == [1, 2])
    #expect(
      StudyAvailability(
        account: account, subjects: available.subjects, assignments: assignments, now: now,
        leechThreshold: 3
      ).practice(.leeches).isEmpty)
  }
  @Test func rollingForecastIncludesTheEntireTwentyFourthHour() {
    let offsets: [Int64] = [
      -1, 0, 1, 3600, 3601, 23 * 3600, 23 * 3600 + 1, 24 * 3600, 24 * 3600 + 1,
    ]
    let assignments = offsets.enumerated().map { index, offset in
      var value = assignment(Int64(index + 1))
      value.availableAt = Int64(now.timeIntervalSince1970) + offset
      return value
    }
    let available = StudyAvailability(
      account: account, subjects: [], assignments: assignments, now: now)
    #expect(available.hourlyReviews.count == 25)
    #expect(
      available.hourlyReviews[0] == 2 && available.hourlyReviews[1] == 2
        && available.hourlyReviews[2] == 1)
    #expect(available.hourlyReviews[23] == 1 && available.hourlyReviews[24] == 2)
    #expect(available.hourlyReviews.reduce(0, +) == 8 && available.scheduledFuture.count == 9)
  }
  @Test func optionalSessionAndMistakeFieldsRoundTrip() throws {
    var session = try StudySession(items: [assignment(1).sessionItem(id: 0, isLesson: false)])
    session.nextQuestion()
    let encoder = JSONEncoder()
    var object = try #require(
      JSONSerialization.jsonObject(with: encoder.encode(session)) as? [String: Any])
    object.removeValue(forKey: "practiceScope")
    let decoded = try JSONDecoder().decode(
      StudySession.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.practiceScope == nil && decoded.question == session.question)
    let progress = SubjectProgress(
      subjectID: 1, level: 1, srsStage: 3, kind: .kanji,
      lastMistakeAt: nil)
    let bytes = try encoder.encode(progress)
    #expect(!String(decoding: bytes, as: UTF8.self).contains("lastMistakeAt"))
    #expect(try JSONDecoder().decode(SubjectProgress.self, from: bytes).lastMistakeAt == nil)
  }
}
