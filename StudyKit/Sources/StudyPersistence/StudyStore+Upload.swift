import Foundation
import StudyCore
import SwiftData

public struct StudyUploadIssue: Codable, Sendable {
    public enum Reason: String, Codable, Sendable { case uncertain, rejected, assignmentChanged, assignmentMissing, materialChanged }
    public let reason: Reason
    public let httpStatus: Int?
    public let serverAssignment: CatalogAssignment?
    public let detectedAt: Date
}

public struct StudyUploadReport: Sendable {
    public var uploadedReviews = 0
    public var uploadedLessons = 0
    public var uploadedMaterials = 0
    public var reviewsNeedingAttention = 0
    public var materialsNeedingAttention = 0
    public var onVacation = false
}

public enum StudyUploadError: Error, LocalizedError {
    case alreadyRunning, accountMismatch
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: "Synchronization is already running."
        case .accountMismatch: "This token belongs to a different WaniKani account. Saved work has not been sent."
        }
    }
}

@Model final class UploadPauseRecord {
    @Attribute(.unique) var accountID: String
    var retryAt: Date
    init(accountID: String, retryAt: Date) { self.accountID = accountID; self.retryAt = retryAt }
}

extension StudyStore {
    /// One native upload lane per store. Account transitions must await cancelSynchronization before
    /// changing credentials or clearing data. No token is persisted in SwiftData.
    public func uploadPending(accountID: String, token: String, client: WaniKaniClient = .init()) async throws -> StudyUploadReport {
        guard synchronizationCancellations == 0, uploadRun == nil, recoveryRun == nil else { throw StudyUploadError.alreadyRunning }
        let id = UUID(), generation = uploadGeneration
        let task = Task { try await self.performUpload(accountID: accountID, token: token, client: client, generation: generation) }
        uploadRun = (id, task)
        defer { if uploadRun?.id == id { uploadRun = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    public func uploadRetryDate(accountID: String) throws -> Date? {
        try modelContext.fetch(FetchDescriptor<UploadPauseRecord>(predicate: #Predicate { $0.accountID == accountID })).first?.retryAt
    }

    private func checkUpload(_ generation: UUID, accountID: String) throws {
        try Task.checkCancellation()
        guard uploadGeneration == generation else { throw CancellationError() }
        try requireAccount(accountID)
    }

    private func performUpload(accountID: String, token: String, client: WaniKaniClient, generation: UUID) async throws -> StudyUploadReport {
        try checkUpload(generation, accountID: accountID)
        if let retryAt = try uploadRetryDate(accountID: accountID), retryAt > Date() {
            throw WaniKaniClient.APIError.rateLimited(retryAt: retryAt)
        }
        var report = StudyUploadReport()
        do {
            let identity = try await client.account(token: token)
            try checkUpload(generation, accountID: accountID)
            guard identity.id == accountID else { throw StudyUploadError.accountMismatch }
            report.onVacation = identity.onVacation
            if !identity.onVacation {
                for key in try pendingReviews(accountID: accountID) {
                    try checkUpload(generation, accountID: accountID)
                    guard let review = try pendingReviews(accountID: accountID).first(where: { $0.subjectID == key.subjectID }) else { continue }
                    // Reads may retry; no attempt is committed until the assignment is checked.
                    let remote = try await client.assignment(subjectID: review.subjectID, token: token)
                    try checkUpload(generation, accountID: accountID)
                    if review.attempted || review.issue != nil || !canSubmit(review, against: remote) {
                        let reason = review.issue?.reason ?? (review.attempted ? .uncertain : remote == nil ? .assignmentMissing : .assignmentChanged)
                        try setIssue(review, reason: reason, status: review.issue?.httpStatus, remote: remote)
                        report.reviewsNeedingAttention += 1
                        continue
                    }
                    try beginReviewAttempt(review)
                    let assignment: CatalogAssignment
                    do { assignment = try await client.submit(review.submission, token: token) }
                    catch {
                        try checkUpload(generation, accountID: accountID)
                        try recordFailure(error, review: review, remote: remote)
                        if shouldStop(error) { throw error }
                        report.reviewsNeedingAttention += 1
                        continue
                    }
                    try checkUpload(generation, accountID: accountID)
                    // The updated assignment and acknowledgement are one durable transaction.
                    try transaction {
                        guard let row = try reviewRecord(review), row.attempted else { return }
                        let subjectID = assignment.subjectID
                        var assignment = assignment
                        let subject = try modelContext.fetch(FetchDescriptor<CatalogRecord>(predicate:
                            #Predicate { $0.accountID == accountID && $0.subjectID == subjectID })).first
                        assignment.level = subject?.level ?? review.originalAssignment?.level ?? 0
                        if let current = try modelContext.fetch(FetchDescriptor<AssignmentRecord>(predicate:
                            #Predicate { $0.accountID == accountID && $0.subjectID == subjectID })).first {
                            if assignment.level == 0 { assignment.level = current.assignment.level }
                            current.assignment = assignment; current.revision = UUID()
                        } else { modelContext.insert(AssignmentRecord(accountID: accountID, assignment: assignment)) }
                        modelContext.delete(row)
                        if review.submission.isLesson { report.uploadedLessons += 1 }
                        else { report.uploadedReviews += 1 }
                    }
                }
            }
            for key in try materials(accountID: accountID).filter(\.pending) {
                try checkUpload(generation, accountID: accountID)
                guard let material = try materials(accountID: accountID).first(where: {
                    $0.material.subjectID == key.material.subjectID && $0.pending
                }) else { continue }
                if material.issue != nil || material.attemptedRevision != nil { report.materialsNeedingAttention += 1; continue }
                let remote = try await client.material(subjectID: material.material.subjectID, token: token)
                try checkUpload(generation, accountID: accountID)
                // An edit made during lookup wins before a request body is put on the wire.
                guard let current = try materialRecords(accountID: accountID).first(where: {
                    $0.subjectID == material.material.subjectID && $0.revision == material.revision && $0.pending
                }) else { continue }
                if let baseline = current.recoveryBaseline, baseline.remote != remote {
                    try transaction {
                        current.issue = .init(reason: .materialChanged, httpStatus: nil, serverAssignment: nil, detectedAt: Date())
                        current.revision = UUID()
                    }
                    report.materialsNeedingAttention += 1
                    continue
                }
                try transaction {
                    current.attemptedRevision = material.revision; current.attemptedMaterial = material.material
                }
                let result: WaniKaniMaterial
                do { result = try await client.writeMaterial(material.material, serverID: remote?.id, token: token) }
                catch {
                    try checkUpload(generation, accountID: accountID)
                    try transaction {
                        if let row = try materialRecords(accountID: accountID).first(where: {
                            $0.subjectID == material.material.subjectID && $0.attemptedRevision == material.revision
                        }) {
                            let failure = issue(for: error, remote: nil)
                            let definitelyRejected: Bool
                            switch error {
                            case WaniKaniClient.APIError.unauthorized, WaniKaniClient.APIError.rateLimited: definitelyRejected = true
                            default: definitelyRejected = failure.reason == .rejected
                            }
                            if definitelyRejected {
                                row.attemptedRevision = nil; row.attemptedMaterial = nil
                                if row.revision == material.revision, failure.reason == .rejected { row.issue = failure }
                            } else { row.issue = failure }
                        }
                    }
                    if shouldStop(error) { throw error }
                    report.materialsNeedingAttention += 1
                    continue
                }
                try checkUpload(generation, accountID: accountID)
                try transaction {
                    if let row = try materialRecords(accountID: accountID).first(where: {
                        $0.subjectID == material.material.subjectID && $0.attemptedRevision == material.revision
                    }) {
                        row.attemptedRevision = nil; row.attemptedMaterial = nil; row.serverID = result.id
                        // A newer local edit must compare against our confirmed write next time.
                        row.recoveryBaseline = row.revision == material.revision ? nil : row.recoveryBaseline.map { _ in .init(remote: result) }
                        if row.revision == material.revision { row.pending = false; row.revision = UUID(); row.issue = nil; report.uploadedMaterials += 1 }
                    }
                }
            }
            return report
        } catch {
            try checkUpload(generation, accountID: accountID)
            try recordRateLimit(error, accountID: accountID)
            throw error
        }
    }

    func recordRateLimit(_ error: any Error, accountID: String) throws {
        if case WaniKaniClient.APIError.rateLimited(let retryAt) = error {
            try transaction {
                if let row = try modelContext.fetch(FetchDescriptor<UploadPauseRecord>(predicate:
                    #Predicate { $0.accountID == accountID })).first { row.retryAt = max(row.retryAt, retryAt) }
                else { modelContext.insert(UploadPauseRecord(accountID: accountID, retryAt: retryAt)) }
            }
        }
    }

    private func canSubmit(_ review: SavedReview, against remote: CatalogAssignment?) -> Bool {
        guard let remote, remote.id == review.submission.assignmentID, remote.hidden != true,
              remote.srsStage == review.originalItem.srsStage else { return false }
        if review.submission.isLesson { return remote.startedAt == nil && remote.unlockedAt != nil && remote.srsStage == 0 }
        return remote.startedAt != nil && remote.availableAt == review.originalItem.availableAt &&
            (remote.availableAt ?? Int64.max) <= Int64(Date().timeIntervalSince1970)
    }

    private func setIssue(_ review: SavedReview, reason: StudyUploadIssue.Reason, status: Int?, remote: CatalogAssignment?) throws {
        try transaction {
            if let row = try reviewRecord(review) {
                row.issue = .init(reason: reason, httpStatus: status, serverAssignment: remote, detectedAt: Date())
            }
        }
    }

    private func recordFailure(_ error: any Error, review: SavedReview, remote: CatalogAssignment?) throws {
        try transaction {
            guard let row = try reviewRecord(review) else { return }
            if case WaniKaniClient.APIError.unauthorized = error { row.attempted = false; return }
            if case WaniKaniClient.APIError.rateLimited = error { row.attempted = false; return }
            row.issue = issue(for: error, remote: remote)
            if row.issue?.reason == .rejected { row.attempted = false }
        }
    }

    private func issue(for error: any Error, remote: CatalogAssignment?) -> StudyUploadIssue {
        var reason = StudyUploadIssue.Reason.uncertain, status: Int?
        if case WaniKaniClient.APIError.request(let code) = error {
            status = code
            // A timeout response (for example 408) is not proof that an upstream write failed.
            if [400, 404, 405, 409, 413, 415, 422].contains(code) { reason = .rejected }
        } else if case WaniKaniClient.APIError.invalidPayload = error { reason = .rejected }
        return .init(reason: reason, httpStatus: status, serverAssignment: remote, detectedAt: Date())
    }

    private func shouldStop(_ error: any Error) -> Bool {
        // Rejected/ambiguous individual responses need attention but must not starve other work.
        // Authentication, throttling, connectivity and cancellation stop the whole pass.
        if case WaniKaniClient.APIError.request(let code) = error { return code >= 500 || code == 408 }
        if case WaniKaniClient.APIError.invalidResponse = error { return false }
        if case WaniKaniClient.APIError.invalidPayload = error { return false }
        return true
    }
}
