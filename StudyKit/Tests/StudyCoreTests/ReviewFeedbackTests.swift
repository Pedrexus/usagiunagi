import StudyCore
import Testing

struct ReviewFeedbackTests {
  @Test(arguments: 1...8)
  func onlyNewSRSCategoriesHaveMilestones(_ stage: Int) throws {
    var session = try StudySession(items: [
      .init(id: 0, subjectID: 1, assignmentID: 1, srsStage: stage, hasReading: false)
    ])
    session.nextQuestion()
    let mark = try session.mark(.correct, for: #require(session.question), now: 10)
    #expect(mark.subjectFinished)
    #expect(
      mark.estimatedMilestone == [4: "Guru", 6: "Master", 7: "Enlightened", 8: "Burned"][stage])
  }

  @Test func partialAnswersAndPenalizedRetriesDoNotCelebrateASRSPromotion() throws {
    var session = try StudySession(items: [.init(id: 0, subjectID: 1, assignmentID: 1, srsStage: 4)]
    )
    session.nextQuestion()
    let first = try session.mark(.correct, for: #require(session.question), now: 10)
    #expect(!first.subjectFinished && first.estimatedMilestone == nil)
    session.nextQuestion()
    let question = try #require(session.question)
    let wrong = try session.mark(.incorrect, for: question, now: 10)
    #expect(wrong.estimatedMilestone == nil)
    let retry = try session.mark(.correct, for: question, now: 10)
    #expect(retry.subjectFinished && !retry.didLevelUp && retry.estimatedMilestone == nil)
  }

  @Test func explicitCorrectionUsesTheOriginalFirstAnswerRules() throws {
    var session = try StudySession(items: [
      .init(id: 0, subjectID: 1, assignmentID: 1, srsStage: 4, hasReading: false)
    ])
    session.nextQuestion()
    let question = try #require(session.question)
    _ = try session.mark(.incorrect, for: question, now: 10)
    let corrected = try session.mark(.overrideCorrect, for: question, now: 10)
    #expect(corrected.subjectFinished && corrected.estimatedMilestone == "Guru")
  }

  @Test func practiceCompletionHasNoSRSOrUploadClaim() throws {
    var practice = try KatakanaPractice(seed: 1)
    let question = try #require(practice.question)
    let reading = try #require(practice.subject?.primaryReadings.first)
    let result = try practice.answer(reading, for: question)
    let success = try #require(result.success)
    #expect(
      success.subjectFinished && success.submission == nil && success.estimatedMilestone == nil)
    let next = try #require(practice.question)
    let wrong = try practice.answer("ぜんぜん", for: next)
    #expect(wrong.grade == .incorrect && wrong.success == nil)
    let correction = try practice.correct(next)
    #expect(
      correction.subjectFinished && correction.submission == nil
        && correction.estimatedMilestone == nil)
  }
}
