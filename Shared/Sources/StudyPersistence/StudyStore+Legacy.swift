import CryptoKit
import Foundation
import StudyCore
import SwiftData

@Model final class CatalogRecord {
    #Unique<CatalogRecord>([\.accountID, \.subjectID])
    var accountID: String
    var subjectID: Int64
    var level: Int
    var japanese: String
    @Attribute(.codable) var subject: CatalogSubject
    init(accountID: String, subject: CatalogSubject) {
        self.accountID = accountID; subjectID = subject.id; level = subject.level
        japanese = subject.japanese; self.subject = subject
    }
}

@Model final class AssignmentRecord {
    var revision: UUID = UUID()
    #Unique<AssignmentRecord>([\.accountID, \.subjectID])
    var accountID: String
    var subjectID: Int64
    @Attribute(.codable) var assignment: CatalogAssignment
    init(accountID: String, assignment: CatalogAssignment) {
        self.accountID = accountID; subjectID = assignment.subjectID; self.assignment = assignment
    }
}

@Model final class AccountRecord {
    @Attribute(.unique) var accountID: String
    @Attribute(.codable) var state: StudyAccountState
    init(accountID: String, state: StudyAccountState) { self.accountID = accountID; self.state = state }
}

public enum LegacyImportError: Error, LocalizedError {
    case unsupportedSchema(Int), invalidData(String), accountMismatch, destinationNotEmpty, sourceChanged
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): "The saved database version (\(version)) needs a different importer. Your original data has been kept."
        case .invalidData(let detail): "The saved data could not be imported: \(detail). Your original data has been kept."
        case .accountMismatch: "The saved account does not match the verified WaniKani account. No data was imported."
        case .destinationNotEmpty: "This account already has native study data. Import cannot overwrite it."
        case .sourceChanged: "The old database changed after its import. Stop migration and keep the original data for recovery."
        }
    }
}

public struct LegacyImportResult: Sendable {
    public let alreadyImported: Bool
    public let subjects: Int
    public let assignments: Int
    public let pendingReviews: Int
    public let pendingMaterials: Int
}

extension StudyStore {
    public func catalog(accountID: String) throws -> [CatalogSubject] {
        try modelContext.fetch(FetchDescriptor<CatalogRecord>(predicate: #Predicate { $0.accountID == accountID },
            sortBy: [SortDescriptor(\.subjectID)])).map(\.subject)
    }
    public func assignments(accountID: String) throws -> [CatalogAssignment] {
        try modelContext.fetch(FetchDescriptor<AssignmentRecord>(predicate: #Predicate { $0.accountID == accountID },
            sortBy: [SortDescriptor(\.subjectID)])).map(\.assignment)
    }
    public func accountState(accountID: String) throws -> StudyAccountState? {
        try modelContext.fetch(FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.accountID == accountID })).first?.state
    }

    /// The caller must quiesce the old writer and verify its token against WaniKani before cutover.
    /// Everything commits together, including a receipt. Retrying never recreates consumed uploads.
    @discardableResult public func importLegacyAccount(_ source: LegacyStudyExport, sourceID: String,
        verifiedAccountID accountID: String, verifiedUsername: String, credentialID: String) throws -> LegacyImportResult {
        guard (9...15).contains(source.schemaVersion) else { throw LegacyImportError.unsupportedSchema(source.schemaVersion) }
        guard !accountID.isEmpty, !credentialID.isEmpty, !sourceID.isEmpty,
              !verifiedUsername.isEmpty, source.profile.username == verifiedUsername else { throw LegacyImportError.accountMismatch }
        func unique(_ ids: [Int64], _ label: String) throws {
            guard ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else { throw LegacyImportError.invalidData(label) }
        }
        try unique(source.subjects.map(\.id), "subject identifiers")
        try unique(source.assignments.map(\.subjectID), "assignment subjects")
        try unique(source.assignments.map(\.id), "assignment identifiers")
        try unique(source.pendingReviews.map { $0.assignment.subjectID }, "pending review subjects")
        try unique(source.materials.map { $0.value.subjectID }, "study material subjects")
        try unique(source.progress.map(\.subjectID), "progress subjects")
        try unique(source.statistics.map(\.id), "statistics identifiers")
        try unique(source.levels.map(\.id), "level progression identifiers")
        try unique(source.voices.map(\.id), "voice actor identifiers")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(source)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let receiptID = "ios:" + accountID + ":" + sourceID
        var alreadyImported = false
        try transaction {
            if let receipt = try modelContext.fetch(FetchDescriptor<ImportReceipt>(predicate:
                #Predicate { $0.sourceID == receiptID })).first {
                guard receipt.digest == digest else { throw LegacyImportError.sourceChanged }
                alreadyImported = true; return
            }
            guard try accountState(accountID: accountID) == nil,
                  try catalog(accountID: accountID).isEmpty, try assignments(accountID: accountID).isEmpty,
                  try pendingReviews(accountID: accountID).isEmpty, try materials(accountID: accountID).isEmpty,
                  try session(accountID: accountID) == nil else { throw LegacyImportError.destinationNotEmpty }
            let cached = try modelContext.fetch(FetchDescriptor<SnapshotRecord>(predicate:
                #Predicate { $0.credentialID == credentialID })).first
            if let existing = cached?.snapshot {
                guard !existing.isSample,
                      existing.accountID.map({ $0 == accountID }) ?? (existing.username == verifiedUsername) else {
                    throw LegacyImportError.accountMismatch
                }
            }
            for subject in source.subjects { modelContext.insert(CatalogRecord(accountID: accountID, subject: subject)) }
            let pendingIDs = Set(source.pendingReviews.map { $0.assignment.subjectID })
            for assignment in source.assignments where !pendingIDs.contains(assignment.subjectID) {
                modelContext.insert(AssignmentRecord(accountID: accountID, assignment: assignment))
            }
            for entry in source.pendingReviews {
                let answer = entry.submission, assignment = entry.assignment
                guard assignment.id > 0, answer.subjectID == assignment.subjectID, answer.assignmentID == assignment.id,
                      answer.meaningWrongCount >= 0, answer.readingWrongCount >= 0 else {
                    throw LegacyImportError.invalidData("pending review payload")
                }
                let row = ReviewRecord(accountID: accountID, submission: answer,
                    originalItem: assignment.sessionItem(id: answer.itemID, isLesson: answer.isLesson))
                row.originalAssignment = assignment
                // The old queue does not record whether a timed-out request reached WaniKani.
                // Import it conservatively; reconciliation must explicitly release it for upload.
                row.attempted = true
                modelContext.insert(row)
            }
            for entry in source.materials {
                let row = MaterialRecord(accountID: accountID, material: entry.value, pending: entry.pending)
                row.serverID = entry.serverID > 0 ? entry.serverID : nil
                // The legacy queue also lacks a record of which note revision reached the server.
                if entry.pending { row.issue = .init(reason: .uncertain, httpStatus: nil, serverAssignment: nil, detectedAt: Date()) }
                modelContext.insert(row)
            }
            modelContext.insert(AccountRecord(accountID: accountID, state: StudyAccountState(legacy: source)))
            if cached?.snapshot.accountID == nil {
                let snapshot = StudySnapshot(accountID: accountID, username: source.profile.username,
                    currentLevel: source.profile.level, onVacation: source.profile.vacationStartedAt != nil,
                    assignments: source.assignments.filter { !pendingIDs.contains($0.subjectID) }.map(\.summary),
                    statistics: source.statistics.map(\.answers), levels: source.levels.map(\.summary),
                    subjects: source.subjects.map(\.summary), pendingReviews: source.pendingReviews.count)
                if let cached { cached.snapshot = snapshot }
                else { modelContext.insert(SnapshotRecord(snapshot, credentialID: credentialID)) }
            }
            modelContext.insert(ImportReceipt(sourceID: receiptID, digest: digest))
        }
        return LegacyImportResult(alreadyImported: alreadyImported, subjects: source.subjects.count,
            assignments: source.assignments.filter { assignment in !source.pendingReviews.contains { $0.assignment.subjectID == assignment.subjectID } }.count,
            pendingReviews: source.pendingReviews.count, pendingMaterials: source.materials.filter(\.pending).count)
    }
}
