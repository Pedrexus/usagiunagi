import Foundation
import StudyCore

/// A consistent offline read; neither credentials nor SwiftData models leave the store.
public struct NativeReviewState: Sendable {
  public let saved: SavedStudySession
  public let subjects: [Int64: CatalogSubject]
  /// A transient receipt for a newly saved correct answer; never replayed on resume.
  public let success: StudyMarkResult?
  public var isAnki: Bool {
    question.map { saved.session.options.ankiMode.includes($0.kind) } == true
  }
  public var combinesAnki: Bool {
    isAnki && saved.session.options.ankiMode == .both && saved.session.options.combinedAnki
      && question.flatMap { saved.session.items[$0.itemID] }?.hasReading == true
  }
  public var isPractice: Bool { saved.session.isPractice }
  public var isLesson: Bool { saved.session.items.values.first?.isLesson == true }
  public var question: StudyQuestion? {
    guard let question = saved.session.question,
      saved.session.activeIDs.contains(question.itemID)
    else { return nil }
    return question
  }
  public func summary(showOldMeanings: Bool) -> StudySessionSummary {
    StudySessionSummary(
      entries: saved.session.completedIDs.compactMap { id in
        guard let item = saved.session.items[id] else { return nil }
        let catalog = subjects[item.subjectID]
        let subject = catalog.map { value in
          StudySubject(
            id: value.id, characters: value.japanese,
            meaning: value.meanings.filter {
              $0.role != .blacklist
                && ($0.role != .auxiliaryWhitelist || (value.kind == .radical && showOldMeanings))
            }.map(\.text).joined(separator: ", "),
            readings: value.readings.filter { value.kind != .kanji || $0.isPrimary }.map(\.text),
            kind: value.kind, level: value.level, documentURL: URL(string: value.documentURL))
        }
        return .init(
          id: id, subject: subject, level: subject?.level ?? 0,
          meaningWrong: item.meaning.firstAnswerWrong == true,
          readingWrong: item.reading.firstAnswerWrong == true)
      })
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

public enum NativeReviewError: Error, LocalizedError, Equatable {
  case unavailableAccount, vacation, noReviews, noLessons, apprenticeLimitReached,
    invalidLessonSelection,
    incompatibleAnswerMode, noPracticeItems, practiceInProgress, exclusionUnavailable
  case sessionInProgress(isLesson: Bool)
  case incompleteContent(Int64)
  case changedAssignment(Int64)
  public var errorDescription: String? {
    switch self {
    case .exclusionUnavailable:
      "Exclude vocabulary after revealing an answer. Typed lesson answers cannot use this action."
    case .noPracticeItems: "No items are available for this practice selection."
    case .practiceInProgress:
      "Resume or end your saved practice before starting a different study session."
    case .unavailableAccount: "Refresh this account before starting reviews."
    case .vacation: "Study sessions are paused while your account is on vacation."
    case .incompatibleAnswerMode:
      "This question uses Anki mode. Show the answer, then mark it correct or incorrect."
    case .noReviews: "No reviews are available in the saved account data."
    case .apprenticeLimitReached:
      "The Apprentice limit is reached. Review existing items or change the limit in lesson settings."
    case .noLessons: "No lessons are available in the saved account data."
    case .invalidLessonSelection:
      "These lessons are no longer available. Return to Lessons and choose again."
    case .sessionInProgress(let isLesson):
      "Finish or end your saved \(isLesson ? "lesson quiz" : "review session") before starting a different session. Completed answers will stay saved."
    case .incompleteContent(let id):
      "Subject \(id) is missing study content. Refresh before reviewing it."
    case .changedAssignment(let id):
      "Subject \(id) changed since this session began. Your saved answers remain on this device."
    }
  }
}

public enum NativeReviewAction: Sendable {
  case advance, overrideCorrect, deferQuestion, wrapUp, stopWrapping, exclude
}

extension StudyStore {
  /// Reopen the existing session unchanged, or select due assignments from the offline catalog.
  /// No network request or upload occurs here. Each window must use the returned revision.
  public func openReviews(
    accountID: String, options: StudySessionOptions = .init(), now: Date = .now,
    lessonPreferences: StudyLessonPreferences = .init(), policy: StudyReviewPolicy = .init()
  ) throws -> NativeReviewState {
    try requireReviewAccount(accountID)
    if let saved = try session(accountID: accountID) {
      let state = try reviewState(saved, accountID: accountID)
      guard !state.isPractice else { throw NativeReviewError.practiceInProgress }
      guard !state.isLesson else { throw NativeReviewError.sessionInProgress(isLesson: true) }
      return state
    }
    let subjects = try catalog(accountID: accountID)
    let byID = Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0) })
    let account = try accountState(accountID: accountID)!
    let profile = account.profile
    let due = try availability(accountID: accountID, now: now, lessonPreferences: lessonPreferences)
      .scheduled
    var selected: [CatalogAssignment] = []
    for assignment in due {
      guard let subject = byID[assignment.subjectID] else {
        throw NativeReviewError.incompleteContent(assignment.subjectID)
      }
      if subject.hiddenAt != nil || subject.level > profile.maxLevelGranted { continue }
      try requireReviewContent(subject, assignment: assignment)
      selected.append(assignment)
    }
    var generator = SystemRandomNumberGenerator()
    let hour = floor(now.timeIntervalSince1970 / 3600) * 3600
    selected = try policy.select(selected, using: &generator) { assignment in
      let subject = byID[assignment.subjectID]!
      let ratio =
        policy.order == .longestRelativeWait
        ? (hour - Double(assignment.availableAt ?? 0))
          / (try StudySRSSystem.interval(
            subject: subject, stage: assignment.srsStage, systems: account.systems)) : 0
      return StudyReviewSortKey(
        stage: assignment.srsStage, level: subject.level, kind: assignment.kind,
        availableAt: assignment.availableAt ?? 0, relativeWait: ratio)
    }
    guard !selected.isEmpty else { throw NativeReviewError.noReviews }

    var session = try StudySession(
      items: selected.enumerated().map { $0.element.sessionItem(id: $0.offset, isLesson: false) },
      options: nativeSessionOptions(options))
    session.nextQuestion()
    return try saveReviewState(session, accountID: accountID, expectedRevision: nil)
  }

  public func openPractice(
    accountID: String, scope: StudyPracticeScope,
    options: StudySessionOptions = .init(), now: Date = .now,
    lessonPreferences: StudyLessonPreferences = .init(), policy: StudyReviewPolicy = .init()
  ) throws -> NativeReviewState {
    try requireReviewAccount(accountID, practice: true)
    if let saved = try session(accountID: accountID) {
      let state = try reviewState(saved, accountID: accountID)
      guard state.isPractice else {
        throw NativeReviewError.sessionInProgress(isLesson: state.isLesson)
      }
      guard saved.session.practiceScope == scope else { throw NativeReviewError.practiceInProgress }
      return state
    }
    let available = try availability(
      accountID: accountID, now: now, leechThreshold: policy.normalized.leechThreshold,
      lessonPreferences: lessonPreferences)
    let selected = available.practice(scope).shuffled()
    guard !selected.isEmpty else { throw NativeReviewError.noPracticeItems }
    let subjects = Dictionary(uniqueKeysWithValues: available.subjects.map { ($0.id, $0) })
    for assignment in selected {
      guard let subject = subjects[assignment.subjectID] else {
        throw NativeReviewError.incompleteContent(assignment.subjectID)
      }
      try requireReviewContent(subject, assignment: assignment)
    }
    var session = try StudySession(
      items: selected.enumerated().map { $0.element.sessionItem(id: $0.offset, isLesson: false) },
      options: nativeSessionOptions(options), isPractice: true, practiceScope: scope)
    session.nextQuestion()
    return try saveReviewState(session, accountID: accountID, expectedRevision: nil)
  }

  /// Available means unlocked, unstarted, visible, accessible and not pending upload.
  public func availableLessons(
    accountID: String, lessonPreferences: StudyLessonPreferences = .init()
  ) throws -> [CatalogSubject] {
    try requireReviewAccount(accountID)
    let byID = Dictionary(
      uniqueKeysWithValues: try catalog(accountID: accountID).map { ($0.id, $0) })
    let profile = try accountState(accountID: accountID)!.profile
    var result: [CatalogSubject] = []
    let available = try availability(accountID: accountID, lessonPreferences: lessonPreferences)
    guard !available.apprenticeLimitReached else { throw NativeReviewError.apprenticeLimitReached }
    for assignment in available.lessons {
      guard let subject = byID[assignment.subjectID] else {
        throw NativeReviewError.incompleteContent(assignment.subjectID)
      }
      guard subject.hiddenAt == nil, subject.level <= profile.maxLevelGranted
      else { continue }
      try requireReviewContent(subject, assignment: assignment)
      result.append(subject)
    }
    return result
  }

  /// Lesson quizzes use the atomic review writer and never replace paused work.
  public func openLessons(
    accountID: String, subjectIDs: [Int64]? = nil, options: StudySessionOptions = .init(),
    lessonPreferences: StudyLessonPreferences = .init()
  ) throws -> NativeReviewState {
    try requireReviewAccount(accountID)
    if let subjectIDs, subjectIDs.isEmpty || Set(subjectIDs).count != subjectIDs.count {
      throw NativeReviewError.invalidLessonSelection
    }
    if let saved = try session(accountID: accountID) {
      let state = try reviewState(saved, accountID: accountID)
      guard !state.isPractice else { throw NativeReviewError.practiceInProgress }
      guard state.isLesson else { throw NativeReviewError.sessionInProgress(isLesson: false) }
      if let subjectIDs, Set(subjectIDs) != Set(saved.session.items.values.map(\.subjectID)) {
        throw NativeReviewError.sessionInProgress(isLesson: true)
      }
      return state
    }
    guard let subjectIDs else { throw NativeReviewError.noLessons }
    let available = Set(
      try availableLessons(accountID: accountID, lessonPreferences: lessonPreferences).map(\.id))
    guard Set(subjectIDs).isSubset(of: available) else {
      throw NativeReviewError.invalidLessonSelection
    }
    let byID = Dictionary(
      uniqueKeysWithValues: try assignments(accountID: accountID).map { ($0.subjectID, $0) })
    var session = try StudySession(
      items: subjectIDs.enumerated().map {
        byID[$0.element]!.sessionItem(id: $0.offset, isLesson: true)
      }, options: nativeSessionOptions(options))
    session.nextQuestion()
    return try saveReviewState(session, accountID: accountID, expectedRevision: nil)
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
    guard !state.isAnki else { throw NativeReviewError.incompatibleAnswerMode }
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
    var success: StudyMarkResult?
    switch grade {
    case .precise, .imprecise:
      success = try session.mark(.correct, for: question, now: Int64(now.timeIntervalSince1970))
      session.nextQuestion()
    case .incorrect:
      _ = try session.mark(.incorrect, for: question, now: Int64(now.timeIntervalSince1970))
    case .isReadingButWantMeaning: try session.creditReading(question)
    default: return .init(state: state, grade: grade, normalized: normalized)
    }
    state = try saveReviewState(
      session, accountID: accountID, expectedRevision: expectedRevision, success: success, now: now)
    return .init(state: state, grade: grade, normalized: normalized)
  }

  public func changeReview(
    _ action: NativeReviewAction, accountID: String,
    expectedRevision: UUID, now: Date = .now
  ) throws -> NativeReviewState {
    let state = try currentReview(accountID: accountID, expectedRevision: expectedRevision)
    var session = state.saved.session
    guard let question = state.question else { throw StudySessionError.staleQuestion }
    var success: StudyMarkResult?
    switch action {
    case .advance:
      guard session.currentDecision == .incorrect else { throw StudyStoreError.invalidSession }
      session.nextQuestion()
    case .overrideCorrect:
      guard !state.isLesson && !state.isAnki else { throw StudySessionError.invalidOverride }
      try validateCurrentAssignment(state, accountID: accountID)
      success = try session.mark(
        .overrideCorrect, for: question, now: Int64(now.timeIntervalSince1970))
      session.nextQuestion()
    case .exclude:
      guard session.currentDecision == .incorrect, let subject = state.subject,
        subject.kind == .vocabulary,
        !state.isLesson || state.isAnki
      else { throw NativeReviewError.exclusionUnavailable }
      try validateCurrentAssignment(state, accountID: accountID)
      let current = try subjectDetails(subjectID: subject.id, accountID: accountID)
      var material = current.material ?? StudyMaterial(subjectID: current.subject.id)
      material.isExcluded = true
      try session.excludeQuestion(question)
      session.nextQuestion()
      let saved = try commitReviewExclusion(
        session, material: .init(material: material, version: current.savedMaterial?.revision),
        accountID: accountID, expectedRevision: expectedRevision, now: now)
      return try reviewState(saved, accountID: accountID)
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
    return try saveReviewState(
      session, accountID: accountID, expectedRevision: expectedRevision, success: success, now: now)
  }

  /// One transaction owns the exclusion marker and queue removal; it never credits the item.
  func commitReviewExclusion(
    _ session: StudySession, material: StudyMaterialEdit<UUID>, accountID: String,
    expectedRevision: UUID, now: Date
  ) throws -> SavedStudySession {
    let revision = UUID()
    try transaction {
      try writeSubjectMaterial(
        material.material, accountID: accountID, expectedRevision: material.version)
      try writeSession(
        session, accountID: accountID, expectedRevision: expectedRevision, revision: revision,
        now: now)
    }
    return .init(revision: revision, session: session)
  }

  /// Revealing an Anki answer records the provisional miss before presenting its details,
  /// matching the original review flow. A later assessment changes that same decision.
  public func revealAnki(
    question: StudyQuestion, accountID: String, expectedRevision: UUID,
    now: Date = .now
  ) throws -> NativeReviewState {
    let state = try currentReview(accountID: accountID, expectedRevision: expectedRevision)
    guard state.question == question else { throw StudySessionError.staleQuestion }
    guard state.isAnki else { throw NativeReviewError.incompatibleAnswerMode }
    guard state.saved.session.currentDecision == nil else {
      throw StudySessionError.alreadyAnswered
    }
    try validateCurrentAssignment(state, accountID: accountID)
    var session = state.saved.session
    _ = try session.mark(.incorrect, for: question, now: Int64(now.timeIntervalSince1970))
    return try saveReviewState(
      session, accountID: accountID, expectedRevision: expectedRevision, now: now)
  }

  /// The combined card's two decisions and any completed submission commit together.
  public func assessAnki(
    correct: Bool, question: StudyQuestion, accountID: String,
    expectedRevision: UUID, now: Date = .now
  ) throws -> NativeReviewState {
    let state = try currentReview(accountID: accountID, expectedRevision: expectedRevision)
    guard state.question == question else { throw StudySessionError.staleQuestion }
    guard state.isAnki, state.saved.session.currentDecision == .incorrect else {
      throw StudyStoreError.invalidSession
    }
    try validateCurrentAssignment(state, accountID: accountID)
    var session = state.saved.session
    var success: StudyMarkResult?
    if correct {
      success = try session.mark(
        .overrideCorrect, for: question, now: Int64(now.timeIntervalSince1970))
      if state.combinesAnki, success?.subjectFinished == false {
        guard let other = session.nextQuestion(continuingCurrentItem: true),
          other.itemID == question.itemID
        else {
          throw StudyStoreError.invalidSession
        }
        success = try session.mark(.correct, for: other, now: Int64(now.timeIntervalSince1970))
      }
    }
    session.nextQuestion()
    return try saveReviewState(
      session, accountID: accountID, expectedRevision: expectedRevision, success: success, now: now)
  }

  private func nativeSessionOptions(_ options: StudySessionOptions) -> StudySessionOptions {
    var value = options
    value.combinedAnki = options.ankiMode == .both && options.combinedAnki
    return value
  }
  private func saveReviewState(
    _ session: StudySession, accountID: String, expectedRevision: UUID?,
    success: StudyMarkResult? = nil, now: Date = .now
  ) throws -> NativeReviewState {
    let revision = try saveSession(
      session, accountID: accountID, expectedRevision: expectedRevision, now: now)
    return try reviewState(
      .init(revision: revision, session: session), accountID: accountID, success: success)
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

  private func requireReviewAccount(_ accountID: String, practice: Bool = false) throws {
    try requireAccount(accountID)
    guard synchronizationCancellations == 0 else { throw StudyUploadError.alreadyRunning }
    guard let profile = try accountState(accountID: accountID)?.profile else {
      throw NativeReviewError.unavailableAccount
    }
    guard practice || profile.vacationStartedAt == nil else { throw NativeReviewError.vacation }
  }
  private func currentReview(accountID: String, expectedRevision: UUID) throws -> NativeReviewState
  {
    try requireAccount(accountID)
    guard let saved = try session(accountID: accountID), saved.revision == expectedRevision else {
      throw StudyStoreError.staleSession
    }
    try requireReviewAccount(accountID, practice: saved.session.isPractice)
    return try reviewState(saved, accountID: accountID)
  }
  private func reviewState(
    _ saved: SavedStudySession, accountID: String, success: StudyMarkResult? = nil
  ) throws
    -> NativeReviewState
  {
    guard let first = saved.session.items.values.first,
      !saved.session.isPractice || (!first.isLesson && saved.session.practiceScope != nil),
      saved.session.items.values.allSatisfy({ $0.isLesson == first.isLesson })
    else {
      throw StudyStoreError.invalidSession
    }
    let subjects = try catalog(accountID: accountID)
    return .init(
      saved: saved, subjects: Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0) }),
      success: success)
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
    if state.isPractice {
      guard
        let current = try assignments(accountID: accountID).first(where: {
          $0.subjectID == item.subjectID
        }),
        current.hidden != true, subject.hiddenAt == nil, subject.level <= profile.maxLevelGranted
      else {
        throw NativeReviewError.changedAssignment(item.subjectID)
      }
      try requireReviewContent(subject, assignment: current)
      return
    }
    let current = try assignments(accountID: accountID).first { $0.subjectID == item.subjectID }
    guard let current, current.id == item.assignmentID, current.srsStage == item.srsStage,
      (current.availableAt ?? 0) == item.availableAt, current.hidden != true,
      subject.hiddenAt == nil,
      subject.level <= profile.maxLevelGranted
    else { throw NativeReviewError.changedAssignment(item.subjectID) }
    guard
      item.isLesson
        ? current.unlockedAt != nil && current.startedAt == nil && current.srsStage == 0
        : current.startedAt != nil && (1...8).contains(current.srsStage)
    else { throw NativeReviewError.changedAssignment(item.subjectID) }
    try requireReviewContent(subject, assignment: current)
  }
}
