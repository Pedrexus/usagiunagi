import Foundation
import StudyCore
import SwiftData

@Model final class MaterialRecord {
    #Unique<MaterialRecord>([\.accountID, \.subjectID])
    var accountID: String
    var subjectID: Int64
    var revision: UUID
    var pending: Bool
    @Attribute(.codable) var material: StudyMaterial
    init(accountID: String, material: StudyMaterial, pending: Bool) {
        self.accountID = accountID; self.subjectID = material.subjectID
        self.material = material; self.pending = pending; revision = UUID()
    }
}

public struct SavedStudyMaterial: Sendable {
    public let accountID: String
    public let revision: UUID
    public let pending: Bool
    public let material: StudyMaterial
}

extension StudyStore {
    private func materialRecords(accountID: String) throws -> [MaterialRecord] {
        try modelContext.fetch(FetchDescriptor<MaterialRecord>(predicate: #Predicate { $0.accountID == accountID }))
    }

    public func materials(accountID: String) throws -> [SavedStudyMaterial] {
        try materialRecords(accountID: accountID).map {
            SavedStudyMaterial(accountID: $0.accountID, revision: $0.revision, pending: $0.pending, material: $0.material)
        }.sorted { $0.material.subjectID < $1.material.subjectID }
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
            }) { row.pending = false }
        }
    }

    /// Capture revisions before a request. Even an edit already acknowledged by the time its
    /// response arrives must win over that older download. Full refresh never deletes dirty notes.
    public func mergeMaterials(_ incoming: [StudyMaterial], accountID: String,
                               baseline: [Int64: UUID], replacingAll: Bool) throws {
        try requireAccount(accountID)
        guard incoming.allSatisfy({ $0.subjectID > 0 }), Set(incoming.map(\.subjectID)).count == incoming.count
        else { throw StudyStoreError.invalidMaterial }
        try transaction {
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
                    guard !row.pending, baseline[row.subjectID] == row.revision else { continue }
                    row.material = material; row.revision = UUID()
                } else if baseline[material.subjectID] == nil {
                    modelContext.insert(MaterialRecord(accountID: accountID, material: material, pending: false))
                }
            }
        }
    }
}
