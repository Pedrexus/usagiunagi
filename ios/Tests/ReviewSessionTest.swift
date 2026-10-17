// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import StudyCore
import WaniKaniAPI
import XCTest

final class ReviewSessionTest: XCTestCase {
  private func subject(reading: Bool = true) -> TKMSubject {
    var value = TKMSubject()
    value.id = 42
    value.japanese = "一"
    value.kanji = .init()
    var meaning = TKMMeaning()
    meaning.meaning = "One"
    value.meanings = [meaning]
    if reading {
      var reading = TKMReading()
      reading.reading = "いち"
      reading.isPrimary = true
      value.readings = [reading]
    }
    return value
  }

  private func item(subject: TKMSubject? = nil) -> ReviewItem {
    var assignment = TKMAssignment()
    assignment.id = 100
    assignment.subjectID = 42
    assignment.srsStageNumber = 4
    assignment.subjectType = .kanji
    assignment.availableAt = 10
    return ReviewItem(assignment: assignment, subject: subject)
  }

  private func options() -> StudySessionOptions {
    var value = StudySessionOptions()
    value.groupMeaningReading = true
    value.meaningFirst = true
    return value
  }

  func testCompletedSubjectUsesExistingDurableWriteBoundaryExactlyOnce() {
    var sent = [TKMProgress]()
    let subject = subject()
    let session = ReviewSession(repository: ReviewRepository(subject: { _ in
      subject
    }, saveProgress: { sent.append($0) }),
    items: [item()], options: options, now: { 100 }, seed: 1)
    session.nextTask()
    XCTAssertEqual(session.activeTaskType, .meaning)
    XCTAssertEqual(session.markAnswer(.Correct)?.subjectFinished, false)
    XCTAssertTrue(sent.isEmpty)
    session.nextTask()
    XCTAssertEqual(session.activeTaskType, .reading)
    XCTAssertEqual(session.markAnswer(.Correct)?.subjectFinished, true)
    XCTAssertEqual(sent.count, 1)
    XCTAssertEqual(sent[0].assignment.id, 100)
    XCTAssertEqual(sent[0].assignment.subjectID, 42)
    XCTAssertEqual(sent[0].createdAt, 100)
    XCTAssertFalse(sent[0].meaningWrong || sent[0].readingWrong)
    XCTAssertNil(session.markAnswer(.Correct))
    XCTAssertEqual(sent.count, 1)
    XCTAssertEqual(session.completedReviews.count, 1)
  }

  func testPracticeNeverWritesProgressEvenWhenCallerJustMarksCorrect() {
    var writes = 0
    let session = ReviewSession(repository: ReviewRepository(subject: { _ in
      nil
    }, saveProgress: { _ in writes += 1 }),
    items: [item(subject: subject(reading: false))],
    isPracticeSession: true,
    options: options, seed: 1)
    session.nextTask()
    XCTAssertEqual(session.markAnswer(.Correct)?.subjectFinished, true)
    XCTAssertEqual(writes, 0)
    XCTAssertEqual(session.completedReviews.count, 1)
  }

  func testIncompleteCatalogDoesNotSilentlySkipOrUpload() {
    var writes = 0
    let session = ReviewSession(repository: ReviewRepository(subject: { _ in
      nil
    }, saveProgress: { _ in writes += 1 }),
    items: [item()], options: options, seed: 1)
    XCTAssertNotNil(session.initializationError)
    XCTAssertEqual(session.activeQueueLength, 0)
    session.nextTask()
    XCTAssertNil(session.markAnswer(.Correct))
    XCTAssertEqual(writes, 0)
  }

  func testOverrideAndReadingCreditReachTheProtobufPayload() {
    var sent = [TKMProgress]()
    let subject = subject()
    let session = ReviewSession(repository: ReviewRepository(subject: { _ in
      subject
    }, saveProgress: { sent.append($0) }),
    items: [item()], options: options, now: { 100 }, seed: 1)
    session.nextTask()
    XCTAssertNotNil(session.markAnswer(.Incorrect))
    session.creditReading()
    XCTAssertEqual(session.markAnswer(.OverrideAnswerCorrect)?.subjectFinished, true)
    XCTAssertEqual(sent.count, 1)
    XCTAssertFalse(sent[0].meaningWrong || sent[0].readingWrong)
    XCTAssertEqual(sent[0].meaningWrongCount, 0)
    XCTAssertEqual(session.tasksAnswered, 1)
    XCTAssertEqual(session.tasksAnsweredCorrectly, 1)
    XCTAssertTrue(session.completedReviews[0].answeredReading)
  }

  func testSynonymsAndExclusionKeepExistingMaterialFields() {
    let subject = subject()
    var materials = TKMStudyMaterials()
    materials.subjectID = 42
    materials.meaningNote = "Keep this note"
    materials.meaningSynonyms = ["Single"]
    var saved: TKMStudyMaterials?
    var exclusion: Bool?
    let repository = ReviewRepository(subject: { _ in subject }, materials: { _ in materials },
                                      saveProgress: { _ in },
                                      saveMaterials: { saved = $0 },
                                      setExcluded: { material, excluded in
                                        exclusion = excluded
                                        material.readingNote = "Excluded marker"
                                      })
    let session = ReviewSession(repository: repository, items: [item()], options: options, seed: 1)
    session.nextTask()
    session.addSynonym("Unity")
    XCTAssertEqual(saved?.meaningSynonyms, ["Single", "Unity"])
    XCTAssertEqual(saved?.meaningNote, "Keep this note")
    session.setExclude(true)
    XCTAssertEqual(exclusion, true)
    XCTAssertEqual(session.activeStudyMaterials?.meaningNote, "Keep this note")
    XCTAssertEqual(session.activeStudyMaterials?.readingNote, "Excluded marker")
  }

  func testRefreshingMaterialsPreservesEditsMadeInAnswerDetails() {
    let subject = subject()
    var stored = TKMStudyMaterials()
    stored.subjectID = 42
    stored.meaningNote = "Before review"
    let repository = ReviewRepository(subject: { _ in subject }, materials: { _ in stored },
                                      saveProgress: { _ in }, saveMaterials: { stored = $0 })
    let session = ReviewSession(repository: repository, items: [item()], options: options, seed: 1)
    session.nextTask()
    stored.meaningNote = "Edited while viewing the answer"
    stored.meaningSynonyms = ["Single"]
    session.refreshStudyMaterials()
    session.addSynonym("Unity")
    XCTAssertEqual(stored.meaningNote, "Edited while viewing the answer")
    XCTAssertEqual(stored.meaningSynonyms, ["Single", "Unity"])
  }
}
