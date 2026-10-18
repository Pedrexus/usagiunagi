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

import Foundation
import StudyCore
import WaniKaniAPI

/// The existing storage implementation remains responsible for durable local writes.
struct ReviewRepository {
  var subject: (Int64) -> TKMSubject?
  var materials: (Int64) -> TKMStudyMaterials? = { _ in nil }
  var saveProgress: (TKMProgress) -> Void
  var saveMaterials: (TKMStudyMaterials) -> Void = { _ in }
  var setExcluded: (inout TKMStudyMaterials, Bool) -> Void = { _, _ in }
}

extension ReviewRepository {
  init(client: LocalCachingClient) {
    self.init(
      subject: { client.getSubject(id: $0) },
      materials: { client.getStudyMaterial(subjectId: $0) },
      saveProgress: { _ = client.sendProgress([$0]) },
      saveMaterials: { _ = client.updateStudyMaterial($0) },
      setExcluded: { material, excluded in
        _ = client.setExcluded(studyMaterials: &material, shouldExclude: excluded)
      })
  }
}

/// Adapts legacy view/protobuf values to the shared engine; contains no scheduling or grading
/// rules.
final class ReviewSession {
  private let repository: ReviewRepository
  private let legacyItems: [ReviewItem]
  private let subjects: [Int: TKMSubject]
  private let options: () -> StudySessionOptions
  private let now: () -> Int64
  private var state: StudySession
  let initializationError: String?
  private(set) var activeStudyMaterials: TKMStudyMaterials?

  init(
    repository: ReviewRepository, items: [ReviewItem], isPracticeSession: Bool = false,
    options: @escaping () -> StudySessionOptions = ReviewSession.currentOptions,
    now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) },
    seed: UInt64 = .random(in: .min ... .max)
  ) {
    self.repository = repository
    legacyItems = items
    self.options = options
    self.now = now
    var subjects = [Int: TKMSubject]()
    var entries = [StudySessionItem]()
    for (index, item) in items.enumerated() {
      guard let subject = item.subject ?? repository.subject(item.assignment.subjectID)
      else { continue }
      subjects[index] = subject
      entries.append(
        StudySessionItem(
          id: index, subjectID: item.assignment.subjectID,
          assignmentID: item.assignment.id,
          srsStage: item.assignment.srsStage.rawValue,
          availableAt: Int64(item.assignment.availableAt),
          isLesson: item.assignment.isLessonStage,
          isKanji: subject.hasKanji,
          hasMeaning: !subject.meanings.isEmpty,
          hasReading: !subject.readings.isEmpty))
    }
    self.subjects = subjects
    do {
      guard entries.count == items.count else { throw StudySessionError.missingQuestionContent(-1) }
      state = try StudySession(
        items: entries, options: options(), isPractice: isPracticeSession,
        seed: seed)
      initializationError = nil
    } catch {
      // Leave every assignment untouched; an incomplete catalog must not silently skip reviews.
      state = try! StudySession(
        items: [], options: options(), isPractice: isPracticeSession,
        seed: seed)
      initializationError =
        "Some study items are missing their question data. Sync your account and try again."
    }
  }

  static func currentOptions() -> StudySessionOptions {
    var value = StudySessionOptions()
    value.batchSize = Settings.reviewBatchSize
    value.groupMeaningReading = Settings.groupMeaningReading
    value.combinedAnki =
      Settings.ankiMode && Settings.ankiModeCombineReadingMeaning
      && Settings
        .ankiModeTaskType == .both
    value.meaningFirst = Settings.meaningFirst
    value.incorrectAnswerDelay = Settings.incorrectAnswerReturnDelay
    value.skipKanjiReadings = Settings.skipKanjiReadings
    value.minimizePenalty = Settings.minimizeReviewPenalty
    return value
  }

  var questionToken: StudyQuestion? { state.question }
  var activeTask: ReviewItem! { state.question.map { legacyItems[$0.itemID] } }
  var activeTaskType: TaskType! { state.question?.kind }
  var activeSubject: TKMSubject! { state.question.flatMap { subjects[$0.itemID] } }
  var activeAssignment: TKMAssignment! { activeTask?.assignment }
  var completedReviews: [ReviewItem] { state.completedIDs.map { legacyItems[$0] } }
  var activeQueueLength: Int { state.activeIDs.count }
  var reviewQueueLength: Int { state.queuedIDs.count }
  var tasksAnswered: Int { state.tasksAnswered }
  var tasksAnsweredCorrectly: Int { state.tasksAnsweredCorrectly }
  var reviewsCompleted: Int { state.completedIDs.count }
  var successRateText: String { "\(state.successRate)%" }
  var hasStarted: Bool { state.question != nil }
  var canWrapUp: Bool { state.canWrapUp }
  var wrappingUp: Bool {
    get { state.wrappingUp }
    set { state.setWrappingUp(newValue) }
  }

  func nextTask(continuingCurrentItem: Bool = false) {
    state.options = options()
    guard let question = state.nextQuestion(continuingCurrentItem: continuingCurrentItem)
    else { return }
    activeStudyMaterials =
      activeTask.subject == nil
      ? repository
        .materials(activeTask.assignment.subjectID) : nil
    copyProgress(for: question.itemID)
  }

  func moveActiveTaskToEnd() {
    guard let question = state.question else { return }
    try? state.deferQuestion(question)
    copyProgress(for: question.itemID)
  }

  func excludeTask() {
    guard let question = state.question else { return }
    try? state.excludeQuestion(question)
    copyProgress(for: question.itemID)
  }

  func creditReading() {
    guard let question = state.question else { return }
    try? state.creditReading(question)
    copyProgress(for: question.itemID)
  }

  func markAnswer(_ decision: StudyAnswerDecision) -> StudyMarkResult? {
    guard let question = state.question else { return nil }
    state.options = options()
    guard let mark = try? state.mark(decision, for: question, now: now()) else { return nil }
    copyProgress(for: question.itemID)
    if mark.submission != nil { repository.saveProgress(legacyItems[question.itemID].answer) }
    return mark
  }

  private func copyProgress(for id: Int) {
    guard let value = state.items[id] else { return }
    let item = legacyItems[id]
    item.answeredMeaning = value.meaning.answered
    item.answeredReading = value.reading.answered
    if let wrong = value.meaning.firstAnswerWrong {
      item.answer.meaningWrong = wrong
    } else {
      item.answer.clearMeaningWrong()
    }
    if let wrong = value.reading.firstAnswerWrong {
      item.answer.readingWrong = wrong
    } else {
      item.answer.clearReadingWrong()
    }
    item.answer.meaningWrongCount = Int32(clamping: value.meaning.wrongCount)
    item.answer.readingWrongCount = Int32(clamping: value.reading.wrongCount)
    if let date = value.createdAt { item.answer.createdAt = Int32(clamping: date) }
  }

  func refreshStudyMaterials() {
    guard let task = activeTask, task.subject == nil else { return }
    activeStudyMaterials = repository.materials(task.assignment.subjectID)
  }

  func addSynonym(_ text: String) {
    var material = activeStudyMaterials ?? TKMStudyMaterials()
    material.subjectID = activeSubject.id
    material.meaningSynonyms.append(text)
    activeStudyMaterials = material
    repository.saveMaterials(material)
  }

  func setExclude(_ exclude: Bool) {
    var material = activeStudyMaterials ?? TKMStudyMaterials()
    material.subjectID = activeSubject.id
    repository.setExcluded(&material, exclude)
    activeStudyMaterials = material
  }
}
