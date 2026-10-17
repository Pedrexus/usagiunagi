import Foundation
import StudyCore
import SwiftData

@Model final class MaterialRecord {
    #Unique<MaterialRecord>([\.accountID, \.subjectID])
    var accountID: String
    var subjectID: Int64
    var revision: UUID
    var pending: Bool
    var serverID: Int64? = nil
    @Attribute(.codable) var issue: StudyUploadIssue? = nil
    var attemptedRevision: UUID? = nil
    @Attribute(.codable) var attemptedMaterial: StudyMaterial? = nil
    @Attribute(.codable) var material: StudyMaterial
    init(accountID: String, material: StudyMaterial, pending: Bool) {
        self.accountID = accountID; self.subjectID = material.subjectID
        self.material = material; self.pending = pending; revision = UUID()
    }
    var saved: SavedStudyMaterial {
        SavedStudyMaterial(accountID: accountID, revision: revision, pending: pending, serverID: serverID,
            issue: issue, attemptedRevision: attemptedRevision, attemptedMaterial: attemptedMaterial, material: material)
    }
}

public struct SavedStudyMaterial: Sendable {
    public let accountID: String
    public let revision: UUID
    public let pending: Bool
    public let serverID: Int64?
    public let issue: StudyUploadIssue?
    public let attemptedRevision: UUID?
    public let attemptedMaterial: StudyMaterial?
    public let material: StudyMaterial
}

extension StudyStore {
    func materialRecords(accountID: String) throws -> [MaterialRecord] {
        try modelContext.fetch(FetchDescriptor<MaterialRecord>(predicate: #Predicate { $0.accountID == accountID }))
    }

    public func materials(accountID: String) throws -> [SavedStudyMaterial] {
        try materialRecords(accountID: accountID).map(\.saved).sorted { $0.material.subjectID < $1.material.subjectID }
    }

    @discardableResult public func saveMaterial(_ material: StudyMaterial, accountID: String,
                                                expectedRevision: UUID?) throws -> UUID {
        try requireAccount(accountID)
        guard material.subjectID > 0 else { throw StudyStoreError.invalidMaterial }
        var revision = UUID()
        try transaction {
            let existing = try materialRecords(accountID: accountID).first { $0.subjectID == material.subjectID }
            guard existing?.revision == expectedRevision else { throw StudyStoreError.staleMaterial }
            if let existing {
                existing.material = material; existing.revision = revision; existing.pending = true
                if existing.issue?.reason == .rejected { existing.issue = nil }
            } else {
                let row = MaterialRecord(accountID: accountID, material: material, pending: true)
                revision = row.revision; modelContext.insert(row)
            }
        }
        return revision
    }

    public func acknowledgeMaterial(_ sent: SavedStudyMaterial) throws {
        try transaction {
            if let row = try materialRecords(accountID: sent.accountID).first(where: {
                $0.subjectID == sent.material.subjectID && $0.revision == sent.revision
            }), row.attemptedRevision == nil || row.attemptedRevision == sent.revision {
                row.pending = false; row.revision = UUID(); row.issue = nil; row.attemptedRevision = nil; row.attemptedMaterial = nil
            }
        }
    }

    /// Capture revisions before a request. Even an edit already acknowledged by the time its
    /// response arrives must win over that older download. Full refresh never deletes dirty notes.
    public func mergeMaterials(_ incoming: [StudyMaterial], accountID: String,
                               baseline: [Int64: UUID], replacingAll: Bool) throws {
        try requireAccount(accountID)
        guard incoming.allSatisfy({ $0.subjectID > 0 }), Set(incoming.map(\.subjectID)).count == incoming.count
        else { throw StudyStoreError.invalidMaterial }
        try transaction { try applyMaterials(incoming, accountID: accountID, baseline: baseline, replacingAll: replacingAll) }
    }

    // Caller owns the transaction so a full download commits notes with the other resources.
    func applyMaterials(_ incoming: [StudyMaterial], accountID: String, baseline: [Int64: UUID],
                        replacingAll: Bool, serverIDs: [Int64: Int64] = [:]) throws {
        let rows = try materialRecords(accountID: accountID)
        let current = Dictionary(uniqueKeysWithValues: rows.map { ($0.subjectID, $0) })
        let ids = Set(incoming.map(\.subjectID))
        if replacingAll {
            for row in rows where !ids.contains(row.subjectID) && !row.pending && baseline[row.subjectID] == row.revision {
                modelContext.delete(row)
            }
        }
        for material in incoming {
            if let row = current[material.subjectID] {
                guard !row.pending, baseline[material.subjectID] == row.revision else { continue }
                row.material = material; row.revision = UUID()
                if let id = serverIDs[material.subjectID] { row.serverID = id }
            } else if baseline[material.subjectID] == nil {
                let row = MaterialRecord(accountID: accountID, material: material, pending: false)
                row.serverID = serverIDs[material.subjectID]; modelContext.insert(row)
            }
        }
    }
}
