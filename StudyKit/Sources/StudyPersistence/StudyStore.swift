import CryptoKit
import Foundation
import StudyCore
import SwiftData

@Model final class SnapshotRecord {
    @Attribute(.unique) var credentialID: String
    @Attribute(.codable) var snapshot: StudySnapshot
    init(_ snapshot: StudySnapshot, credentialID: String) {
        self.snapshot = snapshot; self.credentialID = credentialID
    }
}

@Model final class SessionRecord {
    @Attribute(.unique) var accountID: String
    var revision: UUID
    @Attribute(.codable) var session: StudySession
    init(accountID: String, session: StudySession, revision: UUID) {
        self.accountID = accountID; self.session = session; self.revision = revision
    }
}

@Model final class ReviewRecord {
    #Unique<ReviewRecord>([\.accountID, \.subjectID])
    var accountID: String
    var subjectID: Int64
    var revision: UUID
    var attempted: Bool
    @Attribute(.codable) var submission: StudyReviewSubmission
    @Attribute(.codable) var originalItem: StudySessionItem
    @Attribute(.codable) var originalAssignment: CatalogAssignment? = nil
    @Attribute(.codable) var issue: StudyUploadIssue? = nil
    init(accountID: String, submission: StudyReviewSubmission, originalItem: StudySessionItem) {
        self.accountID = accountID; self.subjectID = submission.subjectID; self.submission = submission
        self.originalItem = originalItem; self.revision = UUID(); attempted = false
    }
}

@Model final class ImportReceipt {
    @Attribute(.unique) var sourceID: String
    var digest: String
    init(sourceID: String, digest: String) { self.sourceID = sourceID; self.digest = digest }
}

public struct SavedStudySession: Sendable {
    public let revision: UUID
    public let session: StudySession
}

public struct SavedReview: Sendable {
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
    case invalidIdentity, sampleData, staleSession, pendingReview(Int64), invalidSession, alreadyAttempted, staleMaterial, invalidMaterial
    public var errorDescription: String? {
        switch self {
        case .invalidIdentity: "Reconnect to WaniKani to verify this account before saving study progress."
        case .sampleData: "Sample data cannot replace saved account data."
        case .staleSession: "This study session changed in another window. Reopen the current session."
        case .pendingReview(let id): "Subject \(id) already has a saved review awaiting upload."
        case .invalidSession: "The session could not be saved because its completed answers are inconsistent."
        case .staleMaterial: "These notes changed in another window. Reload them before saving."
        case .invalidMaterial: "The study material could not be saved because its subject identity is invalid."
        case .alreadyAttempted: "This review was already sent. Check WaniKani before retrying."
        }
    }
}

/// One actor/container per local store. Model values never escape its executor.
/// CloudKit is deliberately disabled: WaniKani owns cross-device study progress.
@ModelActor public actor StudyStore {
    var uploadGeneration = UUID()
    var uploadRun: (id: UUID, task: Task<StudyUploadReport, Error>)?
    @concurrent public static func open(at url: URL, inMemory: Bool = false) async throws -> StudyStore {
        let schema = Schema([SnapshotRecord.self, SessionRecord.self, ReviewRecord.self, MaterialRecord.self, ImportReceipt.self, CatalogRecord.self, AssignmentRecord.self, AccountRecord.self, UploadPauseRecord.self])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        return StudyStore(modelContainer: try ModelContainer(for: schema, configurations: configuration))
    }

    func transaction(_ body: () throws -> Void) throws {
        modelContext.autosaveEnabled = false
        do { try modelContext.transaction(block: body) }
        catch { modelContext.rollback(); throw error }
    }

    public func snapshot(credentialID: String) throws -> StudySnapshot? {
        try modelContext.fetch(FetchDescriptor<SnapshotRecord>(predicate:
            #Predicate { $0.credentialID == credentialID })).first?.snapshot
    }

    public func saveSnapshot(_ snapshot: StudySnapshot, credentialID: String) throws {
        guard !snapshot.isSample else { throw StudyStoreError.sampleData }
        guard !credentialID.isEmpty, let id = snapshot.accountID, !id.isEmpty else { throw StudyStoreError.invalidIdentity }
        try transaction {
            let existing = try modelContext.fetch(FetchDescriptor<SnapshotRecord>(predicate:
                #Predicate { $0.credentialID == credentialID })).first
            if let previous = existing?.snapshot.accountID, previous != id { throw StudyStoreError.invalidIdentity }
            if let existing { existing.snapshot = snapshot }
            else { modelContext.insert(SnapshotRecord(snapshot, credentialID: credentialID)) }
        }
    }

    public func removeSnapshot(credentialID: String) throws {
        try transaction {
            for row in try modelContext.fetch(FetchDescriptor<SnapshotRecord>(predicate:
                #Predicate { $0.credentialID == credentialID })) { modelContext.delete(row) }
        }
    }

    /// One-time import of the former Mac JSON cache. Original file is retained for rollback.
    /// A receipt prevents an explicitly removed snapshot from returning on the next launch.
    @discardableResult public func importLegacySnapshot(at url: URL, credentialID: String) throws -> Bool {
        let sourceID = url.standardizedFileURL.path + ":" + credentialID
        guard try modelContext.fetchCount(FetchDescriptor<ImportReceipt>(predicate:
            #Predicate { $0.sourceID == sourceID })) == 0 else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        struct Legacy: Decodable { let snapshot: StudySnapshot; let credentialID: String? }
        let data = try Data(contentsOf: url)
        let legacy = try JSONDecoder().decode(Legacy.self, from: data)
        guard !credentialID.isEmpty, legacy.credentialID == credentialID else { return false }
        guard !legacy.snapshot.isSample else { throw StudyStoreError.sampleData }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try transaction {
            if try snapshot(credentialID: credentialID) == nil {
                modelContext.insert(SnapshotRecord(legacy.snapshot, credentialID: credentialID))
            }
            modelContext.insert(ImportReceipt(sourceID: sourceID, digest: digest))
        }
        return true
    }

    func requireAccount(_ accountID: String) throws {
        guard !accountID.isEmpty else { throw StudyStoreError.invalidIdentity }
        // Legacy snapshots remain readable offline, but cannot authorize new study writes.
        guard try modelContext.fetch(FetchDescriptor<SnapshotRecord>()).contains(where: {
            $0.snapshot.accountID == accountID && !$0.snapshot.isSample
        }) else { throw StudyStoreError.invalidIdentity }
    }

    private func sessionRecord(_ accountID: String) throws -> SessionRecord? {
        try modelContext.fetch(FetchDescriptor<SessionRecord>(predicate:
            #Predicate { $0.accountID == accountID })).first
    }

    public func session(accountID: String) throws -> SavedStudySession? {
        try sessionRecord(accountID).map { SavedStudySession(revision: $0.revision, session: $0.session) }
    }

    /// Saves the session and only its newly completed answers in the same native transaction.
    /// A revision prevents an older scene from replacing newer progress or resubmitting an answer.
    @discardableResult public func saveSession(_ session: StudySession, accountID: String,
                                              expectedRevision: UUID?) throws -> UUID {
        try requireAccount(accountID)
        let revision = UUID()
        try transaction {
            let old = try sessionRecord(accountID)
            guard old?.revision == expectedRevision else { throw StudyStoreError.staleSession }
            let previous = Set(old?.session.completedIDs ?? [])
            guard previous.isSubset(of: Set(session.completedIDs)) else { throw StudyStoreError.invalidSession }
            if let old {
                guard old.session.isPractice == session.isPractice,
                      old.session.items.count == session.items.count,
                      old.session.items.allSatisfy({ id, item in
                          session.items[id]?.subjectID == item.subjectID && session.items[id]?.assignmentID == item.assignmentID
                      }) else { throw StudyStoreError.invalidSession }
            }
            for submission in session.completedSubmissions where !previous.contains(submission.itemID) {
                let subjectID = submission.subjectID
                guard subjectID > 0, submission.assignmentID > 0,
                      let item = session.items[submission.itemID] else { throw StudyStoreError.invalidSession }
                guard try modelContext.fetchCount(FetchDescriptor<ReviewRecord>(predicate:
                    #Predicate { $0.accountID == accountID && $0.subjectID == subjectID })) == 0 else {
                    throw StudyStoreError.pendingReview(subjectID)
                }
                modelContext.insert(ReviewRecord(accountID: accountID, submission: submission, originalItem: item))
            }
            if let old { old.session = session; old.revision = revision }
            else { modelContext.insert(SessionRecord(accountID: accountID, session: session, revision: revision)) }
        }
        return revision
    }

    public func removeSession(accountID: String, expectedRevision: UUID) throws {
        try transaction {
            guard let row = try sessionRecord(accountID), row.revision == expectedRevision else { throw StudyStoreError.staleSession }
            modelContext.delete(row) // Queued answers remain durable independently of the finished session.
        }
    }

    public func pendingReviews(accountID: String) throws -> [SavedReview] {
        try modelContext.fetch(FetchDescriptor<ReviewRecord>(predicate: #Predicate { $0.accountID == accountID })).map {
            SavedReview(accountID: $0.accountID, subjectID: $0.subjectID, revision: $0.revision,
                        submission: $0.submission, originalItem: $0.originalItem, originalAssignment: $0.originalAssignment, attempted: $0.attempted, issue: $0.issue)
        }.sorted { $0.subjectID < $1.subjectID }
    }

    /// Commit before the network write. No automatic reset of attempted records on process launch.
    public func beginReviewAttempt(_ review: SavedReview) throws {
        try transaction {
            guard let row = try reviewRecord(review), !row.attempted else { throw StudyStoreError.alreadyAttempted }
            row.attempted = true
        }
    }

    /// Call only after a validated successful response for this exact attempt.
    public func acknowledgeReview(_ review: SavedReview) throws {
        try transaction {
            if let row = try reviewRecord(review), row.attempted { modelContext.delete(row) }
        }
    }

    func reviewRecord(_ review: SavedReview) throws -> ReviewRecord? {
        let accountID = review.accountID, subjectID = review.subjectID, revision = review.revision
        return try modelContext.fetch(FetchDescriptor<ReviewRecord>(predicate:
            #Predicate { $0.accountID == accountID && $0.subjectID == subjectID && $0.revision == revision })).first
    }
}
