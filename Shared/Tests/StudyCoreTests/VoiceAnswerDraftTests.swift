import Foundation
import StudyCore
import Testing

struct VoiceAnswerDraftTests {
  private func question(reading: Bool = false) throws -> StudyQuestion {
    var session = try StudySession(items: [
      StudySessionItem(
        id: 0, subjectID: 1, assignmentID: 1, srsStage: 1,
        hasMeaning: !reading, hasReading: reading)
    ])
    let value = session.nextQuestion()
    return try #require(value)
  }

  @Test(arguments: [false, true])
  func interimCancelledAndStaleResultsCannotBecomeAnswers(reading: Bool) throws {
    let question = try question(reading: reading)
    let id = UUID()
    var draft = VoiceAnswerDraft(question: question, recordingID: id)
    let interim = draft.receive(
      text: "wrong", start: 0, end: 1, isFinal: false, recordingID: id, question: question,
      alternatives: ["いち"])
    #expect(!interim && draft.transcript.isEmpty)
    #expect(draft.answer(for: question) == nil)
    let stale = draft.receive(
      text: "wrong", start: 0, end: 1, isFinal: true, recordingID: UUID(), question: question,
      alternatives: ["いち"])
    #expect(!stale)
    #expect(draft.transcript.isEmpty && draft.readingSuggestions.isEmpty)
    draft.cancel()
    let cancelled = draft.receive(
      text: "one", start: 0, end: 1, isFinal: true, recordingID: id, question: question)
    draft.finish(recordingID: id, question: question)
    #expect(!cancelled && draft.answer(for: question) == nil)
    #expect(draft.readingSuggestions.isEmpty)
  }

  @Test func onlyFinalOrderedSegmentsFormTheDraft() throws {
    let question = try question()
    let id = UUID()
    var draft = VoiceAnswerDraft(question: question, recordingID: id)
    draft.receive(
      text: " eat.", start: 1, end: 2, isFinal: true, recordingID: id, question: question,
      alternatives: ["たべる"])
    draft.receive(
      text: "To", start: 0, end: 1, isFinal: true, recordingID: id, question: question,
      alternatives: ["と"])
    draft.receive(
      text: "To", start: 0, end: 1, isFinal: true, recordingID: id, question: question,
      alternatives: ["と"])
    #expect(draft.answer(for: question) == nil)
    draft.finish(recordingID: id, question: question)
    #expect(draft.answer(for: question) == "To eat")
    #expect(draft.readingSuggestions.isEmpty)
    let late = draft.receive(
      text: "changed", start: 0, end: 2, isFinal: true, recordingID: id, question: question)
    #expect(!late && draft.answer(for: question) == "To eat")
  }

  @Test func realSegmentAlternativesCanOfferKanaWithoutChangingWhatWasHeard() throws {
    let question = try question(reading: true)
    let id = UUID()
    var draft = VoiceAnswerDraft(question: question, recordingID: id)
    // Observed local SpeechTranscriber output, delivered out of order here.
    draft.receive(
      text: "つ", start: 0.3, end: 0.7085, isFinal: true, recordingID: id, question: question,
      alternatives: ["つ", "とつ"])
    draft.receive(
      text: "1", start: 0, end: 0.3, isFinal: true, recordingID: id, question: question,
      alternatives: ["1", "ひ", "一"])
    #expect(draft.readingSuggestions.isEmpty && draft.answer(for: question) == nil)
    draft.finish(recordingID: id, question: question)
    #expect(draft.readingSuggestions == ["ひつ", "ひとつ"])
    #expect(draft.transcript == "1つ" && draft.answer(for: question) == "1つ")
    #expect(VoiceAnswerDraft.needsKanaCorrection(draft.transcript))
    draft.cancel()
    #expect(draft.readingSuggestions.isEmpty && draft.answer(for: question) == nil)
  }

  @Test(arguments: [
    (["あ", "い", "う", "え"], ["か", "き", "く", "け"], 6),
    (["ひ", "ひと"], ["つ", "とつ"], 3),
    (["", "一", "1", "one"], ["つ", "とつ"], 0),
  ])
  func kanaCombinationsStayUniqueBoundedAndReplaceEarlierResults(
    first: [String], second: [String], count: Int
  ) throws {
    let question = try question(reading: true)
    let id = UUID()
    var draft = VoiceAnswerDraft(question: question, recordingID: id)
    draft.receive(
      text: "旧", start: 0, end: 1, isFinal: true, recordingID: id, question: question,
      alternatives: ["ふるい"])
    draft.receive(
      text: "漢", start: 0, end: 1, isFinal: true, recordingID: id, question: question,
      alternatives: first)
    draft.receive(
      text: "字", start: 1, end: 2, isFinal: true, recordingID: id, question: question,
      alternatives: second)
    draft.finish(recordingID: id, question: question)
    let suggestions = draft.readingSuggestions
    #expect(suggestions.count == count && Set(suggestions).count == count)
    #expect(
      suggestions.allSatisfy {
        !$0.isEmpty && !VoiceAnswerDraft.needsKanaCorrection($0) && !$0.hasPrefix("ふるい")
      })
    #expect(draft.answer(for: question) == "漢字")
  }

  @Test func japaneseJoinsWithoutSpacesAndDoesNotInventKanjiReadings() throws {
    let question = try question(reading: true)
    let id = UUID()
    var draft = VoiceAnswerDraft(question: question, recordingID: id)
    draft.receive(text: "い", start: 0, end: 1, isFinal: true, recordingID: id, question: question)
    draft.receive(text: "ち。", start: 1, end: 2, isFinal: true, recordingID: id, question: question)
    draft.finish(recordingID: id, question: question)
    #expect(draft.answer(for: question) == "いち")
    #expect(VoiceAnswerDraft.needsKanaCorrection("一"))
    #expect(!VoiceAnswerDraft.needsKanaCorrection("イチ。"))
    #expect(!VoiceAnswerDraft.needsKanaCorrection("びーる"))
    #expect(VoiceAnswerDraft.cleanTranscript("一。") == "一")
  }

  @Test func finishedAnswerBelongsToTheOriginalQuestion() throws {
    var session = try StudySession(items: [
      StudySessionItem(id: 0, subjectID: 1, assignmentID: 1, srsStage: 1)
    ])
    let firstValue = session.nextQuestion()
    let first = try #require(firstValue)
    let id = UUID()
    var draft = VoiceAnswerDraft(question: first, recordingID: id)
    draft.receive(text: "One", start: 0, end: 1, isFinal: true, recordingID: id, question: first)
    draft.finish(recordingID: id, question: first)
    let nextValue = session.nextQuestion()
    let next = try #require(nextValue)
    #expect(draft.answer(for: first) == "One")
    #expect(draft.answer(for: next) == nil)
  }
}
