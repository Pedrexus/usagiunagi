import StudyCore
import Testing

struct StudySessionSummaryTests {
  private func entry(
    _ id: Int, level: Int = 1, meaningWrong: Bool = false, readingWrong: Bool = false
  ) -> StudySessionSummary.Entry {
    .init(
      id: id, subject: nil, level: level, meaningWrong: meaningWrong, readingWrong: readingWrong)
  }
  @Test func eitherMissedAnswerMakesACompletedSubjectIncorrect() {
    let summary = StudySessionSummary(entries: [
      entry(0), entry(1, meaningWrong: true), entry(2, readingWrong: true),
      entry(3, meaningWrong: true, readingWrong: true),
    ])
    #expect(summary.correctCount == 1 && summary.accuracy == 25)
    #expect(summary.missedGroups[0].entries.map(\.id) == [1, 2, 3])
  }
  @Test func emptyAndFractionalAccuracyMatchTheLegacySummary() {
    #expect(StudySessionSummary(entries: []).accuracy == nil)
    let summary = StudySessionSummary(entries: [entry(0), entry(1), entry(2, readingWrong: true)])
    #expect(summary.accuracy == 66)
  }
  @Test func missingContentStillCountsAndLevelsKeepDescendingStableOrder() {
    let summary = StudySessionSummary(
      entries: [
        entry(0, level: 3, meaningWrong: true), entry(1, level: 10, readingWrong: true),
        entry(2, level: 3, meaningWrong: true), entry(3, level: 9),
      ], currentLevel: 3)
    #expect(summary.correctCount == 1 && summary.entries.count == 4)
    #expect(summary.currentLevel == 3)
    #expect(summary.missedGroups.map(\.id) == [10, 3])
    #expect(summary.missedGroups[1].entries.map(\.id) == [0, 2])
  }
  @Test func repeatedPracticeSubjectsHaveSeparateResultIdentities() {
    let subject = StudySubject(
      id: 0, characters: "エ", meaning: "", readings: ["え"], kind: .vocabulary)
    let summary = StudySessionSummary(
      entries: (0...1).map {
        .init(id: $0, subject: subject, level: 0, meaningWrong: false, readingWrong: true)
      })
    #expect(summary.missedGroups[0].entries.map(\.id) == [0, 1])
    #expect(summary.correctCount == 0 && summary.accuracy == 0)
  }
}
