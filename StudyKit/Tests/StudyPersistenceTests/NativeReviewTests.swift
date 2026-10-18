import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

struct NativeReviewTests {
  private let account = "fixture-user-id"
  private let now = Date(timeIntervalSince1970: 2_000_000_000)
  private func store(at url: URL = URL(filePath: "/unused")) async throws -> StudyStore {
    let store = try await StudyStore.open(at: url, inMemory: url.path == "/unused")
    _ = try await store.refresh(
      credentialID: "credential", token: "fixture",
      client: .init(transport: DownloadFixture.response))
    return store
  }

  @Test func answersAndSessionSurviveReopenAndCompletionDoesNotRequeue() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let initial: NativeReviewState
    do {
      let store = try await store(at: url)
      let opened = try await store.openReviews(accountID: account, now: now)
      #expect(opened.success == nil)
      let question = try #require(opened.question)
      initial = try await store.answerReview(
        question.kind == .meaning ? "single" : "いち", question: question, accountID: account,
        expectedRevision: opened.saved.revision,
        now: now
      ).state
      #expect(initial.saved.session.completedIDs.isEmpty)
      #expect(try await store.pendingReviews(accountID: account).isEmpty)
    }
    let reopened = try await StudyStore.open(at: url)
    let resumed = try await reopened.openReviews(accountID: account, now: now)
    #expect(resumed.success == nil)
    #expect(
      resumed.saved.revision == initial.saved.revision && resumed.question == initial.question)
    let reading = try #require(resumed.question)
    let complete = try await reopened.answerReview(
      reading.kind == .reading ? "いち" : "single", question: reading, accountID: account,
      expectedRevision: resumed.saved.revision,
      now: now)
    #expect(complete.state.question == nil)
    #expect(complete.state.success?.subjectFinished == true)
    let snapshot = try #require(await reopened.snapshot(credentialID: "credential"))
    #expect(snapshot.pendingReviews == 1 && snapshot.assignments.isEmpty)
    #expect(try await reopened.pendingReviews(accountID: account).count == 1)
    try await reopened.finishReviews(
      accountID: account, expectedRevision: complete.state.saved.revision)
    #expect(try await reopened.session(accountID: account) == nil)
    await #expect(throws: NativeReviewError.self) {
      try await reopened.openReviews(accountID: account, now: now)
    }
    #expect(try await reopened.pendingReviews(accountID: account).count == 1)
  }

  @Test func staleWindowsAndVoiceTokensCannotCreditAnotherQuestion() async throws {
    let store = try await store()
    let opened = try await store.openReviews(accountID: account, now: now)
    let question = try #require(opened.question)
    let answered = try await store.answerReview(
      question.kind == .meaning ? "one" : "いち", question: question, accountID: account,
      expectedRevision: opened.saved.revision,
      now: now)
    await #expect(throws: StudyStoreError.self) {
      try await store.answerReview(
        question.kind == .meaning ? "one" : "いち", question: question, accountID: account,
        expectedRevision: opened.saved.revision,
        now: now)
    }
    await #expect(throws: StudySessionError.self) {
      try await store.answerReview(
        question.kind == .meaning ? "one" : "いち", question: question, accountID: account,
        expectedRevision: answered.state.saved.revision, now: now)
    }
    #expect(try await store.session(accountID: account)?.session.tasksAnswered == 1)
  }

  @Test func incorrectAnswerPersistsAndExplicitCorrectionUsesNormalEngine() async throws {
    let store = try await store()
    let initial = try await store.openReviews(accountID: account, now: now)
    let question = try #require(initial.question)
    let wrong = try await store.answerReview(
      question.kind == .meaning ? "wrong" : "ぜんぜん", question: question, accountID: account,
      expectedRevision: initial.saved.revision,
      now: now)
    #expect(wrong.grade == .incorrect && wrong.state.saved.session.currentDecision == .incorrect)
    #expect(wrong.state.success == nil)
    let restored = try await store.openReviews(accountID: account, now: now)
    #expect(restored.saved.session.currentDecision == .incorrect)
    #expect(restored.success == nil)
    let corrected = try await store.changeReview(
      .overrideCorrect, accountID: account, expectedRevision: restored.saved.revision, now: now)
    #expect(corrected.saved.session.successRate == 100 && corrected.question?.kind != question.kind)
    #expect(corrected.success?.subjectFinished == false)
    let reopened = try await store.openReviews(accountID: account, now: now)
    #expect(reopened.success == nil)
    #expect(corrected.saved.session.items[question.itemID]?.meaning.wrongCount == 0)
    await #expect(throws: StudyStoreError.self) {
      try await store.finishReviews(accountID: account, expectedRevision: corrected.saved.revision)
    }
  }

  @Test func invalidReadingAndAlternativeReadingDoNotPenalize() async throws {
    let store = try await store()
    let initial = try await store.openReviews(accountID: account, now: now)
    let meaning = try #require(initial.question)
    let readingState =
      meaning.kind == .reading
      ? initial
      : try await store.answerReview(
        "one", question: meaning, accountID: account, expectedRevision: initial.saved.revision,
        now: now
      ).state
    let question = try #require(readingState.question)
    let revision = readingState.saved.revision
    for (text, expected) in [
      ("一", AnswerGrade.containsInvalidCharacters([NSRange(location: 0, length: 1)])),
      ("ひと", .otherKanjiReading),
    ] {
      let result = try await store.answerReview(
        text, question: question, accountID: account, expectedRevision: revision, now: now)
      #expect(result.grade == expected && result.state.saved.revision == revision)
      #expect(result.state.saved.session.tasksAnswered == readingState.saved.session.tasksAnswered)
    }
  }

  @Test func changedAssignmentAndDisconnectedAccountCannotAcceptAnswers() async throws {
    let store = try await store()
    let initial = try await store.openReviews(accountID: account, now: now)
    let question = try #require(initial.question)
    var download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    download.assignments[0].srsStage = 6
    let baseline = try await store.refreshBaseline(accountID: account)
    _ = try await store.applyDownload(download, credentialID: "credential", baseline: baseline)
    await #expect(throws: NativeReviewError.self) {
      try await store.answerReview(
        question.kind == .meaning ? "one" : "いち", question: question, accountID: account,
        expectedRevision: initial.saved.revision,
        now: now)
    }
    try await store.removeSnapshot(credentialID: "credential")
    await #expect(throws: StudyStoreError.self) {
      try await store.answerReview(
        question.kind == .meaning ? "one" : "いち", question: question, accountID: account,
        expectedRevision: initial.saved.revision,
        now: now)
    }
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }

  @Test func selectionHonorsDueTimeVacationAndSubscription() async throws {
    let store = try await store()
    await #expect(throws: NativeReviewError.self) {
      try await store.openReviews(accountID: account, now: .distantPast)
    }
    var download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    download.profile.maxLevelGranted = 0
    let baseline = try await store.refreshBaseline(accountID: account)
    _ = try await store.applyDownload(download, credentialID: "credential", baseline: baseline)
    await #expect(throws: NativeReviewError.self) {
      try await store.openReviews(accountID: account, now: now)
    }
    download.profile.maxLevelGranted = 60
    download.profile.vacationStartedAt = 1
    _ = try await store.applyDownload(
      download, credentialID: "credential", baseline: store.refreshBaseline(accountID: account))
    await #expect(throws: NativeReviewError.self) {
      try await store.openReviews(accountID: account, now: now)
    }
    #expect(try await store.session(accountID: account) == nil)
  }

  @Test func importedExclusionsAffectNewVocabularySessionsAndPreserveResumedWork() async throws {
    let store = try await store()
    var download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    var vocabulary = CatalogAssignment(id: 102, subjectID: 2, kind: .vocabulary)
    vocabulary.level = 1
    vocabulary.srsStage = 3
    vocabulary.startedAt = 1
    vocabulary.availableAt = 1
    vocabulary.isKanaOnlyVocabulary = true
    download.assignments.append(vocabulary)
    _ = try await store.applyDownload(
      download, credentialID: "credential", baseline: store.refreshBaseline(accountID: account))
    let initial = try await store.openReviews(accountID: account, now: now)
    #expect(initial.saved.session.items.count == 2)
    for id: Int64 in [1, 2] {
      let details = try await store.subjectDetails(subjectID: id, accountID: account)
      var material = details.material ?? StudyMaterial(subjectID: id)
      material.meaningNote += StudyMaterial.exclusionMarker
      try await store.saveSubjectMaterial(
        material, accountID: account, expectedRevision: details.savedMaterial?.revision)
    }
    let resumed = try await store.openReviews(accountID: account, now: now)
    #expect(resumed.saved.revision == initial.saved.revision)
    #expect(resumed.saved.session.items.count == 2)
    try await store.endReviews(accountID: account, expectedRevision: resumed.saved.revision)
    let next = try await store.openReviews(accountID: account, now: now)
    #expect(next.saved.session.items.values.map(\.subjectID) == [1])
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
}

extension NativeReviewTests {
  @Test func missingContentCannotSilentlyDropADueAssignment() async throws {
    let store = try await store()
    var download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    download.subjects.removeAll { $0.id == 1 }
    let baseline = try await store.refreshBaseline(accountID: account)
    _ = try await store.applyDownload(download, credentialID: "credential", baseline: baseline)
    await #expect(throws: NativeReviewError.self) {
      try await store.openReviews(accountID: account, now: now)
    }
    #expect(try await store.session(accountID: account) == nil)
  }

  @Test(arguments: [true, false]) func reviewSurfaceDoesNotAdoptPracticeOrLessonSessions(
    isPractice: Bool
  ) async throws {
    let store = try await store()
    var practice = try StudySession(
      items: [.init(id: 1, subjectID: 1, assignmentID: 101, srsStage: 5, isLesson: !isPractice)],
      isPractice: isPractice)
    practice.nextQuestion()
    try await store.saveSession(practice, accountID: account, expectedRevision: nil)
    if isPractice {
      await #expect(throws: StudyStoreError.self) {
        try await store.openReviews(accountID: account, now: now)
      }
    } else {
      await #expect(throws: NativeReviewError.self) {
        try await store.openReviews(accountID: account, now: now)
      }
    }
    #expect(try await store.session(accountID: account)?.session.isPractice == isPractice)
  }
}

extension NativeReviewTests {
  @Test func explicitEndPreservesCompletedWorkAndRejectsOldWindow() async throws {
    let store = try await store()
    var download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    var second = CatalogAssignment(id: 102, subjectID: 2, kind: .vocabulary)
    second.level = 1
    second.srsStage = 3
    second.availableAt = 1
    second.startedAt = 1
    second.isKanaOnlyVocabulary = true
    download.assignments.append(second)
    let baseline = try await store.refreshBaseline(accountID: account)
    _ = try await store.applyDownload(download, credentialID: "credential", baseline: baseline)
    var review = try await store.openReviews(accountID: account, now: now)
    for _ in 0..<4 where review.saved.session.completedIDs.isEmpty {
      let question = try #require(review.question)
      review = try await store.answerReview(
        question.kind == .reading ? "いち" : "one", question: question, accountID: account,
        expectedRevision: review.saved.revision, now: now
      ).state
    }
    #expect(review.saved.session.completedIDs.count == 1 && review.question != nil)
    let pending = try await store.pendingReviews(accountID: account).map(\.revision)
    try await store.endReviews(accountID: account, expectedRevision: review.saved.revision)
    #expect(try await store.session(accountID: account) == nil)
    #expect(try await store.pendingReviews(accountID: account).map(\.revision) == pending)
    await #expect(throws: StudyStoreError.self) {
      try await store.changeReview(
        .advance, accountID: account, expectedRevision: review.saved.revision)
    }
    let next = try await store.openReviews(accountID: account, now: now)
    #expect(next.saved.session.items.count == 1)
  }
}

extension NativeReviewTests {
  @Test func imageOnlyRadicalHasOneMeaningQuestionAndOneDurableSubmission() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var profile = StudyAccountProfile(username: "Radical fixture")
    profile.level = 1
    profile.maxLevelGranted = 60
    var subject = CatalogSubject(id: 8790, kind: .radical)
    subject.level = 1
    subject.meanings = [.init("Death Star", role: .primary)]
    subject.characterImageURL = "https://cdn.wanikani.com/fixture.svg"
    var assignment = CatalogAssignment(id: 101, subjectID: subject.id, kind: .radical)
    assignment.level = 1
    assignment.srsStage = 3
    assignment.startedAt = 1
    assignment.availableAt = 1
    var fixture = LegacyStudyExport(schemaVersion: 15, profile: profile)
    fixture.subjects = [subject]
    fixture.assignments = [assignment]
    _ = try await store.importLegacyAccount(
      fixture, sourceID: "radical-fixture", verifiedAccountID: account,
      verifiedUsername: profile.username, credentialID: "radical-fixture")
    let opened = try await store.openReviews(accountID: account, now: now)
    let question = try #require(opened.question)
    #expect(question.kind == .meaning && opened.subject?.japanese == "")
    let deferred = try await store.changeReview(
      .deferQuestion, accountID: account, expectedRevision: opened.saved.revision)
    let resumed = try await store.openReviews(accountID: account, now: now)
    #expect(resumed.saved.revision == deferred.saved.revision)
    let answer = try #require(resumed.question)
    let completed = try await store.answerReview(
      "death star", question: answer, accountID: account,
      expectedRevision: resumed.saved.revision, now: now)
    #expect(completed.grade == .precise && completed.state.question == nil)
    let pending = try await store.pendingReviews(accountID: account)
    #expect(pending.count == 1)
    let submission = try #require(pending.first).submission
    #expect(submission.subjectID == subject.id && submission.assignmentID == assignment.id)
    #expect(
      !submission.isLesson && submission.readingWrongCount == 0 && submission.meaningWrongCount == 0
    )
  }
}

extension NativeReviewTests {
  @Test(arguments: [true, false]) func exactMatchingUsesNormalGradingWithoutPenalizingTypos(
    exactMatch: Bool
  ) async throws {
    let store = try await store()
    let details = try await store.subjectDetails(subjectID: 1, accountID: account)
    var material = try #require(details.material)
    material.meaningSynonyms.append("Bunny")
    try await store.saveSubjectMaterial(
      material, accountID: account, expectedRevision: details.savedMaterial?.revision)
    var opened = try await store.openReviews(accountID: account, now: now)
    if let question = opened.question, question.kind == .reading {
      opened = try await store.answerReview(
        "いち", question: question, accountID: account, expectedRevision: opened.saved.revision,
        now: now
      ).state
    }
    let question = try #require(opened.question)
    #expect(question.kind == .meaning)
    let checked = try await store.answerReview(
      "bunn", question: question, accountID: account, expectedRevision: opened.saved.revision,
      exactMatch: exactMatch, now: now)
    #expect(checked.grade == .imprecise)
    if exactMatch {
      #expect(checked.state.success == nil)
      #expect(checked.state.saved.revision == opened.saved.revision)
      #expect(checked.state.question == question)
      #expect(checked.state.saved.session.tasksAnswered == opened.saved.session.tasksAnswered)
      #expect(checked.state.saved.session.items[question.itemID]?.meaning.wrongCount == 0)
      #expect(try await store.pendingReviews(accountID: account).isEmpty)
      let restored = try await store.openReviews(accountID: account, now: now)
      #expect(restored.saved.revision == opened.saved.revision && restored.question == question)
      let exact = try await store.answerReview(
        "bunny", question: question, accountID: account, expectedRevision: restored.saved.revision,
        exactMatch: true, now: now)
      #expect(exact.grade == .precise)
      #expect(exact.state.success != nil)
      #expect(exact.state.saved.session.items[question.itemID]?.meaning.answered == true)
    } else {
      #expect(checked.state.success != nil)
      #expect(checked.state.saved.revision != opened.saved.revision)
      #expect(checked.state.saved.session.items[question.itemID]?.meaning.answered == true)
    }
  }
}
