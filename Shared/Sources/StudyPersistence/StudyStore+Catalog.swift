import Foundation
import StudyCore
import SwiftData

extension StudyStore {
  public func catalog(accountID: String) throws -> [CatalogSubject] {
    try modelContext.fetch(
      FetchDescriptor<CatalogRecord>(
        predicate: #Predicate { $0.accountID == accountID },
        sortBy: [SortDescriptor(\.subjectID)])
    ).map(\.subject)
  }

  func catalog(accountID: String, subjectIDs: [Int64]) throws -> [CatalogSubject] {
    guard !subjectIDs.isEmpty else { return [] }
    return try modelContext.fetch(
      FetchDescriptor<CatalogRecord>(
        predicate: #Predicate {
          $0.accountID == accountID && subjectIDs.contains($0.subjectID)
        })
    ).map(\.subject)
  }

  public func assignments(accountID: String) throws -> [CatalogAssignment] {
    try modelContext.fetch(
      FetchDescriptor<AssignmentRecord>(
        predicate: #Predicate { $0.accountID == accountID },
        sortBy: [SortDescriptor(\.subjectID)])
    ).map(\.assignment)
  }

  func assignmentRecord(accountID: String, subjectID: Int64) throws -> AssignmentRecord? {
    try modelContext.fetch(
      FetchDescriptor<AssignmentRecord>(
        predicate: #Predicate {
          $0.accountID == accountID && $0.subjectID == subjectID
        })
    ).first
  }

  public func accountState(accountID: String) throws -> StudyAccountState? {
    try modelContext.fetch(
      FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.accountID == accountID })
    ).first?.state
  }

  /// One actor-bound, read-only projection. Pending answers never masquerade as synced progress.
  public func subjectCatalog(accountID: String) throws -> SubjectCatalogCollection {
    try requireAccount(accountID)
    guard let profile = try accountState(accountID: accountID)?.profile,
      let snapshot = try modelContext.fetch(FetchDescriptor<SnapshotRecord>()).first(where: {
        $0.snapshot.accountID == accountID && !$0.snapshot.isSample
      })?.snapshot
    else { throw StudyStoreError.invalidIdentity }
    let assignments = Dictionary(
      try assignments(accountID: accountID).map { ($0.subjectID, $0) },
      uniquingKeysWith: { first, _ in first })
    let pending = Set(try pendingReviews(accountID: accountID).map(\.subjectID))
    let excluded = Set(
      try materials(accountID: accountID).filter { $0.material.isExcluded }.map {
        $0.material.subjectID
      })
    let items = try catalog(accountID: accountID).filter {
      $0.hiddenAt == nil && $0.level <= profile.maxLevelGranted
    }.map { subject in
      let status: SubjectCatalogItem.Status
      if snapshot.requiresAssignmentRefresh {
        status = .unassigned
      } else if pending.contains(subject.id) {
        status = .pending
      } else if let assignment = assignments[subject.id] {
        if assignment.hidden == true {
          status = .unassigned
        } else if let stage = StudySRSStage(rawValue: assignment.srsStage) {
          status = .studying(
            stage,
            reviewAt: stage == .burned
              ? nil : assignment.availableAt.map { Date(timeIntervalSince1970: Double($0)) },
            guruAt: nil)
        } else {
          status = .lesson
        }
      } else {
        status = .locked
      }
      return SubjectCatalogItem(
        subject: subject, status: status, isExcluded: excluded.contains(subject.id))
    }
    return SubjectCatalogCollection(
      items: items, pendingCount: pending.count,
      requiresAssignmentRefresh: snapshot.requiresAssignmentRefresh)
  }
}
