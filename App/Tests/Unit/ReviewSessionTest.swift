// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Foundation
import StudyCore
import Testing

@testable import StudyPersistence

struct ReviewSessionTest {
  private let account = "native-review-adapter-fixture"
  private let now = Date(timeIntervalSince1970: 100)
  private var options: StudySessionOptions {
    var value = StudySessionOptions()
    value.groupMeaningReading = true
    value.meaningFirst = true
    return value
  }
  private func store() async throws -> StudyStore {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var profile = StudyAccountProfile(username: "Review adapter fixture")
    profile.level = 1
    profile.maxLevelGranted = 3
    var download = StudyDownload(accountID: account, profile: profile)
    var subject = CatalogSubject(id: 42, kind: .kanji)
    subject.level = 1
    subject.japanese = "一"
    subject.meanings = [.init("One", role: .primary)]
    subject.readings = [.init("いち", isPrimary: true, kind: .onyomi)]
    var assignment = CatalogAssignment(id: 100, subjectID: 42, kind: .kanji)
    assignment.level = 1
    assignment.srsStage = 4
    assignment.unlockedAt = 1
    assignment.startedAt = 1
    assignment.availableAt = 10
    download.subjects = [subject]
    download.assignments = [assignment]
    download.materials = [
      .init(
        id: 99,
        value: .init(
          subjectID: 42, meaningNote: "Before review",
          readingNote: "Hidden reading note", meaningSynonyms: ["Single"]))
    ]
    _ = try await store.applyDownload(
      download, credentialID: "native-review-adapter",
      baseline: .init(assignments: [:], materials: [:]))
    return store
  }
  @Test func testOverrideAndReadingCreditReachTheDurableSubmission() async throws {
    let store = try await store()
    let opened = try await store.openReviews(accountID: account, options: options, now: now)
    let question = try #require(opened.question)
    #expect(question.kind == .meaning)
    let credited = try await store.answerReview(
      "ichi", question: question, accountID: account, expectedRevision: opened.saved.revision,
      now: now)
    #expect(credited.grade == .isReadingButWantMeaning)
    #expect(credited.state.saved.session.tasksAnswered == 0)
    let wrong = try await store.answerReview(
      "not an answer", question: #require(credited.state.question), accountID: account,
      expectedRevision: credited.state.saved.revision, now: now)
    #expect(wrong.grade == .incorrect)
    let corrected = try await store.changeReview(
      .overrideCorrect, accountID: account, expectedRevision: wrong.state.saved.revision, now: now)
    #expect(corrected.success?.subjectFinished == true && corrected.question == nil)
    #expect(
      corrected.saved.session.tasksAnswered == 1
        && corrected.saved.session.tasksAnsweredCorrectly == 1)
    let pending = try await store.pendingReviews(accountID: account)
    #expect(pending.count == 1)
    let review = try #require(pending.first)
    #expect(review.submission.assignmentID == 100 && review.subjectID == 42)
    #expect(review.submission.createdAt == 100 && !review.submission.isLesson)
    #expect(!review.submission.meaningWrong && !review.submission.readingWrong)
    #expect(review.submission.meaningWrongCount == 0 && review.submission.readingWrongCount == 0)
    let item = try #require(corrected.saved.session.items[question.itemID])
    #expect(item.reading.answered && corrected.saved.session.completedIDs == [question.itemID])
    await #expect(throws: StudySessionError.self) {
      try await store.changeReview(
        .overrideCorrect, accountID: account,
        expectedRevision: corrected.saved.revision, now: now)
    }
    #expect(try await store.pendingReviews(accountID: account) == pending)
  }
  @Test func testRefreshingMaterialsPreservesEditsMadeInAnswerDetails() async throws {
    let store = try await store()
    let opened = try await store.openReviews(accountID: account, options: options, now: now)
    let before = try await store.subjectDetails(subjectID: 42, accountID: account)
    let edited = StudyMaterial(
      subjectID: 42, meaningNote: "Edited while viewing the answer\n  🐰",
      readingNote: "Hidden latest reading\nいち", meaningSynonyms: ["Single", "Solitary"])
    try await store.saveSubjectMaterial(
      edited, accountID: account, expectedRevision: before.savedMaterial?.revision)
    let wrong = try await store.answerReview(
      "not an answer", question: #require(opened.question),
      accountID: account, expectedRevision: opened.saved.revision, now: now)
    let updated = try await store.changeReview(
      .addSynonym("Unity"), accountID: account,
      expectedRevision: wrong.state.saved.revision, now: now)
    let current = try await store.subjectDetails(subjectID: 42, accountID: account)
    #expect(current.material?.meaningNote == edited.meaningNote)
    #expect(current.material?.readingNote == edited.readingNote)
    #expect(current.material?.meaningSynonyms == ["Single", "Solitary", "Unity"])
    #expect(current.savedMaterial?.serverID == 99 && current.savedMaterial?.pending == true)
    #expect(updated.saved.session.items[0]?.meaning.wrongCount == 0)
    #expect(updated.saved.session.items[0]?.meaning.answered == true)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
}
