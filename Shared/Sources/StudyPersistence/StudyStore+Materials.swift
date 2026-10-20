import Foundation
import StudyCore
import SwiftData

/// A wrapper distinguishes an observed missing record from an edit without a recovery check.
struct StudyMaterialBaseline: Codable, Equatable, Sendable {
  let remote: WaniKaniMaterial?
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

extension MaterialRecord {
  static func fetch(in context: ModelContext, accountID: String) throws -> [MaterialRecord] {
    try context.fetch(
      FetchDescriptor<MaterialRecord>(predicate: #Predicate { $0.accountID == accountID }))
  }

  static func fetch(in context: ModelContext, accountID: String, subjectID: Int64) throws
    -> MaterialRecord?
  {
    try context.fetch(
      FetchDescriptor<MaterialRecord>(
        predicate: #Predicate {
          $0.accountID == accountID && $0.subjectID == subjectID
        })
    ).first
  }
}

extension StudyStore {
  public func materials(accountID: String) throws -> [SavedStudyMaterial] {
    try MaterialRecord.fetch(in: modelContext, accountID: accountID).map(\.saved).sorted {
      $0.material.subjectID < $1.material.subjectID
    }
  }

  @discardableResult public func saveMaterial(
    _ material: StudyMaterial, accountID: String,
    expectedRevision: UUID?
  ) throws -> UUID {
    var revision = UUID()
    try transaction {
      revision = try writeMaterial(
        material, accountID: accountID, expectedRevision: expectedRevision)
    }
    return revision
  }

  /// Caller owns the transaction; all material paths retain the same revision/recovery policy.
  func writeMaterial(_ material: StudyMaterial, accountID: String, expectedRevision: UUID?) throws
    -> UUID
  {
    try requireAccount(accountID)
    guard material.subjectID > 0 else { throw StudyStoreError.invalidMaterial }
    let existing = try MaterialRecord.fetch(
      in: modelContext, accountID: accountID, subjectID: material.subjectID)
    guard existing?.revision == expectedRevision else { throw StudyStoreError.staleMaterial }
    if let existing {
      existing.material = material
      existing.revision = UUID()
      existing.pending = true
      if existing.issue?.reason == .rejected { existing.issue = nil }
      return existing.revision
    }
    let row = MaterialRecord(accountID: accountID, material: material, pending: true)
    modelContext.insert(row)
    return row.revision
  }

  public func acknowledgeMaterial(_ sent: SavedStudyMaterial) throws {
    try transaction {
      if let row = try MaterialRecord.fetch(
        in: modelContext, accountID: sent.accountID, subjectID: sent.material.subjectID),
        row.revision == sent.revision,
        row.attemptedRevision == nil || row.attemptedRevision == sent.revision
      {
        row.pending = false
        row.revision = UUID()
        row.issue = nil
        row.attemptedRevision = nil
        row.attemptedMaterial = nil
        row.recoveryBaseline = nil
      }
    }
  }

  /// Capture revisions before a request. Even an edit already acknowledged by the time its
  /// response arrives must win over that older download. Full refresh never deletes dirty notes.
  public func mergeMaterials(
    _ incoming: [StudyMaterial], accountID: String,
    baseline: [Int64: UUID], replacingAll: Bool
  ) throws {
    try requireAccount(accountID)
    guard incoming.allSatisfy({ $0.subjectID > 0 }),
      Set(incoming.map(\.subjectID)).count == incoming.count
    else { throw StudyStoreError.invalidMaterial }
    try transaction {
      try applyMaterials(
        incoming, accountID: accountID, baseline: baseline, replacingAll: replacingAll)
    }
  }

  // Caller owns the transaction so a full download commits notes with the other resources.
  func applyMaterials(
    _ incoming: [StudyMaterial], accountID: String, baseline: [Int64: UUID],
    replacingAll: Bool, serverIDs: [Int64: Int64] = [:]
  ) throws {
    let rows = try MaterialRecord.fetch(in: modelContext, accountID: accountID)
    let current = Dictionary(uniqueKeysWithValues: rows.map { ($0.subjectID, $0) })
    let ids = Set(incoming.map(\.subjectID))
    if replacingAll {
      for row in rows
      where !ids.contains(row.subjectID) && !row.pending && baseline[row.subjectID] == row.revision
      {
        modelContext.delete(row)
      }
    }
    for material in incoming {
      if let row = current[material.subjectID] {
        guard !row.pending, baseline[material.subjectID] == row.revision else { continue }
        row.material = material
        row.revision = UUID()
        if let id = serverIDs[material.subjectID] { row.serverID = id }
      } else if baseline[material.subjectID] == nil {
        let row = MaterialRecord(accountID: accountID, material: material, pending: false)
        row.serverID = serverIDs[material.subjectID]
        modelContext.insert(row)
      }
    }
  }
}
