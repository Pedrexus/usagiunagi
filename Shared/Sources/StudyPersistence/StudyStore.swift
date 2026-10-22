import Foundation
import StudyCore
import SwiftData

public struct SavedStudySession: Sendable {
  public let revision: UUID
  public let session: StudySession
}

public struct SavedReview: Codable, Equatable, Sendable {
  public let accountID: String
  public let subjectID: Int64
  public let revision: UUID
  public let submission: StudyReviewSubmission
  public let originalItem: StudySessionItem
  public let originalAssignment: CatalogAssignment?
  /// An attempt survives restart. It must be reconciled rather than automatically replayed.
  public let attempted: Bool
  public let issue: StudyUploadIssue?
}

public enum StudyStoreError: Error, LocalizedError {
  case invalidIdentity, sampleData, staleSession
  case pendingReview(Int64)
  case invalidSession, alreadyAttempted, staleMaterial, invalidMaterial
  public var errorDescription: String? {
    switch self {
    case .invalidIdentity:
      "Reconnect to WaniKani to verify this account before saving study progress."
    case .sampleData: "Sample data cannot replace saved account data."
    case .staleSession: "This study session changed in another window. Reopen the current session."
    case .pendingReview(let id): "Subject \(id) already has a saved review awaiting upload."
    case .invalidSession:
      "The session could not be saved because its completed answers are inconsistent."
    case .staleMaterial: "These notes changed in another window. Reload them before saving."
    case .invalidMaterial:
      "The study material could not be saved because its subject identity is invalid."
    case .alreadyAttempted: "This review was already sent. Check WaniKani before retrying."
    }
  }
}

public enum StudyAutomaticWork: Equatable, Sendable { case none, ready, requiresAttention }

/// One actor/container per local store. Model values never escape its executor.
/// CloudKit is deliberately disabled: WaniKani owns cross-device study progress.
@ModelActor public actor StudyStore {
  var applicationLease: StudyStoreLease?
  var uploadGeneration = UUID()
  private var changeObservers: [UUID: AsyncStream<Void>.Continuation] = [:]
  var synchronizationRun: SynchronizationRun?
  var synchronizationCancellations = 0
  var refreshRun: (id: UUID, task: Task<StudySnapshot, any Error>)?
  var uploadRun: (id: UUID, task: Task<StudyUploadReport, any Error>)?
  var recoveryRun: (id: UUID, task: Task<StudyRecoveryComparison, any Error>)?
  @concurrent public static func open(at url: URL, inMemory: Bool = false) async throws
    -> StudyStore
  {
    let schema = StudySchemaV1.unversioned
    let configuration: ModelConfiguration
    if inMemory {
      configuration = ModelConfiguration(
        schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    } else {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    }
    return StudyStore(
      modelContainer: try ModelContainer(for: schema, configurations: configuration))
  }

  /// App-owned consumers receive only committed changes; slow readers coalesce notifications.
  public func changes() -> AsyncStream<Void> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    changeObservers[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeChangeObserver(id) }
    }
    continuation.yield()
    return stream
  }
  private func removeChangeObserver(_ id: UUID) { changeObservers[id] = nil }

  /// Attempt markers and issues require recovery; they can never authorize an automatic write.
  public func automaticWorkState(accountID: String) throws -> StudyAutomaticWork {
    try requireAccount(accountID)
    let reviews = try pendingReviews(accountID: accountID)
    let materials = try materials(accountID: accountID).filter(\.pending)
    guard !reviews.isEmpty || !materials.isEmpty else { return .none }
    return reviews.contains { !$0.attempted && $0.issue == nil }
      || materials.contains { $0.attemptedRevision == nil && $0.issue == nil }
      ? .ready : .requiresAttention
  }

  func transaction(_ body: () throws -> Void) throws {
    modelContext.autosaveEnabled = false
    do { try modelContext.transaction(block: body) } catch {
      modelContext.rollback()
      throw error
    }
    for observer in changeObservers.values { observer.yield() }
  }

  public func snapshot(credentialID: String) throws -> StudySnapshot? {
    guard
      let snapshot = try modelContext.fetch(
        FetchDescriptor<SnapshotRecord>(
          predicate:
            #Predicate { $0.credentialID == credentialID })
      ).first?.snapshot
    else { return nil }
    guard let accountID = snapshot.accountID else { return snapshot }
    let pending = try pendingReviews(accountID: accountID)
    let ids = Set(pending.map(\.subjectID))
    let currentAssignments: [StudyAssignment]
    if try accountState(accountID: accountID) != nil {
      let visible = Set(snapshot.subjects.map(\.id)).union(snapshot.assignments.map(\.subjectID))
      currentAssignments = try assignments(accountID: accountID).filter {
        $0.hidden != true && visible.contains($0.subjectID)
      }.map(\.summary)
    } else {
      // A former JSON-only statistics cache has no authoritative assignment table yet.
      currentAssignments = snapshot.assignments
    }
    return StudySnapshot(
      accountID: accountID, username: snapshot.username, currentLevel: snapshot.currentLevel,
      onVacation: snapshot.onVacation,
      assignments: currentAssignments.filter { !ids.contains($0.subjectID) },
      statistics: snapshot.statistics, levels: snapshot.levels, subjects: snapshot.subjects,
      savedAt: snapshot.savedAt, pendingReviews: pending.count, isSample: snapshot.isSample,
      requiresAssignmentRefresh: snapshot.requiresAssignmentRefresh, pendingSubjectIDs: ids)
  }

  public func saveSnapshot(_ snapshot: StudySnapshot, credentialID: String) throws {
    guard !snapshot.isSample else { throw StudyStoreError.sampleData }
    guard !credentialID.isEmpty, let id = snapshot.accountID, !id.isEmpty else {
      throw StudyStoreError.invalidIdentity
    }
    try transaction {
      let existing = try modelContext.fetch(
        FetchDescriptor<SnapshotRecord>(
          predicate:
            #Predicate { $0.credentialID == credentialID })
      ).first
      if let previous = existing?.snapshot.accountID, previous != id {
        throw StudyStoreError.invalidIdentity
      }
      if let existing {
        existing.snapshot = snapshot
      } else {
        modelContext.insert(SnapshotRecord(snapshot, credentialID: credentialID))
      }
    }
  }

  public func removeSnapshot(credentialID: String) throws {
    try transaction {
      for row in try modelContext.fetch(
        FetchDescriptor<SnapshotRecord>(
          predicate:
            #Predicate { $0.credentialID == credentialID }))
      { modelContext.delete(row) }
    }
  }

  func requireAccount(_ accountID: String) throws {
    guard !accountID.isEmpty else { throw StudyStoreError.invalidIdentity }
    guard
      try modelContext.fetch(FetchDescriptor<SnapshotRecord>()).contains(where: {
        $0.snapshot.accountID == accountID && !$0.snapshot.isSample
      })
    else { throw StudyStoreError.invalidIdentity }
  }

  private func sessionRecord(_ accountID: String) throws -> SessionRecord? {
    try modelContext.fetch(
      FetchDescriptor<SessionRecord>(
        predicate:
          #Predicate { $0.accountID == accountID })
    ).first
  }

  public func session(accountID: String) throws -> SavedStudySession? {
    try sessionRecord(accountID).map {
      SavedStudySession(revision: $0.revision, session: $0.session)
    }
  }

  /// Saves the session and only its newly completed answers in the same native transaction.
  /// A revision prevents an older scene from replacing newer progress or resubmitting an answer.
  @discardableResult public func saveSession(
    _ session: StudySession, accountID: String,
    expectedRevision: UUID?, now: Date = .now
  ) throws -> UUID {
    let revision = UUID()
    try transaction {
      try writeSession(
        session, accountID: accountID, expectedRevision: expectedRevision, revision: revision,
        now: now)
    }
    return revision
  }

  /// Caller owns the transaction, allowing a queue change and notes edit to commit together.
  func writeSession(
    _ session: StudySession, accountID: String, expectedRevision: UUID?, revision: UUID, now: Date
  ) throws {
    try requireAccount(accountID)
    let old = try sessionRecord(accountID)
    guard old?.revision == expectedRevision else { throw StudyStoreError.staleSession }
    let previous = Set(old?.session.completedIDs ?? [])
    guard previous.isSubset(of: Set(session.completedIDs)) else {
      throw StudyStoreError.invalidSession
    }
    if let old {
      guard old.session.isPractice == session.isPractice,
        old.session.practiceScope == session.practiceScope,
        old.session.items.count == session.items.count,
        old.session.items.allSatisfy({ id, item in
          session.items[id]?.subjectID == item.subjectID
            && session.items[id]?.assignmentID == item.assignmentID
            && session.items[id]?.isLesson == item.isLesson
        })
      else { throw StudyStoreError.invalidSession }
    }
    for submission in session.completedSubmissions where !previous.contains(submission.itemID) {
      let subjectID = submission.subjectID
      guard subjectID > 0, submission.assignmentID > 0,
        let item = session.items[submission.itemID]
      else { throw StudyStoreError.invalidSession }
      guard
        try modelContext.fetchCount(
          FetchDescriptor<ReviewRecord>(
            predicate:
              #Predicate { $0.accountID == accountID && $0.subjectID == subjectID })) == 0
      else {
        throw StudyStoreError.pendingReview(subjectID)
      }
      modelContext.insert(
        ReviewRecord(accountID: accountID, submission: submission, originalItem: item))
      if submission.meaningWrong || submission.readingWrong,
        let row = try AccountRecord.fetch(in: modelContext, accountID: accountID),
        let subject = try catalog(accountID: accountID).first(where: { $0.id == subjectID })
      {
        var state = row.state
        if let index = state.progress.firstIndex(where: { $0.subjectID == subjectID }) {
          state.progress[index].lastMistakeAt = Int64(now.timeIntervalSince1970)
        } else {
          state.progress.append(
            .init(
              subjectID: subjectID, level: subject.level, srsStage: item.srsStage,
              kind: subject.kind, lastMistakeLocalTime: nil, legacyRevision: 0,
              lastMistakeAt: Int64(now.timeIntervalSince1970)))
        }
        row.state = state
      }

    }
    if let old {
      old.session = session
      old.revision = revision
    } else {
      modelContext.insert(
        SessionRecord(accountID: accountID, session: session, revision: revision))
    }
  }

  public func removeSession(accountID: String, expectedRevision: UUID) throws {
    try transaction {
      guard let row = try sessionRecord(accountID), row.revision == expectedRevision else {
        throw StudyStoreError.staleSession
      }
      // Queued answers remain durable independently of the finished session.
      modelContext.delete(row)
    }
  }

  public func pendingReviews(accountID: String) throws -> [SavedReview] {
    try modelContext.fetch(
      FetchDescriptor<ReviewRecord>(predicate: #Predicate { $0.accountID == accountID })
    )
    .map(\.saved).sorted { $0.subjectID < $1.subjectID }
  }

  /// Commit before the network write. No automatic reset of attempted records on process launch.
  public func beginReviewAttempt(_ review: SavedReview) throws {
    try transaction {
      guard let row = try reviewRecord(review), !row.attempted else {
        throw StudyStoreError.alreadyAttempted
      }
      row.attempted = true
      try requireCatalogRead(accountID: review.accountID)
    }
  }

  /// Call only after a validated successful response for this exact attempt.
  public func acknowledgeReview(_ review: SavedReview) throws {
    try transaction {
      if let row = try reviewRecord(review), row.attempted {
        modelContext.delete(row)
        try requireCatalogRead(accountID: review.accountID)
      }
    }
  }

  func reviewRecord(_ review: SavedReview) throws -> ReviewRecord? {
    let accountID = review.accountID
    let subjectID = review.subjectID
    let revision = review.revision
    return try modelContext.fetch(
      FetchDescriptor<ReviewRecord>(
        predicate:
          #Predicate {
            $0.accountID == accountID && $0.subjectID == subjectID && $0.revision == revision
          })
    ).first
  }
}
