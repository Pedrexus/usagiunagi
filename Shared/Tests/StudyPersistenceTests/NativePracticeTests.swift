import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

struct NativePracticeTests {
  private let account = "fixture-user-id"
  private let now = Date(timeIntervalSince1970: 1_792_300_000)
  private func download() async throws -> StudyDownload {
    var value = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    value.assignments[0].srsStage = 3
    value.assignments[0].passedAt = nil
    value.assignments[0].availableAt = 1
    return value
  }
  private func apply(_ value: StudyDownload, to store: StudyStore) async throws {
    _ = try await store.applyDownload(
      value, credentialID: "fixture", baseline: store.refreshBaseline(accountID: account))
  }
  private func store(at url: URL = URL(filePath: "/unused")) async throws -> StudyStore {
    let store = try await StudyStore.open(at: url, inMemory: url.path == "/unused")
    try await apply(download(), to: store)
    return store
  }
  private func complete(_ initial: NativeReviewState, in store: StudyStore) async throws
    -> NativeReviewState
  {
    var state = initial
    for _ in 0..<12 {
      guard let question = state.question else { break }
      if state.isAnki {
        if state.saved.session.currentDecision == nil {
          state = try await store.revealAnki(
            question: question, accountID: account, expectedRevision: state.saved.revision, now: now
          )
        }
        state = try await store.assessAnki(
          correct: true, question: question, accountID: account,
          expectedRevision: state.saved.revision, now: now)
      } else {
        state = try await store.answerReview(
          question.kind == .meaning ? "one" : "いち", question: question,
          accountID: account, expectedRevision: state.saved.revision, now: now
        ).state
      }
    }
    #expect(state.question == nil)
    return state
  }
  @Test(arguments: [StudySessionOptions.AnkiMode.off, .both])
  func practiceUsesTheGraderWithoutChangingProgressOrCreatingUploads(
    mode: StudySessionOptions.AnkiMode
  ) async throws {
    let store = try await store()
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let before = try encoder.encode(await store.accountState(accountID: account))
    let assignments = try await store.assignments(accountID: account)
    var options = StudySessionOptions()
    options.ankiMode = mode
    options.combinedAnki = mode == .both
    let initial = try await store.openPractice(
      accountID: account, scope: .recentLessons, options: options, now: now)
    #expect(initial.isPractice && initial.saved.session.practiceScope == .recentLessons)
    let done = try await complete(initial, in: store)
    #expect(
      done.saved.session.completedIDs.count == 1 && done.saved.session.completedSubmissions.isEmpty)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    #expect(try await store.assignments(accountID: account) == assignments)
    #expect(try encoder.encode(await store.accountState(accountID: account)) == before)
    try await store.finishReviews(accountID: account, expectedRevision: done.saved.revision)
    #expect(try await store.homeData(accountID: account, now: now).reviews == 1)
  }
  @Test func pausedPracticeSurvivesRestartAndCannotBeReplacedByOtherSessions() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let store = try await store(at: url)
    let opened = try await store.openPractice(accountID: account, scope: .recentLessons)
    let question = try #require(opened.question)
    let wrong = try await store.answerReview(
      question.kind == .meaning ? "unrelated" : "ぜんぜん", question: question,
      accountID: account, expectedRevision: opened.saved.revision, now: now
    ).state
    let reopened = try await StudyStore.open(at: url)
    let resumed = try await reopened.openPractice(accountID: account, scope: .recentLessons)
    #expect(resumed.question == question && resumed.saved.revision == wrong.saved.revision)
    #expect(resumed.saved.session.currentDecision == .incorrect)
    await #expect(throws: NativeReviewError.self) {
      try await reopened.openReviews(accountID: account)
    }
    await #expect(throws: NativeReviewError.self) {
      try await reopened.openLessons(accountID: account, subjectIDs: [2])
    }
    await #expect(throws: NativeReviewError.self) {
      try await reopened.openPractice(accountID: account, scope: .burned)
    }
    #expect(try await reopened.session(accountID: account)?.revision == wrong.saved.revision)
    #expect(try await reopened.pendingReviews(accountID: account).isEmpty)
    let next = try await reopened.changeReview(
      .advance, accountID: account, expectedRevision: resumed.saved.revision)
    let done = try await complete(next, in: reopened)
    #expect(
      try await reopened.accountState(accountID: account)?.progress.allSatisfy {
        $0.lastMistakeAt == nil
      } == true)
    try await reopened.finishReviews(accountID: account, expectedRevision: done.saved.revision)
  }
  @Test func vacationAndServerScheduleChangesDoNotTurnPracticeIntoScheduledReviews() async throws {
    let store = try await store()
    var value = try await download()
    value.profile.vacationStartedAt = 1
    try await apply(value, to: store)
    await #expect(throws: NativeReviewError.self) {
      try await store.openReviews(accountID: account)
    }
    let initial = try await store.openPractice(accountID: account, scope: .recentLessons)
    value.assignments[0].srsStage = 9
    value.assignments[0].availableAt = nil
    try await apply(value, to: store)
    let done = try await complete(initial, in: store)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    try await store.finishReviews(accountID: account, expectedRevision: done.saved.revision)
    let burned = try await store.openPractice(accountID: account, scope: .burned)
    value.subjects[0].hiddenAt = 1
    try await apply(value, to: store)
    let question = try #require(burned.question)
    await #expect(throws: NativeReviewError.self) {
      try await store.answerReview(
        "one", question: question, accountID: account, expectedRevision: burned.saved.revision)
    }
    #expect(try await store.session(accountID: account)?.revision == burned.saved.revision)
  }
  @Test func practiceFencesStaleWindowsAndKeepsTheStoredScopeImmutable() async throws {
    let store = try await store()
    let initial = try await store.openPractice(accountID: account, scope: .recentLessons)
    let question = try #require(initial.question)
    let wrong = try await store.answerReview(
      question.kind == .meaning ? "unrelated" : "ぜんぜん", question: question, accountID: account,
      expectedRevision: initial.saved.revision
    ).state
    await #expect(throws: StudyStoreError.self) {
      try await store.answerReview(
        "one", question: question, accountID: account, expectedRevision: initial.saved.revision)
    }
    var changed = try StudySession(
      items: Array(wrong.saved.session.items.values), isPractice: true, practiceScope: .burned)
    changed.nextQuestion()
    await #expect(throws: StudyStoreError.self) {
      try await store.saveSession(
        changed, accountID: account, expectedRevision: wrong.saved.revision)
    }
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
  @Test(arguments: [false, true])
  func realMistakesCommitWithCompletedAnswersAndSurviveRefresh(overridden: Bool) async throws {
    let store = try await store()
    let initial = try await store.openReviews(accountID: account, now: now)
    let question = try #require(initial.question)
    let wrong = try await store.answerReview(
      question.kind == .meaning ? "unrelated" : "ぜんぜん", question: question, accountID: account,
      expectedRevision: initial.saved.revision, now: now
    ).state
    #expect(
      try await store.accountState(accountID: account)?.progress.allSatisfy {
        $0.lastMistakeAt == nil
      } == true)
    let next = try await store.changeReview(
      overridden ? .overrideCorrect : .advance, accountID: account,
      expectedRevision: wrong.saved.revision, now: now)
    let done = try await complete(next, in: store)
    let progress = try await store.accountState(accountID: account)?.progress.first {
      $0.subjectID == 1
    }
    #expect(progress?.lastMistakeAt == (overridden ? nil : Int64(now.timeIntervalSince1970)))
    #expect(
      try await store.homeData(accountID: account, now: now).scheduleUnavailableMessage != nil)
    #expect(try await store.homeData(accountID: account, now: now).reviews == 0)
    try await store.finishReviews(accountID: account, expectedRevision: done.saved.revision)
    try await apply(download(), to: store)
    let refreshed = try await store.accountState(accountID: account)?.progress.first {
      $0.subjectID == 1
    }
    #expect(refreshed?.lastMistakeAt == progress?.lastMistakeAt)
    #expect(try await store.pendingReviews(accountID: account).count == 1)
  }
  @Test func homeCountsAndResumeAgreeWithTheSessionsTheyOpen() async throws {
    let store = try await store()
    let data = try await store.homeData(accountID: account, now: now)
    #expect(data.reviews == 1 && data.recentLessons == 1 && data.apprenticePractice == 0)
    #expect(data.hourlyReviews.count == 25 && data.hourlyReviews[0] == 1)
    let practice = try await store.openPractice(accountID: account, scope: .recentLessons)
    #expect(practice.saved.session.items.count == data.recentLessons)
    #expect(
      try await store.homeData(accountID: account, now: now).resumeTitle == "Resume recent lessons")
    await #expect(throws: NativeReviewError.self) {
      try await store.openReviews(accountID: account)
    }
    try await store.endReviews(accountID: account, expectedRevision: practice.saved.revision)
    let review = try await store.openReviews(accountID: account, now: now)
    #expect(review.saved.session.items.count == data.reviews)
    await #expect(throws: NativeReviewError.self) {
      try await store.openPractice(accountID: account, scope: .recentLessons)
    }
    #expect(try await store.homeData(accountID: account, now: now).resumeTitle == "Resume reviews")
  }
}
