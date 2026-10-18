import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

struct NativeAnkiTests {
  private let account = "fixture-user-id"
  private let now = Date(timeIntervalSince1970: 2_000_000_000)
  private func store(at url: URL = URL(filePath: "/unused")) async throws -> StudyStore {
    let store = try await StudyStore.open(at: url, inMemory: url.path == "/unused")
    _ = try await store.refresh(
      credentialID: "fixture", token: "fixture", client: .init(transport: DownloadFixture.response))
    return store
  }
  private func options(
    _ mode: StudySessionOptions.AnkiMode = .both, combined: Bool = false,
    meaningFirst: Bool = true
  ) -> StudySessionOptions {
    var value = StudySessionOptions()
    value.ankiMode = mode
    value.groupMeaningReading = true
    value.combinedAnki = combined
    value.meaningFirst = meaningFirst
    value.incorrectAnswerDelay = 0
    return value
  }
  private func reveal(_ state: NativeReviewState, in store: StudyStore) async throws
    -> NativeReviewState
  {
    try await store.revealAnki(
      question: #require(state.question), accountID: account,
      expectedRevision: state.saved.revision, now: now)
  }
  private func assess(_ state: NativeReviewState, correct: Bool = true, in store: StudyStore)
    async throws -> NativeReviewState
  {
    try await store.assessAnki(
      correct: correct, question: #require(state.question), accountID: account,
      expectedRevision: state.saved.revision, now: now)
  }
  @Test(arguments: [true, false]) func combinedCardCommitsBothSidesOnceAndUsesTheSelectedOrder(
    meaningFirst: Bool
  ) async throws {
    let store = try await store()
    let opened = try await store.openReviews(
      accountID: account, options: options(combined: true, meaningFirst: meaningFirst), now: now)
    #expect(opened.isAnki && opened.combinesAnki)
    #expect(opened.question?.kind == (meaningFirst ? .meaning : .reading))
    let shown = try await reveal(opened, in: store)
    #expect(shown.saved.session.currentDecision == .incorrect)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    let done = try await assess(shown, in: store)
    #expect(done.question == nil && done.saved.session.tasksAnswered == 2)
    #expect(done.saved.session.successRate == 100 && done.success?.subjectFinished == true)
    let pending = try #require(await store.pendingReviews(accountID: account).first)
    #expect(!pending.submission.meaningWrong && !pending.submission.readingWrong)
    #expect(pending.submission.meaningWrongCount == 0 && pending.submission.readingWrongCount == 0)
    await #expect(throws: StudyStoreError.self) { try await assess(shown, in: store) }
    #expect(try await store.pendingReviews(accountID: account).count == 1)
  }
  @Test(arguments: [StudySessionOptions.AnkiMode.meaning, .reading], [true, false])
  func oneSidedAnkiKeepsTheOtherSideTyped(mode: StudySessionOptions.AnkiMode, meaningFirst: Bool)
    async throws
  {
    let store = try await store()
    var state = try await store.openReviews(
      accountID: account, options: options(mode, combined: true, meaningFirst: meaningFirst),
      now: now)
    #expect(!state.saved.session.options.combinedAnki)
    var typed = 0
    var assessed = 0
    for _ in 0..<4 {
      guard let question = state.question else { break }
      if state.isAnki {
        assessed += 1
        state = try await assess(reveal(state, in: store), in: store)
      } else {
        typed += 1
        state = try await store.answerReview(
          question.kind == .meaning ? "one" : "いち",
          question: question, accountID: account, expectedRevision: state.saved.revision, now: now
        ).state
      }
    }
    #expect(typed == 1 && assessed == 1 && state.question == nil)
    #expect(state.saved.session.successRate == 100)
    #expect(try await store.pendingReviews(accountID: account).count == 1)
  }
  @Test func incorrectCombinedCardRetriesWithoutCreditingTheOtherSide() async throws {
    let store = try await store()
    let opened = try await store.openReviews(
      accountID: account, options: options(combined: true), now: now)
    let shown = try await reveal(opened, in: store)
    let retry = try await assess(shown, correct: false, in: store)
    let item = try #require(retry.saved.session.items[0])
    #expect(item.meaning.firstAnswerWrong == true && item.meaning.wrongCount == 1)
    #expect(!item.reading.hasAttempts && retry.question?.kind == .meaning)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    let done = try await assess(reveal(retry, in: store), in: store)
    let submission = try #require(await store.pendingReviews(accountID: account).first?.submission)
    #expect(submission.meaningWrong && !submission.readingWrong)
    #expect(submission.meaningWrongCount == 2 && submission.readingWrongCount == 0)
    #expect(done.saved.session.successRate == 66)
  }
  @Test func revealAndSavedModeSurviveReopenWithoutReplayingOrReplacingChoices() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let shown: NativeReviewState
    do {
      let store = try await store(at: url)
      let opened = try await store.openReviews(
        accountID: account, options: options(combined: true), now: now)
      shown = try await reveal(opened, in: store)
    }
    let reopened = try await StudyStore.open(at: url)
    let resumed = try await reopened.openReviews(accountID: account, options: .init(), now: now)
    #expect(
      resumed.saved.revision == shown.saved.revision && resumed.isAnki && resumed.combinesAnki)
    #expect(resumed.saved.session.currentDecision == .incorrect && resumed.success == nil)
    await #expect(throws: StudySessionError.alreadyAnswered) {
      try await reveal(resumed, in: reopened)
    }
    let done = try await assess(resumed, in: reopened)
    try await reopened.finishReviews(accountID: account, expectedRevision: done.saved.revision)
    #expect(try await reopened.pendingReviews(accountID: account).count == 1)
  }
  @Test func wrongSurfaceAndUnrevealedStaleOrDuplicateDecisionsCannotCredit() async throws {
    let store = try await store()
    let opened = try await store.openReviews(accountID: account, options: options(), now: now)
    await #expect(throws: StudyStoreError.self) { try await assess(opened, in: store) }
    let question = try #require(opened.question)
    await #expect(throws: NativeReviewError.self) {
      try await store.answerReview(
        "one", question: question, accountID: account, expectedRevision: opened.saved.revision)
    }
    let shown = try await reveal(opened, in: store)
    await #expect(throws: StudyStoreError.self) { try await assess(opened, in: store) }
    await #expect(throws: StudySessionError.invalidOverride) {
      try await store.changeReview(
        .overrideCorrect, accountID: account, expectedRevision: shown.saved.revision)
    }
    let next = try await assess(shown, in: store)
    await #expect(throws: StudySessionError.staleQuestion) {
      try await store.assessAnki(
        correct: true, question: question, accountID: account, expectedRevision: next.saved.revision
      )
    }
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
  @Test func assignmentChangesBetweenRevealAndAssessmentPreserveTheSavedDecision() async throws {
    let store = try await store()
    let opened = try await store.openReviews(
      accountID: account, options: options(combined: true), now: now)
    let shown = try await reveal(opened, in: store)
    var download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    download.assignments[0].srsStage = 6
    _ = try await store.applyDownload(
      download, credentialID: "fixture", baseline: store.refreshBaseline(accountID: account))
    await #expect(throws: NativeReviewError.self) { try await assess(shown, in: store) }
    #expect(try await store.session(accountID: account)?.revision == shown.saved.revision)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
  @Test func lessonSelfAssessmentIsExplicitAndUsesTheExistingLessonOutbox() async throws {
    let store = try await store()
    var download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    download.assignments[0].srsStage = 0
    download.assignments[0].startedAt = nil
    download.assignments[0].availableAt = nil
    _ = try await store.applyDownload(
      download, credentialID: "fixture", baseline: store.refreshBaseline(accountID: account))
    let opened = try await store.openLessons(
      accountID: account, subjectIDs: [1], options: options(combined: true))
    let done = try await assess(reveal(opened, in: store), in: store)
    #expect(done.question == nil && done.saved.session.tasksAnswered == 2)
    #expect(try await store.pendingReviews(accountID: account).first?.submission.isLesson == true)
  }
  @Test func newNativeSessionsApplySkippingAndPenaltyOptions() async throws {
    let store = try await store()
    var configuration = options(.off)
    configuration.skipKanjiReadings = true
    configuration.minimizePenalty = true
    let opened = try await store.openReviews(accountID: account, options: configuration, now: now)
    let question = try #require(opened.question)
    #expect(question.kind == .meaning)
    let done = try await store.answerReview(
      "one", question: question, accountID: account,
      expectedRevision: opened.saved.revision, now: now
    ).state
    #expect(done.question == nil && done.saved.session.tasksAnswered == 1)
    #expect(done.saved.session.options == configuration)
    #expect(try await store.pendingReviews(accountID: account).count == 1)
  }

  @Test(arguments: [true, false]) func repeatedMistakesUseTheSelectedPenaltyRule(minimize: Bool)
    async throws
  {
    let store = try await store()
    var configuration = options(.off)
    configuration.minimizePenalty = minimize
    var state = try await store.openReviews(accountID: account, options: configuration, now: now)
    for _ in 0..<2 {
      let question = try #require(state.question)
      #expect(question.kind == .meaning)
      state = try await store.answerReview(
        "wrong", question: question, accountID: account,
        expectedRevision: state.saved.revision, now: now
      ).state
      state = try await store.changeReview(
        .advance, accountID: account, expectedRevision: state.saved.revision, now: now)
    }
    for _ in 0..<2 {
      let question = try #require(state.question)
      state = try await store.answerReview(
        question.kind == .meaning ? "one" : "いち",
        question: question, accountID: account, expectedRevision: state.saved.revision, now: now
      ).state
    }
    #expect(state.question == nil)
    let submission = try #require(await store.pendingReviews(accountID: account).first?.submission)
    #expect(submission.meaningWrong && !submission.readingWrong)
    #expect(submission.meaningWrongCount == (minimize ? 1 : 2))
  }

  @Test(arguments: [Int64(2), 3]) func combinedModeDoesNotInventReadingsForKanaVocabularyOrRadicals(
    id: Int64
  ) async throws {
    let store = try await store()
    var download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    var assignment = CatalogAssignment(
      id: id + 100, subjectID: id, kind: id == 3 ? .radical : .vocabulary)
    assignment.level = 1
    assignment.startedAt = 1
    assignment.availableAt = 1
    assignment.srsStage = 3
    assignment.isKanaOnlyVocabulary = id == 2
    download.assignments = [assignment]
    _ = try await store.applyDownload(
      download, credentialID: "fixture", baseline: store.refreshBaseline(accountID: account))
    let opened = try await store.openReviews(
      accountID: account, options: options(combined: true), now: now)
    #expect(opened.isAnki && !opened.combinesAnki)
    #expect(opened.question?.kind == .meaning)
    let done = try await assess(reveal(opened, in: store), in: store)
    #expect(done.question == nil && done.saved.session.tasksAnswered == 1)
    let submission = try #require(await store.pendingReviews(accountID: account).first?.submission)
    #expect(!submission.readingWrong && submission.readingWrongCount == 0)
  }

}
