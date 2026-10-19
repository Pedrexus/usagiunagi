import Foundation
import StudyCore
import Testing

struct StudyCompanionSnapshotTests {
  private let now = Date(timeIntervalSince1970: 10_000)
  private func level(_ number: Int, _ stages: [Int?]) -> HomeDashboardData.Level {
    .init(
      number: number,
      progress: [
        .init(
          kind: .kanji,
          stages: stages.map { ($0, ($0 ?? 0) > 0) })
      ])
  }
  @Test func exactReviewDatesUseTwentyFourRollingFutureBins() {
    let offsets: [TimeInterval] = [-1, 0, 1, 3600, 3601, 86400, 86401]
    let source = StudyServiceSnapshot(
      reviewDates: offsets.map { now.addingTimeInterval($0) }, onVacation: false)
    let value = StudyCompanionSnapshot(source, now: now)
    #expect(value.reviews == 2 && value.upcoming.count == 24)
    #expect(value.upcoming[0] == 2 && value.upcoming[1] == 1 && value.upcoming[23] == 1)
    #expect(value.upcoming.reduce(0, +) == 4 && value.nextReview == 10_001)
  }
  @Test func vacationClearsReviewsWhilePreservingKnownLevelProgress() {
    let source = StudyServiceSnapshot(
      reviewDates: [now, now.addingTimeInterval(3600)],
      onVacation: true, currentLevel: level(2, [5, 1, nil]))
    let value = StudyCompanionSnapshot(source, now: now)
    #expect(value.reviews == 0 && value.upcoming.isEmpty && value.nextReview == 0)
    #expect(value.level == 2 && value.total == 3 && value.learned == 1 && !value.halfLevel)
  }
  @Test func anUnstartedCurrentLevelKeepsTheExistingHalfLevelConvention() {
    let source = StudyServiceSnapshot(
      onVacation: false, currentLevel: level(4, [1, 0, nil]),
      previousLevel: level(3, [5, 9, nil]))
    let value = StudyCompanionSnapshot(source, now: now)
    #expect(value.level == 3 && value.total == 3 && value.learned == 2 && value.halfLevel)
  }
  @Test func firstLevelOrMissingPreviousDataNeverInventsLevelZeroPointFive() {
    for source in [
      StudyServiceSnapshot(currentLevel: level(1, [0, nil])),
      StudyServiceSnapshot(currentLevel: level(4, [])),
      StudyServiceSnapshot(currentLevel: level(4, [1]), previousLevel: level(3, [])),
      StudyServiceSnapshot(currentLevel: level(4, [1]), previousLevel: level(2, [5])),
    ] {
      let value = StudyCompanionSnapshot(source, now: now)
      #expect(!value.halfLevel && value.level == source.currentLevel?.id)
    }
  }
  @Test func currentGuruProgressDoesNotFallBackAndLogoutIsCompletelyEmpty() {
    let value = StudyCompanionSnapshot(
      .init(currentLevel: level(4, [5, 8, 0]), previousLevel: level(3, [9])), now: now)
    #expect(value.level == 4 && value.total == 3 && value.learned == 2 && !value.halfLevel)
    let empty = StudyCompanionSnapshot(.init(), now: now)
    #expect(empty.level == 0 && empty.total == 0 && empty.learned == 0 && !empty.halfLevel)
    #expect(empty.reviews == 0 && empty.upcoming.isEmpty && empty.nextReview == 0)
  }
  @Test func theNextReviewMayBeBeyondTheForecastAndHasNoRoundingToAnEarlierHour() {
    let date = now.addingTimeInterval(86401.5)
    let value = StudyCompanionSnapshot(.init(reviewDates: [date], onVacation: false), now: now)
    #expect(value.upcoming.allSatisfy { $0 == 0 } && value.nextReview == 96_401)
    #expect(value.reviews == 0)
  }
}
