import Foundation
import StudyCore
import SwiftData

/// Private, in-memory migration comparison. Unlike diagnostics, no account or receipt is omitted.
struct StudyGenerationSnapshot: Encodable, Equatable, Sendable {
  struct Attribute: Encodable, Equatable, Sendable {
    let name: String
    let originalName: String
    let type: String
    let optional: Bool
    let unique: Bool
    let codable: Bool
    let transformable: Bool
    let hashModifier: String?
  }
  struct Entity: Encodable, Equatable, Sendable {
    let name: String
    let attributes: [Attribute]
    let uniqueness: [[String]]
    let indices: [[String]]
    let relationships: [String]
  }
  struct Record: Encodable, Equatable, Sendable {
    let model: String
    let identity: [String]
    let fields: [String: Data]
  }
  let schemaVersion: String
  let entities: [Entity]
  let records: [Record]
  // Synthesized equality includes private handoff state and compares preference Sets by membership.
  let handoffs: [String: StudyLegacyHandoff]
}

extension StudyStore {
  /// Reads one committed actor-owned state without suspension or changes to revisions/attempts.
  func generationSnapshot(requiringEmpty: Bool = false) throws -> StudyGenerationSnapshot {
    modelContext.autosaveEnabled = false
    guard !modelContext.hasChanges else { throw StudyStoreOpeningError.invalidGeneration }
    let schema = modelContainer.schema
    let entities = schema.entities.map { entity in
      StudyGenerationSnapshot.Entity(
        name: entity.name,
        attributes: entity.attributes.map { attribute in
          .init(
            name: attribute.name, originalName: attribute.originalName,
            type: String(reflecting: attribute.valueType), optional: attribute.isOptional,
            unique: attribute.isUnique, codable: attribute.isCodable,
            transformable: attribute.isTransformable, hashModifier: attribute.hashModifier)
        }.sorted { $0.name < $1.name },
        uniqueness: entity.uniquenessConstraints.sorted { $0.lexicographicallyPrecedes($1) },
        indices: entity.indices.sorted { $0.lexicographicallyPrecedes($1) },
        relationships: entity.relationships.map(\.name).sorted())
    }.sorted { $0.name < $1.name }
    guard entities.allSatisfy({ $0.relationships.isEmpty }) else {
      throw StudyStoreOpeningError.unsupportedLayout
    }
    func bytes(_ value: some Encodable) throws -> Data {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      return try encoder.encode(value)
    }
    var records: [StudyGenerationSnapshot.Record] = []
    var handoffs: [String: StudyLegacyHandoff] = [:]
    for row in try modelContext.fetch(FetchDescriptor<SnapshotRecord>()) {
      records.append(
        try .init(
          model: "SnapshotRecord", identity: [row.credentialID],
          fields: [
            "credentialID": bytes(row.credentialID), "snapshot": bytes(row.snapshot),
          ]))
    }
    for row in try modelContext.fetch(FetchDescriptor<SessionRecord>()) {
      records.append(
        try .init(
          model: "SessionRecord", identity: [row.accountID],
          fields: [
            "accountID": bytes(row.accountID), "revision": bytes(row.revision),
            "session": bytes(row.session),
          ]))
    }
    for row in try modelContext.fetch(FetchDescriptor<ReviewRecord>()) {
      records.append(
        try .init(
          model: "ReviewRecord", identity: [row.accountID, String(row.subjectID)],
          fields: [
            "accountID": bytes(row.accountID), "subjectID": bytes(row.subjectID),
            "revision": bytes(row.revision), "attempted": bytes(row.attempted),
            "submission": bytes(row.submission), "originalItem": bytes(row.originalItem),
            "originalAssignment": bytes(row.originalAssignment), "issue": bytes(row.issue),
          ]))
    }
    for row in try modelContext.fetch(FetchDescriptor<MaterialRecord>()) {
      records.append(
        try .init(
          model: "MaterialRecord", identity: [row.accountID, String(row.subjectID)],
          fields: [
            "accountID": bytes(row.accountID), "subjectID": bytes(row.subjectID),
            "revision": bytes(row.revision), "pending": bytes(row.pending),
            "serverID": bytes(row.serverID), "issue": bytes(row.issue),
            "attemptedRevision": bytes(row.attemptedRevision),
            "attemptedMaterial": bytes(row.attemptedMaterial),
            "recoveryBaseline": bytes(row.recoveryBaseline), "material": bytes(row.material),
          ]))
    }
    for row in try modelContext.fetch(FetchDescriptor<ImportReceipt>()) {
      if let handoff = row.handoff { handoffs[row.sourceID] = handoff }
      records.append(
        try .init(
          model: "ImportReceipt", identity: [row.sourceID],
          fields: [
            "sourceID": bytes(row.sourceID), "digest": bytes(row.digest),
            "handoff": bytes(row.handoff != nil),
          ]))
    }
    for row in try modelContext.fetch(FetchDescriptor<CatalogRecord>()) {
      records.append(
        try .init(
          model: "CatalogRecord", identity: [row.accountID, String(row.subjectID)],
          fields: [
            "accountID": bytes(row.accountID), "subjectID": bytes(row.subjectID),
            "level": bytes(row.level),
            "japanese": bytes(row.japanese), "subject": bytes(row.subject),
          ]))
    }
    for row in try modelContext.fetch(FetchDescriptor<AssignmentRecord>()) {
      records.append(
        try .init(
          model: "AssignmentRecord", identity: [row.accountID, String(row.subjectID)],
          fields: [
            "accountID": bytes(row.accountID), "subjectID": bytes(row.subjectID),
            "revision": bytes(row.revision), "assignment": bytes(row.assignment),
          ]))
    }
    for row in try modelContext.fetch(FetchDescriptor<AccountRecord>()) {
      records.append(
        try .init(
          model: "AccountRecord", identity: [row.accountID],
          fields: [
            "accountID": bytes(row.accountID), "state": bytes(row.state),
          ]))
    }
    for row in try modelContext.fetch(FetchDescriptor<UploadPauseRecord>()) {
      records.append(
        try .init(
          model: "UploadPauseRecord", identity: [row.accountID],
          fields: [
            "accountID": bytes(row.accountID), "retryAt": bytes(row.retryAt),
          ]))
    }
    for row in try modelContext.fetch(FetchDescriptor<ArchivedReviewRecord>()) {
      records.append(
        try .init(
          model: "ArchivedReviewRecord", identity: [row.id.uuidString],
          fields: [
            "id": bytes(row.id), "accountID": bytes(row.accountID), "answer": bytes(row.answer),
          ]))
    }
    guard !requiringEmpty || records.isEmpty else {
      throw StudyStoreOpeningError.invalidGeneration
    }
    guard Set(records.map { [$0.model] + $0.identity }).count == records.count else {
      throw StudyStoreOpeningError.invalidGeneration
    }
    for record in records {
      guard let entity = entities.first(where: { $0.name == record.model }),
        Set(record.fields.keys) == Set(entity.attributes.map(\.name))
      else { throw StudyStoreOpeningError.invalidGeneration }
    }
    records.sort {
      $0.model == $1.model
        ? $0.identity.lexicographicallyPrecedes($1.identity) : $0.model < $1.model
    }
    return StudyGenerationSnapshot(
      schemaVersion: schema.version.description, entities: entities, records: records,
      handoffs: handoffs)
  }
  func retainApplicationLease(_ lease: StudyStoreLease) {
    applicationLease = lease
  }
}
