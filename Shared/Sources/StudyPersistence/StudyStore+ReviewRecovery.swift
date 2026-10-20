import Foundation
import StudyCore
import SwiftData

public struct StudyReviewComparison: Identifiable, Sendable {
  public let id: UUID
  public let saved: SavedReview
  public let remote: CatalogAssignment?
  public let checkedAt: Date
  let generation: UUID
  let credentialID: String
  let assignmentRevision: UUID?
}

/// A user's local resolution, not a receipt or evidence that WaniKani accepted an answer.
public struct ArchivedStudyReview: Codable, Identifiable, Sendable {
  public let id: UUID
  public let saved: SavedReview
  public let subject: StudySubject?
  public let cachedAssignment: CatalogAssignment?
  public let cachedProgress: SubjectProgress?
  public let observedAssignment: CatalogAssignment?
  public let checkedAt: Date
  public let archivedAt: Date
}

extension StudyStore {
  public func archivedReviews(accountID: String) throws -> [ArchivedStudyReview] {
    try requireAccount(accountID)
    return try modelContext.fetch(
      FetchDescriptor<ArchivedReviewRecord>(predicate: #Predicate { $0.accountID == accountID })
    )
    .map(\.answer).sorted { $0.archivedAt > $1.archivedAt }
  }

  /// Move the exact answer into a read-only local archive. Refresh must reload current progress;
  /// an old assignment must not become reviewable merely because its pending answer was removed.
  @discardableResult public func archiveReview(_ comparison: StudyReviewComparison) throws
    -> ArchivedStudyReview
  {
    try requireRecoveryIdle(accountID: comparison.saved.accountID)
    guard comparison.generation == uploadGeneration,
      try snapshot(credentialID: comparison.credentialID)?.accountID == comparison.saved.accountID
    else { throw StudyRecoveryError.changed }
    let accountID = comparison.saved.accountID
    let subjectID = comparison.saved.subjectID
    let subject = try modelContext.fetch(
      FetchDescriptor<CatalogRecord>(
        predicate: #Predicate {
          $0.accountID == accountID && $0.subjectID == subjectID
        })
    ).first?.subject.summary
    let cachedAssignment = try recoveryAssignment(comparison.saved)?.assignment
    let cachedProgress = try accountState(accountID: accountID)?.progress.first {
      $0.subjectID == subjectID
    }
    let archived = ArchivedStudyReview(
      id: UUID(), saved: comparison.saved, subject: subject,
      cachedAssignment: cachedAssignment, cachedProgress: cachedProgress,
      observedAssignment: comparison.remote, checkedAt: comparison.checkedAt, archivedAt: Date())
    try transaction {
      let row = try reviewForRecovery(comparison.saved)
      let assignment = try recoveryAssignment(comparison.saved)
      guard assignment?.revision == comparison.assignmentRevision else {
        throw StudyRecoveryError.changed
      }
      modelContext.insert(ArchivedReviewRecord(archived))
      let remaining = try pendingReviews(accountID: accountID).count - 1
      if let assignment { modelContext.delete(assignment) }
      for cached in try modelContext.fetch(FetchDescriptor<SnapshotRecord>())
      where cached.snapshot.accountID == accountID {
        let old = cached.snapshot
        cached.snapshot = StudySnapshot(
          accountID: old.accountID, username: old.username, currentLevel: old.currentLevel,
          onVacation: old.onVacation,
          assignments: old.assignments.filter { $0.subjectID != subjectID },
          statistics: old.statistics, levels: old.levels, subjects: old.subjects,
          savedAt: old.savedAt, pendingReviews: remaining, requiresAssignmentRefresh: true)
      }
      modelContext.delete(row)
    }
    return archived
  }

  func reviewForRecovery(_ saved: SavedReview) throws -> ReviewRecord {
    guard let row = try reviewRecord(saved), row.saved == saved else {
      throw StudyRecoveryError.changed
    }
    return row
  }

  func recoveryAssignment(_ saved: SavedReview) throws -> AssignmentRecord? {
    let accountID = saved.accountID
    let subjectID = saved.subjectID
    return try modelContext.fetch(
      FetchDescriptor<AssignmentRecord>(
        predicate: #Predicate {
          $0.accountID == accountID && $0.subjectID == subjectID
        })
    ).first
  }
}
