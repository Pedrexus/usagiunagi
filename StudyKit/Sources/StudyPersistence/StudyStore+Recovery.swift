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
        case .retryUnavailable: "Only a definitively rejected request can be queued again. This item still needs reconciliation."
        }
    }
}

extension StudyStore {
    public func savedWork(accountID: String) throws -> SavedStudyWork {
        try requireAccount(accountID)
        return try SavedStudyWork(reviews: pendingReviews(accountID: accountID),
            materials: materials(accountID: accountID).filter(\.pending),
            subjects: catalog(accountID: accountID).map(\.summary), retryAt: uploadRetryDate(accountID: accountID))
    }

    /// Explicit local choice only: the uploader must still verify identity and current assignment.
    /// Never clear an uncertain attempt merely because a fresh read looks unchanged.
    public func queueRejectedReview(_ saved: SavedReview) throws {
        try requireRecoveryIdle(accountID: saved.accountID)
        try transaction {
            guard let row = try reviewRecord(saved) else { throw StudyRecoveryError.changed }
            guard !row.attempted, row.issue?.reason == .rejected else { throw StudyRecoveryError.retryUnavailable }
            row.issue = nil; row.revision = UUID()
        }
    }

    public func queueRejectedMaterial(_ saved: SavedStudyMaterial) throws {
        try requireRecoveryIdle(accountID: saved.accountID)
        try transaction {
            guard let row = try materialRecords(accountID: saved.accountID).first(where: {
                $0.subjectID == saved.material.subjectID && $0.revision == saved.revision && $0.pending
            }) else { throw StudyRecoveryError.changed }
            guard row.attemptedRevision == nil, row.issue?.reason == .rejected else { throw StudyRecoveryError.retryUnavailable }
            row.issue = nil; row.revision = UUID()
        }
    }

    private func requireRecoveryIdle(accountID: String) throws {
        try requireAccount(accountID)
        guard uploadRun == nil, refreshRun == nil else { throw StudyUploadError.alreadyRunning }
    }
}
