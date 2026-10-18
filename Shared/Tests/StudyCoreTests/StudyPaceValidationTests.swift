import Foundation
import Testing

@testable import StudyCore

@Suite struct StudyPaceValidationTests {
  private let epoch: Int64 = 1_600_000_000
  private let now = Date(timeIntervalSince1970: 1_900_000_000)

  private func levels(_ days: [Int], first: Int32 = 3, start: Int64? = nil) -> [StudyLevel] {
    var cursor = start ?? epoch
    return days.enumerated().map { index, duration in
      let unlocked = cursor
      cursor += Int64(duration) * 86400
      return StudyLevel(level: first + Int32(index), unlockedAt: unlocked, passedAt: cursor)
    }
  }
  private func metrics(_ history: [StudyLevel], currentLevel: Int = 60, vacation: Bool = false)
    -> StudyMetrics
  {
    StudyMetrics(
      assignments: [], statistics: [], levels: history,
      currentLevel: currentLevel, onVacation: vacation, now: now)
  }

  @Test func unchangedPaceHasZeroErrorAndExactBandHits() throws {
    let result = try #require(metrics(levels(Array(repeating: 7, count: 10))).pace?.validation)
    #expect(result.trials.map(\.level) == Array(6...12))
    #expect(result.meanAbsoluteErrorDays == 0)
    #expect(result.withinBandCount == 7)
    #expect(
      result.trials.allSatisfy { $0.actualDays == 7 && $0.estimatedDays == 7 && $0.withinBand })
  }

  @Test(arguments: [3, 4, 5]) func insufficientHeldOutHistoryDoesNotReportAnErrorRate(_ count: Int)
    throws
  {
    let pace = try #require(metrics(levels(Array(repeating: 7, count: count))).pace)
    #expect(pace.validation == nil)
  }

  @Test func threeTrainingAndThreeHeldOutLevelsAreEnoughForTheFirstCheck() throws {
    let result = try #require(metrics(levels(Array(repeating: 7, count: 6))).pace?.validation)
    #expect(result.trials.map(\.level) == [6, 7, 8])
    #expect(result.trials.map(\.trainingCount) == [3, 4, 5])
  }

  @Test func aChangeInPaceCannotLeakIntoEarlierEstimates() throws {
    let history = levels([5, 5, 5, 20, 20, 20, 20, 20])
    let result = try #require(metrics(history).pace?.validation)
    let first = try #require(result.trials.first)
    #expect(first.level == 6 && first.actualDays == 20)
    #expect(first.estimatedDays == 5 && first.lowerDays == 5 && first.upperDays == 5)
    #expect(first.absoluteErrorDays == 15 && !first.withinBand)
    let extended =
      history + [
        StudyLevel(
          level: 11, unlockedAt: history.last!.passedAt,
          passedAt: history.last!.passedAt + 90 * 86400)
      ]
    let same = try #require(metrics(extended).pace?.validation?.trials.first { $0.level == 6 })
    #expect(same.estimatedDays == first.estimatedDays && same.trainingCount == first.trainingCount)
  }

  @Test func aLowerNumberedLevelStillCannotTrainAnEstimateBeforeItPassed() throws {
    var history = levels(Array(repeating: 10, count: 8))
    history[2] = StudyLevel(
      level: 5, unlockedAt: history[2].unlockedAt, passedAt: epoch + 90 * 86400)
    let result = try #require(metrics(history).pace?.validation)
    #expect(!result.trials.contains { $0.level == 6 })
    let seventh = try #require(result.trials.first { $0.level == 7 })
    #expect(seventh.trainingCount == 3 && seventh.estimatedDays == 10)
  }

  @Test func trainingAndEvaluationEachUseAtMostEightRecentLevels() throws {
    let pace = try #require(metrics(levels(Array(1...20))).pace)
    let result = try #require(pace.validation)
    #expect(pace.sampleCount == 8 && result.trials.count == 8)
    #expect(result.trials.map(\.level) == Array(15...22))
    #expect(result.trials.allSatisfy { $0.trainingCount == 8 })
    let first = try #require(result.trials.first)
    #expect(first.actualDays == 13 && first.estimatedDays == 8.5)
    #expect(first.lowerDays == 6.75 && first.upperDays == 10.25)
    #expect(result.meanAbsoluteErrorDays == 4.5 && result.withinBandCount == 0)
  }

  @Test func resetsAndDuplicateRecordsCannotInflateValidation() throws {
    let previous = levels(Array(repeating: 90, count: 9))
    let reset = previous.last!.passedAt + 86400
    let active = levels(Array(repeating: 4, count: 7), start: reset + 86400)
    let abandoned = StudyLevel(level: 10, unlockedAt: epoch, abandonedAt: reset)
    let pace = try #require(
      metrics(previous + active + [active[3], abandoned], currentLevel: 10).pace)
    let result = try #require(pace.validation)
    #expect(pace.sampleCount == 7 && result.trials.count == 4)
    #expect(result.trials.allSatisfy { $0.estimatedDays == 4 && $0.actualDays == 4 })
    #expect(result.meanAbsoluteErrorDays == 0)
  }

  @Test func unknownFutureAndIntroductoryLevelsCannotBecomeTrainingEvidence() throws {
    let valid = levels(Array(repeating: 7, count: 10))
    let invalid = [
      StudyLevel(level: 1, unlockedAt: epoch - 2 * 86400, passedAt: epoch - 86400),
      StudyLevel(level: 13, unlockedAt: 0, passedAt: epoch + 100 * 86400),
      StudyLevel(level: 14, unlockedAt: epoch, passedAt: Int64(now.timeIntervalSince1970) + 1),
      StudyLevel(level: 15, unlockedAt: epoch),
    ]
    let result = try #require(metrics(valid + invalid).pace?.validation)
    #expect(result.trials.map(\.level) == Array(6...12))
    #expect(result.trials.allSatisfy { $0.estimatedDays == 7 })
  }

  @Test func vacationSuppressesFutureDatesButRetainsPastValidation() throws {
    let history = levels(Array(repeating: 7, count: 6))
    let pace = try #require(metrics(history, vacation: true).pace)
    #expect(pace.nextLevelRange == nil)
    #expect(pace.validation?.trials.count == 3)
  }
}
