#if DEBUG
  import Foundation
  import StudyCore
  import SwiftData

  @testable import StudyPersistence

  /// Reads frozen native-store evidence; the historical writer is excluded from current targets.
  enum NativeStoreBaseline {
    static let writerCommit = "186c1cc350f03d69c11e85bcb6f4d4084bece9b1"
    static let writerSourceHash = "6b23acc31dae349bb5c128ecb47c4c892908821c2c057fe7303a62cc84f23eff"
    static let accounts = ["baseline-account-a", "baseline-account-b"]
    static let models = [
      "AccountRecord", "ArchivedReviewRecord", "AssignmentRecord", "CatalogRecord", "ImportReceipt",
      "MaterialRecord", "ReviewRecord", "SessionRecord", "SnapshotRecord", "UploadPauseRecord",
    ]

    struct Record: Codable, Equatable, Sendable {
      let model: String
      let identity: String
      let accountID: String?
      let fields: [String: Data]
    }
    struct Attribute: Codable, Equatable, Sendable {
      let name: String
      let originalName: String
      let type: String
      let optional: Bool
      let unique: Bool
      let codable: Bool
      let transformable: Bool
      let hashModifier: String?
    }
    struct Entity: Codable, Equatable, Sendable {
      let name: String
      let attributes: [Attribute]
      let uniqueness: [[String]]
      let indices: [[String]]
      let relationships: [String]
    }
    struct State: Codable, Equatable, Sendable {
      let schemaVersion: String
      let schema: [Entity]
      let records: [Record]
    }
    struct Manifest: Codable, Sendable {
      let formatVersion: Int
      let writerCommit: String
      let writerSourceHash: String
      let sourcePaths: [String]
      let schemaKind: String
      let accountIDs: [String]
      let expected: State
    }
    struct Failure: Error, CustomStringConvertible {
      let description: String
    }
    static func require(_ condition: Bool, _ message: String) throws {
      guard condition else { throw Failure(description: message) }
    }
    static func encoded(_ value: some Encodable) throws -> Data {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      return try encoder.encode(value)
    }
    static func run(_ command: String, url: URL) async throws {
      try require(command == "read-native-baseline", "Unknown baseline operation")
      let manifest = try frozenManifest(at: url)
      // Never open the frozen source. SwiftData may migrate or maintain WAL files on open.
      let folder = URL.temporaryDirectory.appending(path: "native-baseline-\(UUID())")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let copy = folder.appending(path: url.lastPathComponent)
      for suffix in ["", "-wal", "-shm"] {
        let source = URL(fileURLWithPath: url.path + suffix)
        if FileManager.default.fileExists(atPath: source.path) {
          try FileManager.default.copyItem(
            at: source, to: URL(fileURLWithPath: copy.path + suffix))
        }
      }
      for _ in 0..<2 {
        try await verify(copy, expected: manifest.expected)
      }
      print(
        "PASS: fresh process restored exact baseline fields, revisions, ownership and schema twice"
      )
    }

    static func frozenManifest(at url: URL) throws -> Manifest {
      try require(
        FileManager.default.fileExists(atPath: url.path), "The frozen baseline store is missing.")
      let manifest = try PropertyListDecoder().decode(
        Manifest.self, from: Data(contentsOf: url.appendingPathExtension("baseline.plist")))
      try require(
        manifest.formatVersion == 1 && manifest.writerCommit == writerCommit
          && manifest.writerSourceHash == writerSourceHash && manifest.schemaKind == "unversioned"
          && manifest.accountIDs == accounts && manifest.sourcePaths.count == 67,
        "Unexpected baseline provenance or format.")
      try validateCoverage(manifest.expected)
      return manifest
    }
    private static func verify(_ url: URL, expected: State) async throws {
      let store = try await StudyStore.open(at: url)
      let actual = try await store.nativeBaselineState()
      try require(actual.schemaVersion == expected.schemaVersion, "Schema version changed")
      try require(actual.schema == expected.schema, "Schema metadata changed")
      try require(actual.records.count == expected.records.count, "Stored record count changed")
      for (before, after) in zip(expected.records, actual.records) {
        try require(
          before == after, "Changed baseline record: \(before.model) / \(before.identity)")
      }
    }
    private static func validateCoverage(_ state: State) throws {
      try require(state.schema.map(\.name) == models, "Baseline must include all ten native models")
      try require(
        Set(state.records.map(\.model)) == Set(models), "A native record category is empty")
      try require(
        state.schema.flatMap(\.attributes).filter(\.codable).count == 15,
        "The pinned baseline must retain all fifteen Codable attributes")
      for model in models where model != "ImportReceipt" {
        try require(
          Set(state.records.filter { $0.model == model }.compactMap(\.accountID)) == Set(accounts),
          "Missing account-scoped coverage for \(model)")
      }
      for record in state.records {
        guard let entity = state.schema.first(where: { $0.name == record.model }) else {
          throw Failure(description: "Unknown record category")
        }
        try require(
          Set(record.fields.keys) == Set(entity.attributes.map(\.name)),
          "The baseline capture omitted a stored field in \(record.model)")
      }
    }

  }

  extension StudyStore {
    func nativeBaselineState() throws -> NativeStoreBaseline.State {
      let schema = modelContainer.schema
      let entities = schema.entities.map { entity in
        NativeStoreBaseline.Entity(
          name: entity.name,
          attributes: entity.attributes.map { attribute in
            NativeStoreBaseline.Attribute(
              name: attribute.name, originalName: attribute.originalName,
              type: String(reflecting: attribute.valueType), optional: attribute.isOptional,
              unique: attribute.isUnique, codable: attribute.isCodable,
              transformable: attribute.isTransformable, hashModifier: attribute.hashModifier)
          }.sorted { $0.name < $1.name },
          uniqueness: entity.uniquenessConstraints.sorted { $0.joined() < $1.joined() },
          indices: entity.indices.sorted { $0.joined() < $1.joined() },
          relationships: entity.relationships.map(\.name).sorted())
      }.sorted { $0.name < $1.name }
      func data(_ value: some Encodable) throws -> Data { try NativeStoreBaseline.encoded(value) }
      var records: [NativeStoreBaseline.Record] = []
      for row in try modelContext.fetch(FetchDescriptor<SnapshotRecord>()) {
        records.append(
          try .init(
            model: "SnapshotRecord", identity: row.credentialID, accountID: row.snapshot.accountID,
            fields: ["credentialID": data(row.credentialID), "snapshot": data(row.snapshot)]))
      }
      for row in try modelContext.fetch(FetchDescriptor<AccountRecord>()) {
        records.append(
          try .init(
            model: "AccountRecord", identity: row.accountID, accountID: row.accountID,
            fields: ["accountID": data(row.accountID), "state": data(row.state)]))
      }
      for row in try modelContext.fetch(FetchDescriptor<CatalogRecord>()) {
        records.append(
          try .init(
            model: "CatalogRecord", identity: "\(row.accountID)/\(row.subjectID)",
            accountID: row.accountID,
            fields: [
              "accountID": data(row.accountID), "subjectID": data(row.subjectID),
              "level": data(row.level), "japanese": data(row.japanese),
              "subject": data(row.subject),
            ]))
      }
      for row in try modelContext.fetch(FetchDescriptor<AssignmentRecord>()) {
        records.append(
          try .init(
            model: "AssignmentRecord", identity: "\(row.accountID)/\(row.subjectID)",
            accountID: row.accountID,
            fields: [
              "accountID": data(row.accountID), "subjectID": data(row.subjectID),
              "revision": data(row.revision), "assignment": data(row.assignment),
            ]))
      }
      for row in try modelContext.fetch(FetchDescriptor<SessionRecord>()) {
        records.append(
          try .init(
            model: "SessionRecord", identity: row.accountID, accountID: row.accountID,
            fields: [
              "accountID": data(row.accountID), "revision": data(row.revision),
              "session": data(row.session),
            ]))
      }
      for row in try modelContext.fetch(FetchDescriptor<ReviewRecord>()) {
        records.append(
          try .init(
            model: "ReviewRecord", identity: "\(row.accountID)/\(row.subjectID)",
            accountID: row.accountID,
            fields: [
              "accountID": data(row.accountID), "subjectID": data(row.subjectID),
              "revision": data(row.revision), "attempted": data(row.attempted),
              "submission": data(row.submission), "originalItem": data(row.originalItem),
              "originalAssignment": data(row.originalAssignment), "issue": data(row.issue),
            ]))
      }
      for row in try modelContext.fetch(FetchDescriptor<MaterialRecord>()) {
        records.append(
          try .init(
            model: "MaterialRecord", identity: "\(row.accountID)/\(row.subjectID)",
            accountID: row.accountID,
            fields: [
              "accountID": data(row.accountID), "subjectID": data(row.subjectID),
              "revision": data(row.revision), "pending": data(row.pending),
              "serverID": data(row.serverID),
              "issue": data(row.issue), "attemptedRevision": data(row.attemptedRevision),
              "attemptedMaterial": data(row.attemptedMaterial),
              "recoveryBaseline": data(row.recoveryBaseline),
              "material": data(row.material),
            ]))
      }
      for row in try modelContext.fetch(FetchDescriptor<ImportReceipt>()) {
        records.append(
          try .init(
            model: "ImportReceipt", identity: row.sourceID, accountID: row.handoff?.accountID,
            fields: [
              "sourceID": data(row.sourceID), "digest": data(row.digest),
              "handoff": data(row.handoff),
            ]))
      }
      for row in try modelContext.fetch(FetchDescriptor<UploadPauseRecord>()) {
        records.append(
          try .init(
            model: "UploadPauseRecord", identity: row.accountID, accountID: row.accountID,
            fields: ["accountID": data(row.accountID), "retryAt": data(row.retryAt)]))
      }
      for row in try modelContext.fetch(FetchDescriptor<ArchivedReviewRecord>()) {
        records.append(
          try .init(
            model: "ArchivedReviewRecord", identity: row.id.uuidString, accountID: row.accountID,
            fields: [
              "id": data(row.id), "accountID": data(row.accountID), "answer": data(row.answer),
            ]))
      }
      records.sort { ($0.model, $0.identity) < ($1.model, $1.identity) }
      return .init(schemaVersion: schema.version.description, schema: entities, records: records)
    }

  }
#endif
