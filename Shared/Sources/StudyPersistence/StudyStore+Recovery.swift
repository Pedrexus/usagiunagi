import Foundation
import StudyCore
import SwiftData

/// One consistent local read for the recovery screen. No credentials or model objects escape.
public struct SavedStudyWork: Sendable {
  public let reviews: [SavedReview]
  public let materials: [SavedStudyMaterial]
  public let archivedReviews: [ArchivedStudyReview]
  public let subjects: [StudySubject]
  public let retryAt: Date?
  public let requiresAssignmentRefresh: Bool
  public var isEmpty: Bool { reviews.isEmpty && materials.isEmpty }
}

public enum StudyRecoveryError: Error, LocalizedError {
  case changed, retryUnavailable
  public var errorDescription: String? {
    switch self {
    case .changed: "This saved work changed. Reload it before choosing an action."
    case .retryUnavailable:
      "Only a definitively rejected request can be queued again. This item still needs reconciliation."
    }
  }
}

public struct StudyMaterialComparison: Identifiable, Sendable {
  public let id: UUID
  public let saved: SavedStudyMaterial
  public let remote: WaniKaniMaterial?
  public let checkedAt: Date
  fileprivate let generation: UUID
}

public enum StudyMaterialResolution: Equatable, Sendable { case keepLocal, useServer }

public enum StudyRecoveryRequest: Sendable {
  case material(SavedStudyMaterial)
  case review(SavedReview)
  public var accountID: String {
    switch self {
    case .material(let saved): saved.accountID
    case .review(let saved): saved.accountID
    }
  }
}

public enum StudyRecoveryComparison: Identifiable, Sendable {
  case material(StudyMaterialComparison)
  case review(StudyReviewComparison)
  public var id: UUID {
    switch self {
    case .material(let value): value.id
    case .review(let value): value.id
    }
  }
}

extension StudyStore {
  /// Read-only comparison. A fresh identity check and local revisions fence every suspension.
  public func compareSavedWork(
    _ request: StudyRecoveryRequest, credentialID: String, token: String,
    client: any WaniKaniService = WaniKaniClient()
  ) async throws -> StudyRecoveryComparison {
    try Task.checkCancellation()
    try requireRecoveryIdle(accountID: request.accountID)
    guard !token.isEmpty else { throw StudyStoreError.invalidIdentity }
    let id = UUID()
    let generation = uploadGeneration
    try checkRecoveryRequest(request, credentialID: credentialID, generation: generation)
    let assignmentRevision: UUID?
    if case .review(let saved) = request {
      assignmentRevision = try recoveryAssignment(saved)?.revision
    } else {
      assignmentRevision = nil
    }
    let task = Task {
      do {
        if let retryAt = try uploadRetryDate(accountID: request.accountID), retryAt > Date() {
          throw WaniKaniClient.APIError.rateLimited(retryAt: retryAt)
        }
        let account = try await client.account(token: token)
        try checkRecoveryRequest(request, credentialID: credentialID, generation: generation)
        guard account.id == request.accountID else { throw StudyUploadError.accountMismatch }
        switch request {
        case .material(let saved):
          let remote = try await client.material(subjectID: saved.material.subjectID, token: token)
          try checkRecoveryRequest(request, credentialID: credentialID, generation: generation)
          return StudyRecoveryComparison.material(
            .init(
              id: id, saved: saved, remote: remote, checkedAt: Date(), generation: generation))
        case .review(let saved):
          let remote = try await client.assignment(subjectID: saved.subjectID, token: token)
          try checkRecoveryRequest(request, credentialID: credentialID, generation: generation)
          guard try recoveryAssignment(saved)?.revision == assignmentRevision else {
            throw StudyRecoveryError.changed
          }
          return StudyRecoveryComparison.review(
            .init(
              id: id, saved: saved, remote: remote,
              checkedAt: Date(), generation: generation, credentialID: credentialID,
              assignmentRevision: assignmentRevision))
        }
      } catch {
        try checkRecoveryAccount(
          request.accountID, credentialID: credentialID, generation: generation)
        try recordRateLimit(error, accountID: request.accountID)
        throw error
      }
    }
    recoveryRun = (id, task)
    defer { if recoveryRun?.id == id { recoveryRun = nil } }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  /// Explicit local choice only. Keeping an edit records a durable server precondition;
  /// the ordinary uploader must check it again before making any write.
  public func resolveMaterial(
    _ comparison: StudyMaterialComparison, choice: StudyMaterialResolution
  ) throws {
    try requireRecoveryIdle(accountID: comparison.saved.accountID)
    guard comparison.generation == uploadGeneration else { throw StudyRecoveryError.changed }
    try transaction {
      let row = try materialForRecovery(comparison.saved)
      switch choice {
      case .keepLocal:
        row.recoveryBaseline = .init(remote: comparison.remote)
      case .useServer:
        row.material = comparison.remote?.value ?? StudyMaterial(subjectID: row.subjectID)
        row.pending = false
        row.recoveryBaseline = nil
      }
      row.serverID = comparison.remote?.id
      row.attemptedRevision = nil
      row.attemptedMaterial = nil
      row.issue = nil
      row.revision = UUID()
    }
  }

  private func checkRecoveryRequest(
    _ request: StudyRecoveryRequest, credentialID: String, generation: UUID
  ) throws {
    try checkRecoveryAccount(request.accountID, credentialID: credentialID, generation: generation)
    switch request {
    case .material(let saved): _ = try materialForRecovery(saved)
    case .review(let saved): _ = try reviewForRecovery(saved)
    }
  }

  private func checkRecoveryAccount(
    _ accountID: String, credentialID: String, generation: UUID
  ) throws {
    try Task.checkCancellation()
    guard uploadGeneration == generation else { throw CancellationError() }
    try requireAccount(accountID)
    guard try snapshot(credentialID: credentialID)?.accountID == accountID else {
      throw StudyUploadError.accountMismatch
    }
  }

  private func materialForRecovery(_ saved: SavedStudyMaterial) throws -> MaterialRecord {
    guard
      let row = try materialRecords(accountID: saved.accountID).first(where: {
        $0.subjectID == saved.material.subjectID && $0.revision == saved.revision && $0.pending
      }), row.material == saved.material, row.serverID == saved.serverID,
      row.attemptedRevision == saved.attemptedRevision,
      row.attemptedMaterial == saved.attemptedMaterial,
      row.issue?.reason == saved.issue?.reason, row.issue?.detectedAt == saved.issue?.detectedAt
    else {
      throw StudyRecoveryError.changed
    }
    return row
  }

  public func savedWork(accountID: String) throws -> SavedStudyWork {
    try requireAccount(accountID)
    return try SavedStudyWork(
      reviews: pendingReviews(accountID: accountID),
      materials: materials(accountID: accountID).filter(\.pending),
      archivedReviews: archivedReviews(accountID: accountID),
      subjects: catalog(accountID: accountID).map(\.summary),
      retryAt: uploadRetryDate(accountID: accountID),
      requiresAssignmentRefresh: modelContext.fetch(FetchDescriptor<SnapshotRecord>()).contains {
        $0.snapshot.accountID == accountID && $0.snapshot.requiresAssignmentRefresh
      })
  }

  /// Explicit local choice only: the uploader must still verify identity and current assignment.
  /// Never clear an uncertain attempt merely because a fresh read looks unchanged.
  public func queueRejectedReview(_ saved: SavedReview) throws {
    try requireRecoveryIdle(accountID: saved.accountID)
    try transaction {
      guard let row = try reviewRecord(saved) else { throw StudyRecoveryError.changed }
      guard !row.attempted, row.issue?.reason == .rejected else {
        throw StudyRecoveryError.retryUnavailable
      }
      row.issue = nil
      row.revision = UUID()
    }
  }

  public func queueRejectedMaterial(_ saved: SavedStudyMaterial) throws {
    try requireRecoveryIdle(accountID: saved.accountID)
    try transaction {
      guard
        let row = try materialRecords(accountID: saved.accountID).first(where: {
          $0.subjectID == saved.material.subjectID && $0.revision == saved.revision && $0.pending
        })
      else { throw StudyRecoveryError.changed }
      guard row.attemptedRevision == nil, row.issue?.reason == .rejected else {
        throw StudyRecoveryError.retryUnavailable
      }
      row.issue = nil
      row.revision = UUID()
    }
  }

  func requireRecoveryIdle(accountID: String) throws {
    try requireAccount(accountID)
    guard synchronizationCancellations == 0, synchronizationRun == nil, uploadRun == nil,
      refreshRun == nil, recoveryRun == nil
    else { throw StudyUploadError.alreadyRunning }
  }
}
