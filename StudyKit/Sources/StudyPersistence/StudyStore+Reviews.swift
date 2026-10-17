import Foundation
import StudyCore

/// A consistent offline read; neither credentials nor SwiftData models leave the store.
public struct NativeReviewState: Sendable {
  public let saved: SavedStudySession
  public let subjects: [Int64: CatalogSubject]
  public var question: StudyQuestion? {
    guard let question = saved.session.question,
      saved.session.activeIDs.contains(question.itemID)
    else { return nil }
    return question
  }
  public var subject: CatalogSubject? {
    question.flatMap { saved.session.items[$0.itemID] }.flatMap { subjects[$0.subjectID] }
  }
}

public struct NativeReviewAnswer: Sendable {
  public let state: NativeReviewState
  public let grade: AnswerGrade
  public let normalized: String
}

public enum NativeReviewError: Error, LocalizedError {
  case unavailableAccount, vacation, noReviews
  case incompleteContent(Int64)
  case changedAssignment(Int64)
  public var errorDescription: String? {
    switch self {
    case .unavailableAccount: "Refresh this account before starting reviews."
    case .vacation: "Reviews are paused while your account is on vacation."
    case .noReviews: "No reviews are available in the saved account data."
    case .incompleteContent(let id):
      "Subject \(id) is missing study content. Refresh before reviewing it."
    case .changedAssignment(let id):
      "Subject \(id) changed since this session began. Your saved answers remain on this device."
    }
  }
}

public enum NativeReviewAction: Sendable {
  case advance, overrideCorrect, deferQuestion, wrapUp, stopWrapping
}

extension StudyStore {
  /// Reopen the existing session unchanged, or select due assignments from the offline catalog.
  /// No network request or upload occurs here. Each window must use the returned revision.
  public func openReviews(accountID: String, now: Date = .now) throws -> NativeReviewState {
    try requireReviewAccount(accountID)
    if let saved = try session(accountID: accountID) {
      return try reviewState(saved, accountID: accountID)
    }
    let subjects = try catalog(accountID: accountID)
    let byID = Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0) })
    let pending = Set(try pendingReviews(accountID: accountID).map(\.subjectID))
    let profile = try accountState(accountID: accountID)!.profile
    let due = try assignments(accountID: accountID).filter {
      $0.startedAt != nil && (1...8).contains($0.srsStage) && $0.hidden != true
        && $0.availableAt.map { $0 <= Int64(now.timeIntervalSince1970) } == true
        && !pending.contains($0.subjectID)
    }.sorted { ($0.availableAt ?? 0, $0.subjectID) < ($1.availableAt ?? 0, $1.subjectID) }
    var selected: [CatalogAssignment] = []
    for assignment in due {
      guard let subject = byID[assignment.subjectID] else {
        throw NativeReviewError.incompleteContent(assignment.subjectID)
      }
      if subject.hiddenAt != nil || subject.level > profile.maxLevelGranted { continue }
      try requireReviewContent(subject, assignment: assignment)
      selected.append(assignment)
    }
    guard !selected.isEmpty else { throw NativeReviewError.noReviews }
    var session = try StudySession(
      items: selected.enumerated().map { $0.element.sessionItem(id: $0.offset, isLesson: false) })
    session.nextQuestion()
    let revision = try saveSession(session, accountID: accountID, expectedRevision: nil)
    return try reviewState(.init(revision: revision, session: session), accountID: accountID)
  }

  /// Grade against the latest local synonyms and commit the decision and outbox together.
  public func answerReview(
    _ answer: String, question: StudyQuestion, accountID: String,
    expectedRevision: UUID, exactMatch: Bool = false, now: Date = .now
  ) throws -> NativeReviewAnswer {
    var state = try currentReview(accountID: accountID, expectedRevision: expectedRevision)
    guard state.question == question, let subject = state.subject else {
      throw StudySessionError.staleQuestion
    }
    try validateCurrentAssignment(state, accountID: accountID)
    let normalized = AnswerGrader.normalizedString(answer, taskType: question.kind)
    let synonyms =
      try materials(accountID: accountID).first { $0.material.subjectID == subject.id }?.material
      .meaningSynonyms ?? []
    let grade = AnswerGrader.checkNormalizedAnswer(
      normalized, subject: subject.gradingSubject, synonyms: synonyms,
      taskType: question.kind, subjectLookup: { state.subjects[$0]?.gradingSubject })
    if exactMatch, grade == .imprecise {
      return .init(state: state, grade: grade, normalized: normalized)
    }
    var session = state.saved.session
    switch grade {
    case .precise, .imprecise:
      _ = try session.mark(.correct, for: question, now: Int64(now.timeIntervalSince1970))
      session.nextQuestion()
    case .incorrect:
      _ = try session.mark(.incorrect, for: question, now: Int64(now.timeIntervalSince1970))
    case .isReadingButWantMeaning: try session.creditReading(question)
    default: return .init(state: state, grade: grade, normalized: normalized)
    }
    let revision = try saveSession(
      session, accountID: accountID, expectedRevision: expectedRevision)
    state = try reviewState(.init(revision: revision, session: session), accountID: accountID)
    return .init(state: state, grade: grade, normalized: normalized)
  }

  public func changeReview(
    _ action: NativeReviewAction, accountID: String,
    expectedRevision: UUID, now: Date = .now
  ) throws -> NativeReviewState {
    let state = try currentReview(accountID: accountID, expectedRevision: expectedRevision)
    var session = state.saved.session
    guard let question = state.question else { throw StudySessionError.staleQuestion }
    switch action {
    case .advance:
      guard session.currentDecision == .incorrect else { throw StudyStoreError.invalidSession }
      session.nextQuestion()
    case .overrideCorrect:
      try validateCurrentAssignment(state, accountID: accountID)
      _ = try session.mark(.overrideCorrect, for: question, now: Int64(now.timeIntervalSince1970))
      session.nextQuestion()
    case .deferQuestion:
      try session.deferQuestion(question)
      session.nextQuestion()
    case .wrapUp:
      session.setWrappingUp(true)
      session.nextQuestion()
    case .stopWrapping:
      session.setWrappingUp(false)
      session.nextQuestion()
    }
    let revision = try saveSession(
      session, accountID: accountID, expectedRevision: expectedRevision)
    return try reviewState(.init(revision: revision, session: session), accountID: accountID)
  }

  public func endReviews(accountID: String, expectedRevision: UUID) throws {
    try requireAccount(accountID)
    try removeSession(accountID: accountID, expectedRevision: expectedRevision)
  }

  public func finishReviews(accountID: String, expectedRevision: UUID) throws {
    let current = try currentReview(accountID: accountID, expectedRevision: expectedRevision)
    guard current.question == nil else { throw StudyStoreError.invalidSession }
    try removeSession(accountID: accountID, expectedRevision: expectedRevision)
  }

  private func requireReviewAccount(_ accountID: String) throws {
    try requireAccount(accountID)
    guard synchronizationCancellations == 0 else { throw StudyUploadError.alreadyRunning }
    guard let profile = try accountState(accountID: accountID)?.profile else {
      throw NativeReviewError.unavailableAccount
    }
    guard profile.vacationStartedAt == nil else { throw NativeReviewError.vacation }
  }
  private func currentReview(accountID: String, expectedRevision: UUID) throws -> NativeReviewState
  {
    try requireReviewAccount(accountID)
    guard let saved = try session(accountID: accountID), saved.revision == expectedRevision else {
      throw StudyStoreError.staleSession
    }
    return try reviewState(saved, accountID: accountID)
  }
  private func reviewState(_ saved: SavedStudySession, accountID: String) throws
    -> NativeReviewState
  {
    guard !saved.session.isPractice, saved.session.items.values.allSatisfy({ !$0.isLesson }) else {
      throw StudyStoreError.invalidSession
    }
    let subjects = try catalog(accountID: accountID)
    return .init(
      saved: saved, subjects: Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0) }))
  }
  private func requireReviewContent(_ subject: CatalogSubject, assignment: CatalogAssignment) throws
  {
    guard subject.kind == assignment.kind,
      subject.meanings.contains(where: { $0.role != .blacklist }),
      !assignment.sessionItem(id: 0, isLesson: false).hasReading
        || subject.readings.contains(where: \.isPrimary)
    else {
      throw NativeReviewError.incompleteContent(subject.id)
    }
  }
  private func validateCurrentAssignment(_ state: NativeReviewState, accountID: String) throws {
    guard let question = state.question, let item = state.saved.session.items[question.itemID],
      let subject = state.subject,
      let profile = try accountState(accountID: accountID)?.profile
    else { throw StudyStoreError.invalidSession }
    let current = try assignments(accountID: accountID).first { $0.subjectID == item.subjectID }
    guard let current, current.id == item.assignmentID, current.srsStage == item.srsStage,
      current.availableAt == item.availableAt, current.hidden != true, subject.hiddenAt == nil,
      subject.level <= profile.maxLevelGranted
    else { throw NativeReviewError.changedAssignment(item.subjectID) }
    try requireReviewContent(subject, assignment: current)
  }
}
