import Foundation
import Testing
import StudyCore

struct StudySessionTests {
    private func advance(_ session: inout StudySession) throws -> StudyQuestion {
        let question = session.nextQuestion()
        return try #require(question)
    }
    private func item(_ id: Int = 0, meaning: Bool = true, reading: Bool = true, kanji: Bool = false,
                      available: Int64 = 0, lesson: Bool = false) -> StudySessionItem {
        StudySessionItem(id: id, subjectID: Int64(100 + id), assignmentID: Int64(200 + id),
                         srsStage: lesson ? 0 : 4, availableAt: available, isLesson: lesson,
                         isKanji: kanji, hasMeaning: meaning, hasReading: reading)
    }
    private var grouped: StudySessionOptions {
        var options = StudySessionOptions()
        options.groupMeaningReading = true
        return options
    }

    @Test func groupedQuestionsProduceOneSubmission() throws {
        var session = try StudySession(items: [item()], options: grouped, seed: 7)
        let meaning = try advance(&session)
        #expect(meaning.kind == .meaning)
        let first = try session.mark(.correct, for: meaning, now: 50)
        #expect(!first.subjectFinished && first.submission == nil)
        let reading = try advance(&session)
        #expect(reading.kind == .reading && reading.itemID == meaning.itemID)
        let last = try session.mark(.correct, for: reading, now: 60)
        #expect(last.subjectFinished && last.didLevelUp)
        #expect(last.estimatedSRSStage == 5)
        #expect(last.submission?.createdAt == 60)
        #expect(last.submission?.assignmentID == 200)
        #expect(last.submission?.meaningWrong == false && last.submission?.readingWrong == false)
        #expect(session.completedIDs == [0] && session.activeIDs.isEmpty)
        #expect(session.tasksAnswered == 2 && session.successRate == 100)
        #expect(throws: StudySessionError.staleQuestion) { try session.mark(.correct, for: reading, now: 61) }
    }

    @Test func overrideOnlyRepairsTheImmediatelyPrecedingFirstMistake() throws {
        var session = try StudySession(items: [item()], options: grouped, seed: 1)
        let question = try advance(&session)
        #expect(throws: StudySessionError.invalidOverride) { try session.mark(.overrideCorrect, for: question, now: 1) }
        _ = try session.mark(.incorrect, for: question, now: 2)
        _ = try session.mark(.overrideCorrect, for: question, now: 3)
        #expect(session.items[0]?.meaning.firstAnswerWrong == false)
        #expect(session.items[0]?.meaning.wrongCount == 0)
        #expect(session.tasksAnswered == 1 && session.tasksAnsweredCorrectly == 1)
        #expect(throws: StudySessionError.alreadyAnswered) { try session.mark(.overrideCorrect, for: question, now: 4) }
    }

    @Test func laterCorrectAnswerPreservesFirstMistakeAndPenalty() throws {
        var options = grouped
        options.incorrectAnswerDelay = 0
        var session = try StudySession(items: [item()], options: options, seed: 1)
        let question = try advance(&session)
        _ = try session.mark(.incorrect, for: question, now: 1)
        _ = try session.mark(.incorrect, for: question, now: 2)
        _ = try session.mark(.overrideCorrect, for: question, now: 3)
        #expect(session.items[0]?.meaning.firstAnswerWrong == true)
        #expect(session.items[0]?.meaning.wrongCount == 2)
        let next = try advance(&session)
        let result = try session.mark(.correct, for: next, now: 4)
        #expect(result.submission?.meaningWrong == true && result.submission?.meaningWrongCount == 2)
        #expect(!result.didLevelUp && result.estimatedSRSStage == 3)
        #expect(session.tasksAnswered == 3 && session.tasksAnsweredCorrectly == 2)
    }

    @Test func minimizedPenaltyAndPracticeNeverUploads() throws {
        var options = grouped
        options.minimizePenalty = true
        for practice in [false, true] {
            var session = try StudySession(items: [item(reading: false)], options: options, isPractice: practice, seed: 1)
            let question = try advance(&session)
            _ = try session.mark(.incorrect, for: question, now: 1)
            _ = try session.mark(.incorrect, for: question, now: 2)
            let finish = try session.mark(.correct, for: question, now: 3)
            #expect(session.items[0]?.meaning.wrongCount == 1)
            #expect(finish.subjectFinished)
            #expect((finish.submission == nil) == practice)
            #expect(finish.submission?.meaningWrongCount == (practice ? nil : 1))
        }
    }

    @Test func wrongAnswerDelayAllowsAnotherItemIntoTheBatch() throws {
        var session = try StudySession(items: [item(0), item(1), item(2)], options: grouped, seed: 1)
        let first = try advance(&session)
        _ = try session.mark(.incorrect, for: first, now: 1)
        let next = try advance(&session)
        #expect(next.itemID == 1)
        #expect(session.activeIDs == [0, 1] && session.queuedIDs == [2])
        #expect(session.items[0]?.returnDelay == 4)
        #expect(throws: StudySessionError.staleQuestion) { try session.mark(.correct, for: first, now: 2) }
    }

    @Test func wrapUpPreservesUnstartedItemsAndCanResumeRefilling() throws {
        var session = try StudySession(items: [item(0), item(1)], options: grouped, seed: 1)
        _ = session.nextQuestion()
        session.setWrappingUp(true)
        #expect(session.activeIDs.isEmpty && session.queuedIDs == [1, 0])
        let finishedQuestion = session.nextQuestion()
        #expect(finishedQuestion == nil)
        session.setWrappingUp(false)
        let next = try advance(&session)
        #expect(next.itemID == 1)
        _ = try session.mark(.correct, for: next, now: 1)
        #expect(session.canWrapUp)
        session.setWrappingUp(true)
        let last = try advance(&session)
        _ = try session.mark(.correct, for: last, now: 2)
        #expect(session.activeIDs.isEmpty && session.queuedIDs == [0])
    }

    @Test func deferAndExcludeResetAttemptsWithoutSubmitting() throws {
        var session = try StudySession(items: [item(0), item(1)], options: grouped, seed: 1)
        let question = try advance(&session)
        _ = try session.mark(.incorrect, for: question, now: 1)
        try session.deferQuestion(question)
        #expect(session.items[0]?.hasAttempts == false)
        #expect(session.queuedIDs == [0] && session.activeIDs == [1])
        let next = try advance(&session)
        try session.excludeQuestion(next)
        #expect(!session.activeIDs.contains(1) && !session.queuedIDs.contains(1))
        #expect(session.completedIDs.isEmpty)
        #expect(throws: StudySessionError.staleQuestion) { try session.mark(.correct, for: next, now: 2) }
    }

    @Test func readingCreditAndSkipKanjiOption() throws {
        var session = try StudySession(items: [item()], options: grouped, seed: 1)
        let question = try advance(&session)
        try session.creditReading(question)
        let finish = try session.mark(.correct, for: question, now: 1)
        #expect(finish.subjectFinished && session.tasksAnswered == 1)
        var skip = try StudySession(items: [item(kanji: true)], options: grouped, seed: 1)
        let prompt = try advance(&skip)
        skip.options.skipKanjiReadings = true // Quick settings remain live during a session.
        let skipped = try skip.mark(.correct, for: prompt, now: 1)
        #expect(skipped.subjectFinished)
    }

    @Test func practiceEntriesWithIdenticalSubjectIDsRemainDistinct() throws {
        let entries = (0..<3).map { StudySessionItem(id: $0, subjectID: 0, assignmentID: 0, srsStage: 0,
                                                     hasMeaning: false, hasReading: true) }
        var session = try StudySession(items: entries, isPractice: true, seed: 1)
        for expected in 0..<3 {
            let question = try advance(&session)
            #expect(question.itemID == expected && question.kind == .reading)
            let result = try session.mark(.correct, for: question, now: 1)
            #expect(result.submission == nil)
        }
        #expect(session.completedIDs == [0, 1, 2])
    }

    @Test func snapshotRestoresQuestionRandomOrderAndPendingMistakes() throws {
        var original = try StudySession(items: (0..<15).map { item($0) }, seed: 972)
        let question = try advance(&original)
        _ = try original.mark(.incorrect, for: question, now: 1)
        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(StudySession.self, from: data)
        #expect(original.question == restored.question)
        #expect(original.items == restored.items)
        let originalOverride = try original.mark(.overrideCorrect, for: question, now: 2)
        let restoredOverride = try restored.mark(.overrideCorrect, for: question, now: 2)
        #expect(originalOverride == restoredOverride)
        for time in 3..<32 {
            let a = try advance(&original)
            let b = try advance(&restored)
            #expect(a == b)
            let originalMark = try original.mark(.correct, for: a, now: Int64(time))
            let restoredMark = try restored.mark(.correct, for: b, now: Int64(time))
            #expect(originalMark == restoredMark)
        }
        #expect(original.items == restored.items && original.completedIDs == restored.completedIDs)
    }

    @Test func combinedAnkiKeepsBothAnswersOnTheSameItemAfterARetry() throws {
        var options = StudySessionOptions()
        options.combinedAnki = true
        options.incorrectAnswerDelay = 1
        for seed in 0..<30 {
            var session = try StudySession(items: [item(0), item(1)], options: options, seed: UInt64(seed))
            let first = try advance(&session)
            _ = try session.mark(.incorrect, for: first, now: 1)
            let second = try advance(&session)
            #expect(second.itemID == 1)
            _ = try session.mark(.correct, for: second, now: 2)
            let otherPart = session.nextQuestion(continuingCurrentItem: true)
            #expect(otherPart?.itemID == second.itemID)
            #expect(otherPart?.kind == .reading)
        }
    }

    @Test func lessonTimestampAndInputValidation() throws {
        var session = try StudySession(items: [item(reading: false, available: 100, lesson: true)], seed: 1)
        let question = try advance(&session)
        let result = try session.mark(.correct, for: question, now: 50)
        #expect(result.submission?.isLesson == true && result.submission?.createdAt == nil)
        #expect(result.estimatedSRSStage == 1)
        #expect(throws: StudySessionError.duplicateItemID) { try StudySession(items: [item(), item()]) }
        #expect(throws: StudySessionError.missingQuestionContent(0)) { try StudySession(items: [item(meaning: false, reading: false)]) }
        var options = StudySessionOptions()
        options.batchSize = 0
        var clamped = try StudySession(items: [item()], options: options, seed: 1)
        let clampedQuestion = clamped.nextQuestion()
        #expect(clampedQuestion != nil)
    }
}
