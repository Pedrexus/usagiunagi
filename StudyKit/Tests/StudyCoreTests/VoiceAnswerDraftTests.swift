import Foundation
import Testing
import StudyCore

struct VoiceAnswerDraftTests {
    private func question(reading: Bool = false) throws -> StudyQuestion {
        var session = try StudySession(items: [StudySessionItem(id: 0, subjectID: 1, assignmentID: 1, srsStage: 1,
            hasMeaning: !reading, hasReading: reading)])
        let value = session.nextQuestion()
        return try #require(value)
    }

    @Test func interimCancelledAndStaleResultsCannotBecomeAnswers() throws {
        let question = try question()
        let id = UUID()
        var draft = VoiceAnswerDraft(question: question, recordingID: id)
        let interim = draft.receive(text: "wrong", start: 0, end: 1, isFinal: false, recordingID: id, question: question)
        #expect(!interim && draft.transcript.isEmpty)
        #expect(draft.answer(for: question) == nil)
        let stale = draft.receive(text: "wrong", start: 0, end: 1, isFinal: true, recordingID: UUID(), question: question)
        #expect(!stale)
        draft.cancel()
        let cancelled = draft.receive(text: "one", start: 0, end: 1, isFinal: true, recordingID: id, question: question)
        draft.finish(recordingID: id, question: question)
        #expect(!cancelled && draft.answer(for: question) == nil)
    }

    @Test func onlyFinalOrderedSegmentsFormTheDraft() throws {
        let question = try question()
        let id = UUID()
        var draft = VoiceAnswerDraft(question: question, recordingID: id)
        draft.receive(text: " eat.", start: 1, end: 2, isFinal: true, recordingID: id, question: question)
        draft.receive(text: "To", start: 0, end: 1, isFinal: true, recordingID: id, question: question)
        draft.receive(text: "To", start: 0, end: 1, isFinal: true, recordingID: id, question: question)
        #expect(draft.answer(for: question) == nil)
        draft.finish(recordingID: id, question: question)
        #expect(draft.answer(for: question) == "To eat")
        let late = draft.receive(text: "changed", start: 0, end: 2, isFinal: true, recordingID: id, question: question)
        #expect(!late && draft.answer(for: question) == "To eat")
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
        var session = try StudySession(items: [StudySessionItem(id: 0, subjectID: 1, assignmentID: 1, srsStage: 1)])
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
