import Foundation
import StudyCore
import Testing

struct KatakanaPracticeTests {
  @Test func deckPreservesOriginalCardsAndAcceptedReadings() {
    #expect(KatakanaPractice.characters.count == 107)
    #expect(Set(KatakanaPractice.characters).count == 106)
    #expect(KatakanaPractice.characters.filter { $0 == "エ" }.count == 2)
    #expect(KatakanaPractice.characters.first == "ア" && KatakanaPractice.characters.last == "ン")
    for index in KatakanaPractice.characters.indices {
      let subject = KatakanaPractice.subject(at: index)
      #expect(subject.japanese == KatakanaPractice.characters[index])
      #expect(subject.meanings.isEmpty && subject.kind == .vocabulary)
      #expect(
        subject.primaryReadings[0].applyingTransform(.hiraganaToKatakana, reverse: false)
          == subject.japanese)
    }
  }
  @Test func completeDeckNeverProducesAnAccountSubmission() throws {
    var practice = try KatakanaPractice(seed: 1)
    for _ in KatakanaPractice.characters.indices {
      let question = try #require(practice.question)
      #expect(question.kind == .reading)
      let answer = try #require(practice.subject?.primaryReadings.first)
      let result = try practice.answer(answer, for: question)
      #expect(result.grade == .precise)
      #expect(practice.session.completedSubmissions.isEmpty)
    }
    #expect(practice.question == nil && practice.subject == nil)
    #expect(practice.session.completedIDs.count == 107)
    #expect(practice.session.tasksAnswered == 107 && practice.session.successRate == 100)
    #expect(practice.session.isPractice)
  }
  @Test func wrongAnswerRetryAndCorrectionUseSharedAccounting() throws {
    var practice = try KatakanaPractice(seed: 1)
    let question = try #require(practice.question)
    #expect(try practice.answer("neko", for: question).grade == .incorrect)
    #expect(practice.question == question && practice.session.successRate == 0)
    try practice.correct(question)
    #expect(practice.session.successRate == 100 && practice.session.completedIDs.count == 1)
    #expect(practice.session.items[question.itemID]?.reading.wrongCount == 0)
    #expect(practice.session.completedSubmissions.isEmpty)
    #expect(throws: StudySessionError.staleQuestion) { try practice.correct(question) }
    let next = try #require(practice.question)
    #expect(try practice.answer("neko", for: next).grade == .incorrect)
    #expect(try practice.answer("i", for: next).grade == .precise)
    #expect(practice.session.items[next.itemID]?.reading.wrongCount == 1)
    #expect(practice.session.successRate == 66)
  }
  @Test func invalidInputAndDeferralDoNotMarkAnAnswer() throws {
    var practice = try KatakanaPractice(seed: 1)
    let question = try #require(practice.question)
    let invalid = try practice.answer("猫", for: question, convertRomaji: false)
    guard case .containsInvalidCharacters = invalid.grade else {
      Issue.record("Non-kana input should remain ungraded")
      return
    }
    #expect(practice.session.tasksAnswered == 0)
    #expect(throws: StudySessionError.staleQuestion) { try practice.advance(question) }
    try practice.deferQuestion(question)
    #expect(practice.question?.itemID != question.itemID)
    #expect(practice.session.tasksAnswered == 0 && practice.session.completedIDs.isEmpty)
    #expect(throws: StudySessionError.staleQuestion) {
      try practice.answer("あ", for: question, convertRomaji: false)
    }
    #expect(practice.session.completedSubmissions.isEmpty)
  }
  @Test func incorrectAdvanceReturnsCardLaterWithoutLosingPenalty() throws {
    var practice = try KatakanaPractice(seed: 1)
    let first = try #require(practice.question)
    _ = try practice.answer("neko", for: first)
    try practice.advance(first)
    #expect(practice.question?.itemID != first.itemID)
    #expect(practice.session.items[first.itemID]?.reading.wrongCount == 1)
    #expect(practice.session.tasksAnswered == 1 && practice.session.completedSubmissions.isEmpty)
    var count = 0
    while let question = practice.question, count < 120 {
      let answer = try #require(practice.subject?.primaryReadings.first)
      _ = try practice.answer(answer, for: question)
      count += 1
    }
    #expect(practice.question == nil && practice.session.completedIDs.count == 107)
    #expect(practice.session.items[first.itemID]?.reading.wrongCount == 1)
    #expect(practice.session.completedSubmissions.isEmpty)
  }
  @Test(arguments: [StudySessionOptions.AnkiMode.off, .meaning, .reading, .both])
  func ankiModeUsesTheReadingPreferenceWithoutRebuildingCards(_ mode: StudySessionOptions.AnkiMode)
    throws
  {
    var options = StudySessionOptions()
    options.ankiMode = mode
    var practice = try KatakanaPractice(options: options, seed: 1)
    #expect(practice.isAnki == mode.includes(.reading))
    let question = try #require(practice.question)
    let queued = practice.session.queuedIDs
    options.ankiMode = mode == .off ? .reading : .off
    options.incorrectAnswerDelay = 12
    practice.options = options
    #expect(practice.isAnki == options.ankiMode.includes(.reading))
    #expect(practice.question == question && practice.session.queuedIDs == queued)
    #expect(practice.session.tasksAnswered == 0 && practice.summary.entries.isEmpty)
    #expect(practice.session.completedSubmissions.isEmpty)
  }

  @Test func ankiAssessmentCompletesTheOriginalDeckWithoutSRSClaimsOrUploads() throws {
    var options = StudySessionOptions()
    options.ankiMode = .reading
    var practice = try KatakanaPractice(options: options, seed: 1)
    for id in KatakanaPractice.characters.indices {
      let question = try #require(practice.question)
      #expect(question.itemID == id && question.kind == .reading)
      let mark = try practice.assess(correct: true, for: question)
      #expect(mark.subjectFinished && !mark.didLevelUp && mark.estimatedMilestone == nil)
      #expect(mark.submission == nil && practice.session.completedSubmissions.isEmpty)
      #expect(throws: StudySessionError.staleQuestion) {
        try practice.assess(correct: true, for: question)
      }
    }
    #expect(practice.question == nil && practice.session.tasksAnswered == 107)
    #expect(practice.summary.entries.map(\.id) == Array(KatakanaPractice.characters.indices))
    #expect(practice.summary.correctCount == 107 && practice.summary.accuracy == 100)
    #expect(practice.summary.missedGroups.isEmpty)
    #expect(practice.summary.entries.filter { $0.subject?.characters == "エ" }.count == 2)
  }

  @Test func incorrectAnkiAssessmentRequeuesAndPreservesItsMissedReadingInSummary() throws {
    var options = StudySessionOptions()
    options.ankiMode = .both
    options.incorrectAnswerDelay = 2
    var practice = try KatakanaPractice(options: options, seed: 1)
    let first = try #require(practice.question)
    let incorrect = try practice.assess(correct: false, for: first)
    #expect(!incorrect.subjectFinished && incorrect.submission == nil)
    #expect(practice.question?.itemID == 1 && practice.session.tasksAnswered == 1)
    #expect(practice.summary.entries.isEmpty)
    #expect(throws: StudySessionError.staleQuestion) {
      try practice.assess(correct: false, for: first)
    }
    var count = 0
    while let question = practice.question, count < 110 {
      try practice.assess(correct: true, for: question)
      count += 1
    }
    #expect(practice.question == nil && practice.session.tasksAnswered == 108)
    #expect(practice.session.successRate == 99 && practice.session.completedSubmissions.isEmpty)
    let missed = try #require(practice.summary.missedGroups.first)
    #expect(missed.id == 0 && missed.entries.count == 1)
    let entry = try #require(missed.entries.first)
    #expect(entry.id == first.itemID && entry.subject?.characters == "ア")
    #expect(entry.subject?.readings == ["あ"] && !entry.meaningWrong && entry.readingWrong)
    #expect(practice.summary.correctCount == 106 && practice.summary.accuracy == 99)
  }

  @Test func summaryCountsCompletedCardsAndRespectsCorrectionsRatherThanAttemptAccuracy() throws {
    var practice = try KatakanaPractice(seed: 1)
    let first = try #require(practice.question)
    _ = try practice.answer("neko", for: first)
    #expect(practice.summary.entries.isEmpty)
    _ = try practice.answer("a", for: first)
    let second = try #require(practice.question)
    _ = try practice.answer("neko", for: second)
    try practice.correct(second)
    let unfinished = try #require(practice.question)
    _ = try practice.answer("猫", for: unfinished, convertRomaji: false)
    #expect(practice.session.successRate == 66)
    #expect(practice.summary.entries.map(\.id) == [first.itemID, second.itemID])
    #expect(practice.summary.correctCount == 1 && practice.summary.accuracy == 50)
    #expect(practice.summary.entries[0].readingWrong && !practice.summary.entries[1].readingWrong)
    #expect(practice.summary.entries.allSatisfy { !$0.meaningWrong && $0.level == 0 })
    #expect(practice.session.completedSubmissions.isEmpty)
  }
}
