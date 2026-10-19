import Foundation
import StudyCore
import Testing

@testable import StudyPersistence

struct ReviewExclusionTests {
  private let account = "review-exclusion"
  private let credential = "review-exclusion-credential"
  private let now = Date(timeIntervalSince1970: 2_000_000_000)
  private func store(
    lesson: Bool = false, kind: SubjectKind = .vocabulary, count: Int = 1,
    material: Bool = true, at url: URL = URL(filePath: "/unused")
  ) async throws -> StudyStore {
    let store = try await StudyStore.open(at: url, inMemory: url.path == "/unused")
    var profile = StudyAccountProfile(username: "Review exclusion fixture")
    profile.level = 1
    profile.maxLevelGranted = 3
    var source = LegacyStudyExport(schemaVersion: 15, profile: profile)
    for id in 1...count {
      var subject = CatalogSubject(id: Int64(id), kind: kind)
      subject.level = 1
      subject.japanese = kind == .vocabulary ? "一つ" : "一"
      subject.meanings = [.init(kind == .vocabulary ? "One thing" : "One", role: .primary)]
      if kind != .radical {
        subject.readings = [
          .init(kind == .vocabulary ? "ひとつ" : "いち", isPrimary: true, kind: .onyomi)
        ]
      }
      var assignment = CatalogAssignment(id: Int64(100 + id), subjectID: subject.id, kind: kind)
      assignment.level = 1
      assignment.unlockedAt = 1
      if !lesson {
        assignment.srsStage = 2
        assignment.startedAt = 1
        assignment.availableAt = 1
      }
      source.subjects.append(subject)
      source.assignments.append(assignment)
    }
    if material {
      source.materials = [
        .init(
          serverID: 701,
          value: .init(
            subjectID: 1, meaningNote: "  Saved 🐰\n ", readingNote: "Keep reading",
            meaningSynonyms: ["Single"]), pending: false, legacyRevision: 0)
      ]
    }
    _ = try await store.importLegacyAccount(
      source, sourceID: "review-exclusion", verifiedAccountID: account,
      verifiedUsername: profile.username, credentialID: credential)
    return store
  }
  private var grouped: StudySessionOptions {
    var value = StudySessionOptions()
    value.groupMeaningReading = true
    value.batchSize = 1
    return value
  }
  private func wrong(_ state: NativeReviewState, in store: StudyStore) async throws
    -> NativeReviewState
  {
    let question = try #require(state.question)
    let answer = try await store.answerReview(
      question.kind == .reading ? "ああつ" : "banana", question: question, accountID: account,
      expectedRevision: state.saved.revision, now: now)
    #expect(answer.grade == .incorrect)
    return answer.state
  }
  private func correct(_ state: NativeReviewState, in store: StudyStore) async throws
    -> NativeReviewState
  {
    let question = try #require(state.question)
    let subject = try #require(state.subject)
    let answer = try #require(
      question.kind == .reading
        ? subject.readings.first(where: \.isPrimary)?.text
        : subject.meanings.first(where: { $0.role == .primary })?.text)
    return try await store.answerReview(
      answer, question: question, accountID: account, expectedRevision: state.saved.revision,
      now: now
    ).state
  }
  @Test(arguments: [true, false])
  func typedExclusionPreservesLatestNotesAndDoesNotCreditEitherQuestion(_ meaningFirst: Bool)
    async throws
  {
    let store = try await store()
    var options = grouped
    options.meaningFirst = meaningFirst
    let open = try await store.openReviews(accountID: account, options: options, now: now)
    let missed = try await wrong(open, in: store)
    let before = try await store.subjectDetails(subjectID: 1, accountID: account)
    var edited = try #require(before.material)
    edited.meaningNote = "Another window's latest note\n  "
    edited.meaningSynonyms.append("Unity")
    try await store.saveSubjectMaterial(
      edited, accountID: account, expectedRevision: before.savedMaterial?.revision)
    let assignments = try await store.assignments(accountID: account)
    let excluded = try await store.changeReview(
      .exclude, accountID: account, expectedRevision: missed.saved.revision, now: now)
    #expect(
      excluded.question == nil && excluded.saved.session.completedIDs.isEmpty
        && excluded.success == nil)
    #expect(excluded.saved.session.items[0]?.hasAttempts == false)
    let current = try await store.subjectDetails(subjectID: 1, accountID: account)
    #expect(
      current.material?.isExcluded == true
        && current.material?.meaningNoteText == edited.meaningNote)
    #expect(
      current.material?.readingNote == edited.readingNote
        && current.material?.meaningSynonyms == edited.meaningSynonyms)
    #expect(current.savedMaterial?.serverID == 701 && current.savedMaterial?.pending == true)
    #expect(try await store.assignments(accountID: account) == assignments)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
  @Test func partiallyAnsweredVocabularyIsRemovedWithoutSubmittingTheCorrectSide() async throws {
    let store = try await store()
    let open = try await store.openReviews(accountID: account, options: grouped, now: now)
    let half = try await correct(open, in: store)
    let missed = try await wrong(half, in: store)
    let excluded = try await store.changeReview(
      .exclude, accountID: account, expectedRevision: missed.saved.revision, now: now)
    #expect(excluded.question == nil && excluded.saved.session.completedSubmissions.isEmpty)
    #expect(excluded.saved.session.items[0]?.hasAttempts == false)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
  enum Mode: CaseIterable, Sendable { case reviews, lessons, practice }
  struct AnkiCase: Sendable {
    let mode: Mode
    let scope: StudySessionOptions.AnkiMode
    let combined: Bool
    static var all: [Self] {
      Mode.allCases.flatMap { mode in
        [StudySessionOptions.AnkiMode.meaning, .reading, .both].flatMap { scope in
          [false, true].map { Self(mode: mode, scope: scope, combined: $0) }
        }
      }
    }
  }
  @Test(arguments: AnkiCase.all)
  func revealedAnkiCanExcludeInEachStudyMode(_ example: AnkiCase) async throws {
    let (mode, scope, combined) = (example.mode, example.scope, example.combined)
    let store = try await store(lesson: mode == .lessons)
    var options = grouped
    options.ankiMode = scope
    options.meaningFirst = scope != .reading
    options.combinedAnki = combined
    let open: NativeReviewState
    switch mode {
    case .reviews:
      open = try await store.openReviews(accountID: account, options: options, now: now)
    case .lessons:
      open = try await store.openLessons(accountID: account, subjectIDs: [1], options: options)
    case .practice:
      open = try await store.openPractice(
        accountID: account, scope: .recentLessons, options: options, now: now)
    }
    let question = try #require(open.question)
    #expect(open.isAnki)
    let revealed = try await store.revealAnki(
      question: question, accountID: account, expectedRevision: open.saved.revision, now: now)
    let result = try await store.changeReview(
      .exclude, accountID: account, expectedRevision: revealed.saved.revision, now: now)
    #expect(result.question == nil && result.saved.session.completedIDs.isEmpty)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
    #expect(
      try await store.subjectDetails(subjectID: 1, accountID: account).material?.isExcluded == true)
  }
  enum Ineligible: CaseIterable, Sendable {
    case unanswered, unrevealedAnki, typedLesson, kanji, radical
  }
  @Test(arguments: Ineligible.allCases)
  func ineligibleActionsDoNotChangeNotesOrTheSession(_ kind: Ineligible) async throws {
    let store = try await store(
      lesson: kind == .typedLesson,
      kind: kind == .kanji ? .kanji : kind == .radical ? .radical : .vocabulary)
    var options = grouped
    if kind == .unrevealedAnki { options.ankiMode = .both }
    var state =
      try await
      (kind == .typedLesson
      ? store.openLessons(accountID: account, subjectIDs: [1], options: options)
      : store.openReviews(accountID: account, options: options, now: now))
    if kind != .unanswered && kind != .unrevealedAnki { state = try await wrong(state, in: store) }
    let material = try await store.subjectDetails(subjectID: 1, accountID: account)
    await #expect(throws: NativeReviewError.exclusionUnavailable) {
      try await store.changeReview(
        .exclude, accountID: account, expectedRevision: state.saved.revision, now: now)
    }
    let current = try await store.subjectDetails(subjectID: 1, accountID: account)
    #expect(
      current.savedMaterial?.revision == material.savedMaterial?.revision
        && current.material == material.material)
    #expect(try await store.session(accountID: account)?.revision == state.saved.revision)
  }
  @Test func staleWindowsAndForeignAccountsCannotExcludeTheCurrentQuestion() async throws {
    let store = try await store()
    let open = try await store.openReviews(accountID: account, options: grouped, now: now)
    let missed = try await wrong(open, in: store)
    for pair in [(account, open.saved.revision), ("another-account", missed.saved.revision)] {
      await #expect(throws: StudyStoreError.self) {
        try await store.changeReview(
          .exclude, accountID: pair.0, expectedRevision: pair.1, now: now)
      }
    }
    #expect(
      try await store.subjectDetails(subjectID: 1, accountID: account).material?.isExcluded == false
    )
    #expect(try await store.session(accountID: account)?.revision == missed.saved.revision)
  }
  enum Changed: CaseIterable, Sendable { case stage, identity, hidden, subscription, vacation }
  @Test(arguments: Changed.allCases)
  func refreshedAssignmentOrAccessChangesCannotApplyAnExclusion(_ changed: Changed) async throws {
    let store = try await store(material: false)
    let open = try await store.openReviews(accountID: account, options: grouped, now: now)
    let missed = try await wrong(open, in: store)
    var profile = try #require(await store.accountState(accountID: account)).profile
    var assignments = try await store.assignments(accountID: account)
    switch changed {
    case .stage: assignments[0].srsStage = 6
    case .identity:
      let old = assignments[0]
      var replacement = CatalogAssignment(id: old.id + 1, subjectID: old.subjectID, kind: old.kind)
      replacement.level = old.level
      replacement.srsStage = old.srsStage
      replacement.startedAt = old.startedAt
      replacement.availableAt = old.availableAt
      replacement.unlockedAt = old.unlockedAt
      assignments = [replacement]
    case .hidden: assignments[0].hidden = true
    case .subscription: profile.maxLevelGranted = 0
    case .vacation: profile.vacationStartedAt = 1
    }
    let download = StudyDownload(
      accountID: account, profile: profile, subjects: try await store.catalog(accountID: account),
      assignments: assignments)
    _ = try await store.applyDownload(
      download, credentialID: credential, baseline: store.refreshBaseline(accountID: account))
    await #expect(throws: NativeReviewError.self) {
      try await store.changeReview(
        .exclude, accountID: account, expectedRevision: missed.saved.revision, now: now)
    }
    #expect(try await store.materials(accountID: account).isEmpty)
    #expect(try await store.session(accountID: account)?.revision == missed.saved.revision)
  }
  @Test(arguments: [false, true])
  func sessionFailureRollsBackAnAlreadyWrittenExclusion(_ existingMaterial: Bool) async throws {
    let store = try await store(material: existingMaterial)
    let open = try await store.openReviews(accountID: account, options: grouped, now: now)
    let missed = try await wrong(open, in: store)
    let before = try await store.subjectDetails(subjectID: 1, accountID: account)
    var material = before.material ?? StudyMaterial(subjectID: 1)
    material.isExcluded = true
    var session = missed.saved.session
    try session.excludeQuestion(try #require(missed.question))
    session.nextQuestion()
    await #expect(throws: StudyStoreError.self) {
      try await store.commitReviewExclusion(
        session, material: .init(material: material, version: before.savedMaterial?.revision),
        accountID: account, expectedRevision: UUID(), now: now)
    }
    let after = try await store.subjectDetails(subjectID: 1, accountID: account)
    #expect(
      after.material == before.material
        && after.savedMaterial?.revision == before.savedMaterial?.revision)
    #expect(try await store.session(accountID: account)?.revision == missed.saved.revision)
    #expect(try await store.pendingReviews(accountID: account).isEmpty)
  }
  @Test func anAlreadyExcludedItemKeepsItsMaterialRevisionWhenRemovedFromTheQuiz() async throws {
    let store = try await store()
    let open = try await store.openReviews(accountID: account, options: grouped, now: now)
    let missed = try await wrong(open, in: store)
    let before = try await store.setSubjectExcluded(
      subjectID: 1, accountID: account, excluded: true)
    let result = try await store.changeReview(
      .exclude, accountID: account, expectedRevision: missed.saved.revision, now: now)
    #expect(result.question == nil)
    #expect(
      try await store.subjectDetails(subjectID: 1, accountID: account).savedMaterial?.revision
        == before.savedMaterial?.revision)
  }
  @Test func exclusionRetainsPreviouslyCompletedAndAttemptedUploads() async throws {
    let store = try await store(count: 2)
    let open = try await store.openReviews(accountID: account, options: grouped, now: now)
    let first = try await correct(open, in: store)
    let second = try await correct(first, in: store)
    let saved = try #require(await store.pendingReviews(accountID: account).first)
    try await store.beginReviewAttempt(saved)
    let attempted = try await store.pendingReviews(accountID: account)
    let missed = try await wrong(second, in: store)
    let result = try await store.changeReview(
      .exclude, accountID: account, expectedRevision: missed.saved.revision, now: now)
    #expect(result.question == nil && result.saved.session.completedIDs.count == 1)
    #expect(try await store.pendingReviews(accountID: account) == attempted)
  }
  @Test func exclusionAndQueueRemovalReopenTogetherWithoutAReviewSubmission() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "study.store")
    let result: NativeReviewState
    do {
      let store = try await store(at: url)
      let open = try await store.openReviews(accountID: account, options: grouped, now: now)
      let missed = try await wrong(open, in: store)
      result = try await store.changeReview(
        .exclude, accountID: account, expectedRevision: missed.saved.revision, now: now)
    }
    let reopened = try await StudyStore.open(at: url)
    let resumed = try await reopened.openReviews(accountID: account, now: now)
    #expect(resumed.question == nil && resumed.saved.revision == result.saved.revision)
    #expect(
      try await reopened.subjectDetails(subjectID: 1, accountID: account).material?.isExcluded
        == true)
    #expect(try await reopened.pendingReviews(accountID: account).isEmpty)
    try await reopened.finishReviews(accountID: account, expectedRevision: resumed.saved.revision)
    await #expect(throws: NativeReviewError.noReviews) {
      try await reopened.openReviews(accountID: account, now: now)
    }
  }
}
