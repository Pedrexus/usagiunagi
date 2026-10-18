import Foundation
import StudyCore

/// One consistent local read for the recovery screen. No credentials or model objects escape.
public struct SavedStudyWork: Sendable {
  public let reviews: [SavedReview]
  public let materials: [SavedStudyMaterial]
  public let subjects: [StudySubject]
  public let retryAt: Date?
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

extension StudyStore {
  /// Read-only comparison. A fresh identity check and local revisions fence every suspension.
  public func compareMaterial(
    _ saved: SavedStudyMaterial, credentialID: String, token: String,
    client: WaniKaniClient = .init()
  ) async throws -> StudyMaterialComparison {
    try Task.checkCancellation()
    try requireRecoveryIdle(accountID: saved.accountID)
    guard !token.isEmpty else { throw StudyStoreError.invalidIdentity }
    let id = UUID()
    let generation = uploadGeneration
    try checkMaterialRecovery(saved, credentialID: credentialID, generation: generation)
    let task = Task {
      do {
        if let retryAt = try uploadRetryDate(accountID: saved.accountID), retryAt > Date() {
          throw WaniKaniClient.APIError.rateLimited(retryAt: retryAt)
        }
        let account = try await client.account(token: token)
        try checkMaterialRecovery(saved, credentialID: credentialID, generation: generation)
        guard account.id == saved.accountID else { throw StudyUploadError.accountMismatch }
        let remote = try await client.material(subjectID: saved.material.subjectID, token: token)
        try checkMaterialRecovery(saved, credentialID: credentialID, generation: generation)
        return StudyMaterialComparison(
          id: id, saved: saved, remote: remote, checkedAt: Date(), generation: generation)
      } catch {
        try checkRecoveryAccount(
          saved.accountID, credentialID: credentialID, generation: generation)
        try recordRateLimit(error, accountID: saved.accountID)
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

  private func checkMaterialRecovery(
    _ saved: SavedStudyMaterial, credentialID: String, generation: UUID
  ) throws {
    try checkRecoveryAccount(saved.accountID, credentialID: credentialID, generation: generation)
    _ = try materialForRecovery(saved)
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
      subjects: catalog(accountID: accountID).map(\.summary),
      retryAt: uploadRetryDate(accountID: accountID))
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

  private func requireRecoveryIdle(accountID: String) throws {
    try requireAccount(accountID)
    guard synchronizationCancellations == 0, synchronizationRun == nil, uploadRun == nil,
      refreshRun == nil, recoveryRun == nil
    else { throw StudyUploadError.alreadyRunning }
  }
}
