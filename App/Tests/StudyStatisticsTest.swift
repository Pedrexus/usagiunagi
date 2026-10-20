// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import StudyCore
import Testing

struct StudyStatisticsTest {
  private let now = Date(timeIntervalSince1970: 1_780_000_000)

  private func assignment(_ id: Int64, due: Date, stage: Int = 2) -> StudyAssignment {
    .init(subjectID: id, srsStageNumber: stage, availableAt: Int64(due.timeIntervalSince1970))
  }

  private func statistic(
    _ id: Int64, correct: Int, incorrect: Int,
    streak: Int = 0, hidden: Bool = false
  ) -> StudyAnswerStatistics {
    .init(
      subjectID: id, meaningCorrect: correct, meaningIncorrect: incorrect,
      meaningCurrentStreak: streak, hidden: hidden)
  }

  private func levels() -> [StudyLevel] {
    var result = [StudyLevel]()
    var start = now.addingTimeInterval(-100 * 86400)
    for (index, days) in [8, 10, 12, 14].enumerated() {
      let unlocked = Int64(start.timeIntervalSince1970)
      start = start.addingTimeInterval(Double(days) * 86400)
      result.append(
        .init(
          level: Int32(index + 3), unlockedAt: unlocked,
          passedAt: Int64(start.timeIntervalSince1970)))
    }
    result.append(
      .init(level: 7, unlockedAt: Int64(now.addingTimeInterval(-86400).timeIntervalSince1970)))
    return result
  }

  private func calculate(
    assignments: [StudyAssignment] = [], statistics: [StudyAnswerStatistics] = [],
    history: [StudyLevel] = [], vacation: Bool = false
  ) -> StudyMetrics {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return StudyMetrics(
      assignments: assignments, statistics: statistics, levels: history,
      currentLevel: 7, onVacation: vacation, now: now, calendar: calendar)
  }

  @Test func testEmptyHistoryDoesNotInventAccuracyOrPace() {
    let result = calculate()
    #expect(result.meaning.fraction == nil)
    #expect(result.reading.fraction == nil)
    #expect(result.pace == nil)
    #expect(result.dueNow == 0)
    #expect(result.focus.isEmpty)
  }

  @Test func testAccuracyWeightsAnswersAndExcludesHiddenItems() throws {
    let result = calculate(statistics: [
      statistic(1, correct: 9, incorrect: 1),
      statistic(2, correct: 0, incorrect: 2),
      statistic(3, correct: 100, incorrect: 0, hidden: true),
    ])
    let accuracy = try #require(result.meaning.fraction)
    #expect(abs(accuracy - 0.75) <= 0.0001)
    #expect(result.meaning.attempts == 12)
    #expect(result.reading.fraction == nil)
  }

  @Test func testScheduleCountsEachActiveAssignmentOnceAndSeparatesOverdue() {
    let a = assignment(1, due: now)
    let result = calculate(assignments: [
      a, a, assignment(2, due: now.addingTimeInterval(3600)),
      assignment(3, due: now, stage: 0),
      assignment(
        4, due: now,
        stage: 9),
    ])
    #expect(result.dueNow == 1)
    #expect(result.scheduledDays.reduce(0) { $0 + $1.count } == 1)
  }

  @Test func testMissingAvailableDateIsNotOverdue() {
    let a = StudyAssignment(subjectID: 1, srsStageNumber: 2)
    #expect(calculate(assignments: [a]).dueNow == 0)
  }

  @Test func testFocusIncludesZeroStreakButRequiresEvidenceAndActiveItem() {
    let result = calculate(
      assignments: [assignment(1, due: now), assignment(2, due: now)],
      statistics: [
        statistic(1, correct: 3, incorrect: 2),
        statistic(2, correct: 1, incorrect: 2),
        statistic(3, correct: 3, incorrect: 20),
      ])
    #expect(result.focus.map(\.subjectID) == [1])
    #expect(result.focus.first?.streak == 0)
  }

  @Test func testRecoveryStreakLowersPriority() {
    let result = calculate(
      assignments: [assignment(1, due: now), assignment(2, due: now)],
      statistics: [
        statistic(1, correct: 10, incorrect: 5, streak: 8),
        statistic(2, correct: 10, incorrect: 5, streak: 0),
      ])
    #expect(result.focus.map(\.subjectID) == [2, 1])
  }

  @Test func testPaceUsesMedianAndInterpolatedQuartiles() throws {
    let pace = try #require(calculate(history: levels()).pace)
    #expect(pace.sampleCount == 4)
    #expect(pace.medianDays == 11)
    #expect(pace.lowerDays == 9.5)
    #expect(pace.upperDays == 12.5)
    let range = try #require(pace.nextLevelRange)
    #expect(range.lowerBound > now)
  }

  @Test func testVacationAndElapsedPaceSuppressDates() {
    #expect(calculate(history: levels(), vacation: true).pace?.nextLevelRange == nil)
    var history = levels()
    history[4] = .init(
      level: 7, unlockedAt: Int64(now.addingTimeInterval(-20 * 86400).timeIntervalSince1970))
    #expect(calculate(history: history).pace?.nextLevelRange == nil)
  }

  @Test func testResetAndSmallSampleSuppressPace() {
    #expect(calculate(history: Array(levels().prefix(2))).pace == nil)
    var history = levels()
    let abandoned = StudyLevel(
      level: 8, unlockedAt: 0,
      abandonedAt: Int64(now.addingTimeInterval(-2 * 86400).timeIntervalSince1970))
    history.append(abandoned)
    #expect(calculate(history: history).pace == nil)
  }

  @Test func testDuplicateLevelIsNotCountedTwice() {
    var history = levels()
    history.append(history[0])
    #expect(calculate(history: history).pace?.sampleCount == 4)
  }
}
