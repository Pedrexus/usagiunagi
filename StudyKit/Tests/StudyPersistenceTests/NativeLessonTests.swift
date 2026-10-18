import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

struct NativeLessonTests {
  private let account = "fixture-user-id"
  private func assignment(_ id: Int64, kind: SubjectKind = .kanji) -> CatalogAssignment {
    var value = CatalogAssignment(id: id + 100, subjectID: id, kind: kind)
    value.level = 1
    value.unlockedAt = 1
    value.isKanaOnlyVocabulary = id == 2
    return value
  }
  private func download() async throws -> StudyDownload {
    var value = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    value.assignments = [assignment(1), assignment(2, kind: .vocabulary)]
    return value
  }
  private func store(at url: URL = URL(filePath: "/unused")) async throws -> StudyStore {
    let value = try await StudyStore.open(at: url, inMemory: url.path == "/unused")
    _ = try await value.applyDownload(
      download(), credentialID: "fixture", baseline: value.refreshBaseline(accountID: account))
    return value
  }
  private func apply(_ download: StudyDownload, to store: StudyStore) async throws {
    _ = try await store.applyDownload(
      download, credentialID: "fixture",
      baseline: store.refreshBaseline(accountID: account))
  }
  private func complete(_ initial: NativeReviewState, in store: StudyStore) async throws
    -> NativeReviewState
  {
    var state = initial
    for _ in 0..<12 {
      guard let question = state.question else { break }
      state = try await store.answerReview(
        question.kind == .meaning ? "one" : "いち",
        question: question, accountID: account, expectedRevision: state.saved.revision
      ).state
    }
    #expect(state.question == nil)
    return state
  }
  @Test func selectionUsesUnlockedAccessibleVisibleContentAndHonorsExclusions() async throws {
    let store = try await store()
    var value = try await download()
    var locked = assignment(3, kind: .radical)
    locked.unlockedAt = nil
    var hidden = assignment(4)
    hidden.hidden = true
    value.assignments += [locked, hidden, assignment(5, kind: .vocabulary)]
    value.subjects[value.subjects.firstIndex { $0.id == 5 }!].level = 61
    try await apply(value, to: store)
    #expect(try await store.availableLessons(accountID: account).map(\.id) == [1, 2])
    try await store.saveMaterial(
      .init(subjectID: 2, meaningNote: StudyMaterial.exclusionMarker), accountID: account,
      expectedRevision: nil)
    #expect(try await store.availableLessons(accountID: account).map(\.id) == [1])
    value.assignments[0].startedAt = 1
    try await apply(value, to: store)
    #expect(try await store.availableLessons(accountID: account).isEmpty)
  }
  @Test func invalidSelectionDoesNotCreateSessionAndModesNeverReplacePausedWork() async throws {
    let store = try await store()
    for ids: [Int64] in [[], [1, 1], [999], [-1]] {
      await #expect(throws: NativeReviewError.self) {
        try await store.openLessons(accountID: account, subjectIDs: ids)
      }
      #expect(try await store.session(accountID: account) == nil)
    }
    var value = try await download()
    value.assignments[0].startedAt = 1
    value.assignments[0].srsStage = 5
    value.assignments[0].availableAt = 1
    try await apply(value, to: store)
    let review = try await store.openReviews(accountID: account)
    await #expect(throws: NativeReviewError.self) {
      try await store.openLessons(accountID: account, subjectIDs: [2])
    }
    #expect(try await store.session(accountID: account)?.revision == review.saved.revision)
    try await store.endReviews(accountID: account, expectedRevision: review.saved.revision)
    let lesson = try await store.openLessons(accountID: account, subjectIDs: [2])
    #expect(lesson.isLesson)
    await #expect(throws: NativeReviewError.self) {
      try await store.openReviews(accountID: account)
    }
    await #expect(throws: NativeReviewError.self) {
      try await store.openLessons(accountID: account, subjectIDs: [1])
    }
    #expect(try await store.session(accountID: account)?.revision == lesson.saved.revision)
  }
  @Test func wrongAnswersRetryAndCompletedLessonsSurviveReopenWithoutRequeueing() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    do {
      let store = try await store(at: url)
      let initial = try await store.openLessons(accountID: account, subjectIDs: [1])
      let question = try #require(initial.question)
      let wrong = try await store.answerReview(
        question.kind == .meaning ? "wrong" : "ぜんぜん",
        question: question, accountID: account, expectedRevision: initial.saved.revision)
      #expect(wrong.grade == .incorrect && wrong.state.question == question)
      #expect(try await store.pendingReviews(accountID: account).isEmpty)
      await #expect(throws: StudySessionError.invalidOverride) {
        try await store.changeReview(
          .overrideCorrect, accountID: account,
          expectedRevision: wrong.state.saved.revision)
      }
      let resumed = try await store.openLessons(accountID: account)
      #expect(resumed.saved.session.currentDecision == .incorrect)
      let next = try await store.changeReview(
        .advance, accountID: account,
        expectedRevision: resumed.saved.revision)
      let finished = try await complete(next, in: store)
      #expect(finished.saved.session.completedIDs.count == 1)
      let pending = try #require(await store.pendingReviews(accountID: account).first)
      #expect(pending.submission.isLesson)
      #expect(pending.submission.meaningWrongCount + pending.submission.readingWrongCount == 1)
    }
    let reopened = try await StudyStore.open(at: url)
    let resumed = try await reopened.openLessons(accountID: account)
    #expect(resumed.question == nil && resumed.success == nil)
    #expect(try await reopened.pendingReviews(accountID: account).count == 1)
    try await reopened.finishReviews(accountID: account, expectedRevision: resumed.saved.revision)
    #expect(try await reopened.session(accountID: account) == nil)
    #expect(try await reopened.availableLessons(accountID: account).map(\.id) == [2])
  }
  @Test func kanaVocabularyRequiresOnlyMeaningAndEndingKeepsCompletedOutbox() async throws {
    let store = try await store()
    let initial = try await store.openLessons(accountID: account, subjectIDs: [2])
    let question = try #require(initial.question)
    #expect(question.kind == .meaning)
    let done = try await complete(initial, in: store)
    #expect(done.saved.session.tasksAnswered == 1)
    try await store.endReviews(accountID: account, expectedRevision: done.saved.revision)
    #expect(try await store.pendingReviews(accountID: account).first?.submission.isLesson == true)
    #expect(try await store.availableLessons(accountID: account).map(\.id) == [1])
  }
  @Test func endingUnfinishedLessonsKeepsCompletedAnswersAndReleasesOnlyUnfinishedItems()
    async throws
  {
    let store = try await store()
    var state = try await store.openLessons(accountID: account, subjectIDs: [1, 2])
    for _ in 0..<8 where state.saved.session.completedIDs.isEmpty {
      let question = try #require(state.question)
      state = try await store.answerReview(
        question.kind == .meaning ? "one" : "いち",
        question: question, accountID: account, expectedRevision: state.saved.revision
      ).state
    }
    #expect(state.saved.session.completedIDs.count == 1)
    #expect(state.question != nil)
    let completed = try #require(await store.pendingReviews(accountID: account).first)
    try await store.endReviews(accountID: account, expectedRevision: state.saved.revision)
    #expect(try await store.session(accountID: account) == nil)
    #expect(try await store.pendingReviews(accountID: account) == [completed])
    let remaining = try await store.availableLessons(accountID: account).map(\.id)
    #expect(remaining.count == 1 && !remaining.contains(completed.subjectID))
  }
  @Test func staleWindowsChangedUnlocksVacationAndIdentityCannotCreditLessons() async throws {
    let store = try await store()
    let initial = try await store.openLessons(accountID: account, subjectIDs: [1])
    let question = try #require(initial.question)
    let answered = try await store.answerReview(
      question.kind == .meaning ? "one" : "いち",
      question: question, accountID: account, expectedRevision: initial.saved.revision
    ).state
    await #expect(throws: StudyStoreError.self) {
      try await store.answerReview(
        "one", question: question, accountID: account,
        expectedRevision: initial.saved.revision)
    }
    var value = try await download()
    value.assignments[0].unlockedAt = nil
    try await apply(value, to: store)
    let current = try #require(answered.question)
    await #expect(throws: NativeReviewError.self) {
      try await store.answerReview(
        current.kind == .meaning ? "one" : "いち", question: current,
        accountID: account, expectedRevision: answered.saved.revision)
    }
    #expect(try await store.session(accountID: account)?.revision == answered.saved.revision)
    value.profile.vacationStartedAt = 1
    try await apply(value, to: store)
    await #expect(throws: NativeReviewError.self) {
      try await store.openLessons(accountID: account)
    }
    try await store.removeSnapshot(credentialID: "fixture")
    await #expect(throws: StudyStoreError.self) { try await store.openLessons(accountID: account) }
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
  @Test func savedSessionCannotChangeFromLessonToReview() async throws {
    let store = try await store()
    let opened = try await store.openLessons(accountID: account, subjectIDs: [1])
    let assignment = try #require(await store.assignments(accountID: account).first)
    let changed = try StudySession(items: [assignment.sessionItem(id: 0, isLesson: false)])
    await #expect(throws: StudyStoreError.self) {
      try await store.saveSession(
        changed, accountID: account, expectedRevision: opened.saved.revision)
    }
    #expect(try await store.session(accountID: account)?.revision == opened.saved.revision)
  }
}
