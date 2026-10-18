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
}
