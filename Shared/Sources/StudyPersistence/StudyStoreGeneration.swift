import CoreData
import CryptoKit
import Darwin
import Foundation
import StudyCore
import SwiftData

public enum StudyStoreOpeningError: Error, LocalizedError {
  case alreadyOpen, invalidSelection, invalidGeneration, sourceChanged, unsupportedLayout
  public var errorDescription: String? {
    switch self {
    case .alreadyOpen: "Close the other app instance before opening saved study data."
    case .invalidSelection:
      "The saved study-data selection could not be verified. All generations have been kept."
    case .invalidGeneration:
      "Saved study data could not be verified. No replacement account was created."
    case .sourceChanged:
      "Saved study data changed during preparation. Its original data has been kept."
    case .unsupportedLayout:
      "This study-data format needs a supported recovery path. Its files have been kept."
    }
  }
}

/// New application owners share this lease for their entire actor lifetime. It cannot make an older
/// binary or an unrelated external tool cooperate; the host must exclude its known older owners.
final class StudyStoreLease: Sendable {
  private let descriptor: Int32
  init(at url: URL) throws {
    let opened = Darwin.open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard opened >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
      Darwin.close(opened)
      throw StudyStoreOpeningError.alreadyOpen
    }
    descriptor = opened
  }
  deinit { Darwin.close(descriptor) }
}

extension StudyStore {
  /// Application-only startup. Explicit `open(at:)` remains for isolated import/test stores.
  @concurrent public static func openApplication(in directory: URL) async throws -> StudyStore {
    let generations = try StudyStoreGeneration(directory: directory)
    let lease = try StudyStoreLease(at: generations.directory.appending(path: "store-owner.lock"))
    let store = try await generations.open()
    await store.retainApplicationLease(lease)
    return store
  }
}

/// First-version adoption only. No old generation is opened in place, removed, or selected on error.
private struct StudyStoreGeneration: Sendable {
  private struct PhysicalSchema: Equatable, Sendable {
    let storeType: String
    let entityHashes: [String: Data]
  }
  private enum Phase: String, Codable, Equatable { case preparing, selected }
  private struct Selection: Codable, Equatable {
    let formatVersion: Int
    let schema: String
    let phase: Phase
    let candidate: UUID
    let retained: UUID?
    let source: [String: String]?
    let validation: String?
  }
  private struct SelectionKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }
  private struct SelectionEnvelope: Decodable {
    let value: Selection
    init(from decoder: any Decoder) throws {
      let fields = try decoder.container(keyedBy: SelectionKey.self)
      let allowed: Set<String> = [
        "formatVersion", "schema", "phase", "candidate", "retained", "source", "validation",
      ]
      guard Set(fields.allKeys.map(\.stringValue)).isSubset(of: allowed) else {
        throw StudyStoreOpeningError.invalidSelection
      }
      value = try Selection(from: decoder)
    }
  }
  let directory: URL
  private var manager: FileManager { .default }
  private let storeName = "study.store"
  private var selectionURL: URL { directory.appending(path: "store-selection.plist") }
  private var family: Set<String> { [storeName, storeName + "-wal", storeName + "-shm"] }

  init(directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink == false else {
      throw StudyStoreOpeningError.unsupportedLayout
    }
    self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
  }

  func open() async throws -> StudyStore {
    try Task.checkCancellation()
    let names = try entries(in: directory)
    // Fonts/audio and the earlier snapshot belong to their existing owners, outside store images.
    let allowed = family.union([
      "store-selection.plist", "store-owner.lock", "generations", "preparations",
      "fonts", "audio", "snapshot-v1.json",
    ])
    guard Set(names.map(\.lastPathComponent)).isSubset(of: allowed) else {
      throw StudyStoreOpeningError.unsupportedLayout
    }
    if manager.fileExists(atPath: selectionURL.path) {
      let selection = try loadSelection()
      if selection.phase == .selected {
        let url = generation(selection.candidate).appending(path: storeName)
        _ = try fingerprints(in: url.deletingLastPathComponent())
        let store = try namedStore(at: url)
        _ = try await store.generationSnapshot()
        return store
      }
      return try await prepare(selection)
    }
    // Selection loss must not reinterpret an existing generation as a fresh installation.
    for name in ["generations", "preparations"] {
      let url = directory.appending(path: name)
      if manager.fileExists(atPath: url.path), !(try entries(in: url)).isEmpty {
        throw StudyStoreOpeningError.invalidSelection
      }
    }
    let sourceNames = Set(names.map(\.lastPathComponent)).intersection(family)
    let source: [String: String]?
    if sourceNames.isEmpty {
      source = nil
    } else {
      source = try fingerprints(in: directory, original: true)
    }
    let selection = Selection(
      formatVersion: 1, schema: StudySchemaV1.versionIdentifier.description, phase: .preparing,
      candidate: UUID(), retained: source == nil ? nil : UUID(), source: source, validation: nil)
    try publish(selection)
    return try await prepare(selection)
  }

  private func prepare(_ previous: Selection) async throws -> StudyStore {
    try Task.checkCancellation()
    // Never reuse a candidate or working path whose container may survive a failed attempt.
    let selection = Selection(
      formatVersion: 1, schema: previous.schema, phase: .preparing, candidate: UUID(),
      retained: previous.retained, source: previous.source, validation: nil)
    try publish(selection)
    let work = directory.appending(path: "preparations/\(selection.candidate.uuidString)")
    try makeDirectory(work)
    try encode(selection).write(to: work.appending(path: "preparation.plist"), options: .atomic)
    let candidate = generation(selection.candidate)
    guard !manager.fileExists(atPath: candidate.path) else {
      throw StudyStoreOpeningError.invalidGeneration
    }
    try makeDirectory(candidate)
    let store: StudyStore
    if let source = selection.source, let retainedID = selection.retained {
      guard try fingerprints(in: directory, original: true) == source else {
        throw StudyStoreOpeningError.sourceChanged
      }
      let retained = generation(retainedID)
      if manager.fileExists(atPath: retained.path) {
        guard try fingerprints(in: retained) == source else {
          throw StudyStoreOpeningError.invalidGeneration
        }
      } else {
        let capture = work.appending(path: "capture")
        try clone(from: directory, to: capture, expected: source)
        guard try fingerprints(in: directory, original: true) == source else {
          throw StudyStoreOpeningError.sourceChanged
        }
        try synchronize(capture)
        try manager.moveItem(at: capture, to: retained)
        try synchronizeDirectory(retained.deletingLastPathComponent())
      }
      // FileManager cannot publish a read-only directory. Protect the retained image after its
      // move, including when a previous process stopped between publication and protection.
      for file in try entries(in: retained) {
        try manager.setAttributes([.posixPermissions: 0o400], ofItemAtPath: file.path)
      }
      try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: retained.path)
      let verification = work.appending(path: "verification")
      try clone(from: retained, to: verification, expected: source)
      // Inspect the stored model before any SwiftData container can adopt or migrate this clone.
      // The requested Schema is not evidence of the physical source schema.
      let physical = try physicalSchema(in: verification)
      let reference = work.appending(path: "reference")
      try makeDirectory(reference)
      let referenceStore = try namedStore(at: reference.appending(path: storeName))
      _ = try await referenceStore.generationSnapshot(requiringEmpty: true)
      let frozenV1 = try physicalSchema(in: reference)
      guard physical == frozenV1 else { throw StudyStoreOpeningError.invalidGeneration }
      let oldSchema = StudySchemaV1.unversioned
      let oldConfiguration = ModelConfiguration(
        schema: oldSchema, url: verification.appending(path: storeName), allowsSave: false,
        cloudKitDatabase: .none)
      try validateCodableValues(at: verification.appending(path: storeName))
      let reader = StudyStore(
        modelContainer: try ModelContainer(
          for: oldSchema, configurations: oldConfiguration))
      let expected = try await reader.generationSnapshot()
      guard try physicalSchema(in: verification) == physical else {
        throw StudyStoreOpeningError.invalidGeneration
      }
      let staging = work.appending(path: "staging")
      try clone(from: retained, to: staging, expected: source)
      // The public copier may maintain its source's auxiliary files. Only this marked staging
      // directory is passed to it, never the original, retained image, or verification container.
      guard
        try decodeSelection(Data(contentsOf: work.appending(path: "preparation.plist")))
          == selection
      else {
        throw StudyStoreOpeningError.invalidSelection
      }
      let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
      try coordinator.performAndWait {
        try coordinator.replacePersistentStore(
          at: candidate.appending(path: storeName), destinationOptions: nil,
          withPersistentStoreFrom: staging.appending(path: storeName),
          sourceOptions: [NSReadOnlyPersistentStoreOption: true], type: .sqlite)
      }
      guard try physicalSchema(in: candidate) == frozenV1 else {
        throw StudyStoreOpeningError.invalidGeneration
      }
      store = try namedStore(at: candidate.appending(path: storeName))
      guard try await store.generationSnapshot() == expected,
        try physicalSchema(in: candidate) == frozenV1,
        try fingerprints(in: retained) == source,
        try fingerprints(in: directory, original: true) == source
      else { throw StudyStoreOpeningError.sourceChanged }
    } else {
      guard selection.source == nil, selection.retained == nil else {
        throw StudyStoreOpeningError.invalidSelection
      }
      guard try entries(in: directory).allSatisfy({ !family.contains($0.lastPathComponent) }) else {
        throw StudyStoreOpeningError.sourceChanged
      }
      store = try namedStore(at: candidate.appending(path: storeName))
      _ = try await store.generationSnapshot(requiringEmpty: true)
    }
    let validated = try await store.generationSnapshot()
    try synchronize(candidate)
    try Task.checkCancellation()
    if selection.source == nil,
      try entries(in: directory).contains(where: { family.contains($0.lastPathComponent) })
    {
      throw StudyStoreOpeningError.sourceChanged
    }
    try publish(
      Selection(
        formatVersion: 1, schema: selection.schema, phase: .selected,
        candidate: selection.candidate,
        retained: selection.retained, source: selection.source, validation: digest(validated)))
    return store
  }

  /// Called only for mutable verification/reference/candidate images, never original or retained.
  /// Metadata loading may create auxiliary SQLite files even with the read-only option.
  private func physicalSchema(in folder: URL) throws -> PhysicalSchema {
    let url = folder.appending(path: storeName)
    try requireRegular(url)
    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
      type: .sqlite, at: url, options: [NSReadOnlyPersistentStoreOption: true])
    guard let storeType = metadata[NSStoreTypeKey] as? String,
      storeType == NSSQLiteStoreType,
      let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data],
      !hashes.isEmpty, hashes.keys.allSatisfy({ !$0.isEmpty }),
      hashes.values.allSatisfy({ !$0.isEmpty })
    else { throw StudyStoreOpeningError.invalidGeneration }
    // Dictionary equality compares every entity identity and its exact stored model-version hash.
    // It does not prove historical Codable decoder compatibility or compare store UUIDs.
    return PhysicalSchema(storeType: storeType, entityHashes: hashes)
  }
  private func namedStore(at url: URL) throws -> StudyStore {
    if manager.fileExists(atPath: url.path) { try validateCodableValues(at: url) }
    let schema = StudySchemaV1.schema
    let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    return StudyStore(
      modelContainer: try ModelContainer(
        for: schema, migrationPlan: StudySchemaMigrationPlan.self, configurations: configuration))
  }
  /// Binary projections avoid Core Data's fatal transformed-value decoding. Only active selected
  /// stores and mutable verification/candidate images reach this method, never retained originals.
  private func validateCodableValues(at url: URL) throws {
    try requireRegular(url)
    try Task.checkCancellation()
    let schema = StudySchemaV1.schema
    let options = [NSReadOnlyPersistentStoreOption: true]
    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
      type: .sqlite, at: url, options: options)
    let model = try NSPersistentStoreCoordinator.cachedModelForPersistentStore(
      at: url, options: options)
    guard let frozen = NSManagedObjectModel.makeManagedObjectModel(for: schema),
      metadata[NSStoreTypeKey] as? String == NSSQLiteStoreType,
      let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data],
      hashes == model.entityVersionHashesByName && hashes == frozen.entityVersionHashesByName,
      Set(hashes.keys) == Set(schema.entities.map(\.name))
    else { throw StudyStoreOpeningError.invalidGeneration }
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    let persistent = try coordinator.addPersistentStore(type: .sqlite, at: url, options: options)
    let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    do {
      try context.performAndWait {
        defer { context.reset() }
        let schema = StudySchemaV1.schema
        func decode<Value: Decodable>(_ type: Value.Type, _ data: Data) throws {
          do { _ = try JSONDecoder().decode(type, from: data) } catch is DecodingError {
            throw StudyStoreOpeningError.invalidGeneration
          }
        }
        let validators: [String: (Data) throws -> Void] = [
          "SnapshotRecord.snapshot": { try decode(StudySnapshot.self, $0) },
          "SessionRecord.session": { try decode(StudySession.self, $0) },
          "ReviewRecord.submission": { try decode(StudyReviewSubmission.self, $0) },
          "ReviewRecord.originalItem": { try decode(StudySessionItem.self, $0) },
          "ReviewRecord.originalAssignment": { try decode(CatalogAssignment?.self, $0) },
          "ReviewRecord.issue": { try decode(StudyUploadIssue?.self, $0) },
          "ImportReceipt.handoff": { try decode(StudyLegacyHandoff?.self, $0) },
          "CatalogRecord.subject": { try decode(CatalogSubject.self, $0) },
          "AssignmentRecord.assignment": { try decode(CatalogAssignment.self, $0) },
          "AccountRecord.state": { try decode(StudyAccountState.self, $0) },
          "MaterialRecord.issue": { try decode(StudyUploadIssue?.self, $0) },
          "MaterialRecord.attemptedMaterial": { try decode(StudyMaterial?.self, $0) },
          "MaterialRecord.recoveryBaseline": { try decode(StudyMaterialBaseline?.self, $0) },
          "MaterialRecord.material": { try decode(StudyMaterial.self, $0) },
          "ArchivedReviewRecord.answer": { try decode(ArchivedStudyReview.self, $0) },
        ]
        let fields = Set(
          schema.entities.flatMap { entity in
            entity.attributes.filter(\.isCodable).map { entity.name + "." + $0.name }
          })
        guard fields == Set(validators.keys) else {
          throw StudyStoreOpeningError.invalidGeneration
        }
        for entity in schema.entities {
          try Task.checkCancellation()
          let attributes = entity.attributes.filter(\.isCodable)
          guard !attributes.isEmpty else { continue }
          guard
            let description = NSEntityDescription.entity(forEntityName: entity.name, in: context)
          else { throw StudyStoreOpeningError.invalidGeneration }
          let request = NSFetchRequest<NSDictionary>(entityName: entity.name)
          request.entity = description
          request.resultType = .dictionaryResultType
          request.propertiesToFetch = attributes.map { attribute in
            let projection = NSExpressionDescription()
            projection.name = attribute.name
            projection.expression = NSExpression(forKeyPath: attribute.name)
            projection.resultType = .binaryData
            return projection
          }
          request.includesPendingChanges = false
          for row in try context.fetch(request) {
            try Task.checkCancellation()
            for attribute in attributes {
              let key = entity.name + "." + attribute.name
              guard let validate = validators[key] else {
                throw StudyStoreOpeningError.invalidGeneration
              }
              if let data = row[attribute.name] as? Data {
                try validate(data)
              } else if !attribute.isOptional
                || !(row[attribute.name] == nil || row[attribute.name] is NSNull)
              {
                throw StudyStoreOpeningError.invalidGeneration
              }
            }
          }
        }
      }
    } catch {
      try coordinator.remove(persistent)
      throw error
    }
    try coordinator.remove(persistent)
  }
  private func loadSelection() throws -> Selection {
    try requireRegular(selectionURL)
    return try decodeSelection(Data(contentsOf: selectionURL))
  }
  private func decodeSelection(_ data: Data) throws -> Selection {
    let selection = try PropertyListDecoder().decode(SelectionEnvelope.self, from: data).value
    guard selection.formatVersion == 1,
      selection.schema == StudySchemaV1.versionIdentifier.description,
      (selection.source == nil) == (selection.retained == nil),
      selection.candidate != selection.retained,
      selection.phase == .selected ? selection.validation?.count == 64 : selection.validation == nil
    else { throw StudyStoreOpeningError.invalidSelection }
    if let source = selection.source {
      guard source[storeName] != nil, Set(source.keys).isSubset(of: family),
        source.values.allSatisfy({ $0.count == 64 && $0.allSatisfy { $0.isASCII && $0.isHexDigit } }
        )
      else { throw StudyStoreOpeningError.invalidSelection }
    }
    if let validation = selection.validation,
      !validation.allSatisfy({ $0.isASCII && $0.isHexDigit })
    {
      throw StudyStoreOpeningError.invalidSelection
    }
    return selection
  }
  private func generation(_ id: UUID) -> URL {
    directory.appending(path: "generations/\(id.uuidString)")
  }
  private func publish(_ selection: Selection) throws {
    try encode(selection).write(to: selectionURL, options: .atomic)
    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: selectionURL.path)
    try synchronizeFile(selectionURL)
    try synchronizeDirectory(directory)
  }
  private func encode(_ selection: Selection) throws -> Data {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    return try encoder.encode(selection)
  }
  private func clone(from source: URL, to destination: URL, expected: [String: String]) throws {
    try makeDirectory(destination)
    for name in expected.keys.sorted() {
      try Task.checkCancellation()
      let target = destination.appending(path: name)
      try manager.copyItem(at: source.appending(path: name), to: target)
      try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    guard try fingerprints(in: destination) == expected else {
      throw StudyStoreOpeningError.sourceChanged
    }
  }
  private func fingerprints(in folder: URL, original: Bool = false) throws -> [String: String] {
    var result: [String: String] = [:]
    for file in try entries(in: folder) {
      if original && !family.contains(file.lastPathComponent) { continue }
      guard family.contains(file.lastPathComponent) else {
        throw StudyStoreOpeningError.unsupportedLayout
      }
      try requireRegular(file)
      if file.lastPathComponent == storeName,
        try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == 0
      {
        throw StudyStoreOpeningError.invalidGeneration
      }
      result[file.lastPathComponent] = try fileDigest(file)
    }
    guard result[storeName] != nil else { throw StudyStoreOpeningError.invalidGeneration }
    return result
  }
  private func entries(in url: URL) throws -> [URL] {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink == false else {
      throw StudyStoreOpeningError.unsupportedLayout
    }
    return try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
  }
  private func makeDirectory(_ url: URL) throws {
    guard url == directory || url.path.hasPrefix(directory.path + "/") else {
      throw StudyStoreOpeningError.unsupportedLayout
    }
    if manager.fileExists(atPath: url.path) {
      _ = try entries(in: url)
      return
    }
    try makeDirectory(url.deletingLastPathComponent())
    try manager.createDirectory(
      at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    _ = try entries(in: url)
  }
  private func requireRegular(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink == false else {
      throw StudyStoreOpeningError.unsupportedLayout
    }
  }
  private func fileDigest(_ url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hash = SHA256()
    while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
      try Task.checkCancellation()
      hash.update(data: chunk)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
  private func digest(_ snapshot: StudyGenerationSnapshot) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    // Activation evidence only: equality uses the typed snapshot, never this encoding of Sets.
    return SHA256.hash(data: try encoder.encode(snapshot)).map { String(format: "%02x", $0) }
      .joined()
  }
  private func synchronize(_ folder: URL) throws {
    for file in try entries(in: folder) {
      try requireRegular(file)
      try synchronizeFile(file)
    }
    try synchronizeDirectory(folder)
    try synchronizeDirectory(folder.deletingLastPathComponent())
  }
  private func synchronizeFile(_ url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.synchronize()
  }
  private func synchronizeDirectory(_ url: URL) throws {
    let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw POSIXError(.EIO) }
    defer { Darwin.close(descriptor) }
    guard Darwin.fsync(descriptor) == 0 else { throw POSIXError(.EIO) }
  }
}
