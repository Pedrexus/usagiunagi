#if DEBUG
  import CoreData
  import CryptoKit
  import Darwin
  import Foundation
  import StudyCore
  import SwiftData

  @testable import StudyPersistence

  // Experimental naming of the unchanged schema; no production model or migration is changed.
  private enum NativeUpgradeSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
      [
        SnapshotRecord.self, SessionRecord.self, ReviewRecord.self, MaterialRecord.self,
        ImportReceipt.self, CatalogRecord.self, AssignmentRecord.self, AccountRecord.self,
        UploadPauseRecord.self, ArchivedReviewRecord.self,
      ]
    }
  }
  private enum NativeUpgradePlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NativeUpgradeSchema.self] }
    static var stages: [MigrationStage] { [] }
  }

  /// Disposable public-API evidence, not a production backup, upgrade or activation implementation.
  enum NativeStoreUpgrade {
    static let commands = [
      "probe-native-upgrade", "verify-native-upgrade", "seed-native-upgrade-wal",
      "write-native-upgrade",
    ]
    private static let marker = Data("usagi-native-upgrade-disposable-v1".utf8)

    static func run(_ command: String, url: URL) async throws {
      if command == "probe-native-upgrade" {
        try experiment(frozen: url)
        return
      }
      try requireDisposable(url)
      let expected = try PropertyListDecoder().decode(
        NativeStoreBaseline.State.self, from: Data(contentsOf: expectedURL(url)))
      let store: StudyStore
      if command == "seed-native-upgrade-wal" {
        store = try await StudyStore.open(at: url)
      } else {
        store = try versionedStore(url)
      }
      let actual = try await store.nativeBaselineState()
      try NativeStoreBaseline.require(
        actual == expected, "Schema metadata or exact stored fields changed")
      if command == "verify-native-upgrade" {
        log("PASS: fresh named V1 process, \(actual.records.count) exact records / 10 models")
        return
      }
      let accountID = NativeStoreBaseline.accounts[0]
      guard
        let saved = try await store.materials(accountID: accountID).first(where: {
          $0.material.subjectID == 42
        })
      else { throw NativeStoreBaseline.Failure(description: "Missing synthetic baseline note") }
      var material = saved.material
      material.meaningNote = "\(command) note \u{0000}猫\n "
      try await store.saveMaterial(material, accountID: accountID, expectedRevision: saved.revision)
      try encode(try await store.nativeBaselineState(), to: expectedURL(url))
      if command == "seed-native-upgrade-wal" {
        log("CHECKPOINT: real transaction saved before abrupt WAL writer exit")
        _exit(86)
      }
      log("PASS: real transaction saved through named V1")
    }

    private static func experiment(frozen: URL) throws {
      let manager = FileManager.default
      let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
      let source = frozen.deletingLastPathComponent()
      let pristine = try hashes(in: source)
      let allowed = Set([frozen.lastPathComponent, frozen.lastPathComponent + ".baseline.plist"])
      try NativeStoreBaseline.require(
        Set(pristine.keys) == allowed, "Only the pinned journal-free synthetic fixture is allowed")
      let root = URL.temporaryDirectory.appending(path: "native-upgrade-\(UUID())")
      try manager.createDirectory(at: root, withIntermediateDirectories: true)
      try marker.write(to: root.appending(path: ".disposable"), options: .atomic)
      log("DISPOSABLE: \(root.path)")
      let base = root.appending(path: "base-source")
      // No persistence API receives the original fixture. Every open/copy uses a disposable clone.
      try manager.copyItem(at: source, to: base)
      let baseBefore = try hashes(in: base)
      let candidate = root.appending(path: "base-candidate/\(frozen.lastPathComponent)")
      try copyStore(from: base.appending(path: frozen.lastPathComponent), to: candidate)
      let baseAfter = try hashes(in: base)
      try NativeStoreBaseline.require(
        baseBefore.allSatisfy { baseAfter[$0.key] == $0.value },
        "Copy changed existing source bytes")
      log(
        "BASE-SOURCE-ADDED-AUXILIARY: \(Set(baseAfter.keys).subtracting(baseBefore.keys).sorted())")
      log("BASE-FULL-SOURCE-UNCHANGED: \(baseBefore == baseAfter)")
      try verifyTwice(candidate, expected: manifest.expected)

      let wal = root.appending(path: "wal-source")
      try manager.copyItem(at: source, to: wal)
      let walStore = wal.appending(path: frozen.lastPathComponent)
      try encode(manifest.expected, to: expectedURL(walStore))
      let walBefore = try hashes(in: wal)
      try child("seed-native-upgrade-wal", store: walStore, status: 86)
      let seeded = try hashes(in: wal)
      let walBytes = try Data(contentsOf: URL(filePath: walStore.path + "-wal")).count
      try NativeStoreBaseline.require(walBytes > 0, "Abrupt writer did not leave a populated WAL")
      try NativeStoreBaseline.require(
        walBefore[walStore.lastPathComponent] == seeded[walStore.lastPathComponent],
        "WAL-only transaction changed main-store bytes")
      let walExpected = try PropertyListDecoder().decode(
        NativeStoreBaseline.State.self, from: Data(contentsOf: expectedURL(walStore)))
      let walCandidate = root.appending(path: "wal-candidate/\(frozen.lastPathComponent)")
      try copyStore(from: walStore, to: walCandidate)
      let copied = try hashes(in: wal)
      for suffix in ["", "-wal"] {
        let name = walStore.lastPathComponent + suffix
        try NativeStoreBaseline.require(seeded[name] == copied[name], "Copy changed source \(name)")
      }
      log(
        "WAL-SOURCE-SHM-UNCHANGED: \(seeded[walStore.lastPathComponent + "-shm"] == copied[walStore.lastPathComponent + "-shm"])"
      )
      try verifyTwice(walCandidate, expected: walExpected)

      let protectedBase = root.appending(path: "protected-base-source")
      try manager.copyItem(at: source, to: protectedBase)
      try protectedCopy(
        from: protectedBase.appending(path: frozen.lastPathComponent),
        to: root.appending(path: "protected-base-candidate/\(frozen.lastPathComponent)"),
        expected: manifest.expected, succeeds: false)
      let protectedWAL = root.appending(path: "protected-wal-source")
      // The writer is dead: copy the complete stopped disposable generation, including WAL/SHM.
      try manager.copyItem(at: wal, to: protectedWAL)
      try protectedCopy(
        from: protectedWAL.appending(path: frozen.lastPathComponent),
        to: root.appending(path: "protected-wal-candidate/\(frozen.lastPathComponent)"),
        expected: walExpected, succeeds: true)
      let finalPristine = try hashes(in: source)
      try NativeStoreBaseline.require(
        finalPristine == pristine, "Original fixture bytes/names changed")
      log("PASS: \(walBytes)-byte WAL-only commit copied with exact durable fields")
      log("PASS: original frozen fixture filenames and SHA-256 hashes unchanged")
      log("SCOPED EXPERIMENT: no production activation, failure matrix, external-data or iOS proof")
    }

    private static func copyStore(from source: URL, to destination: URL) throws {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
      try coordinator.performAndWait {
        try coordinator.replacePersistentStore(
          at: destination, destinationOptions: nil, withPersistentStoreFrom: source,
          sourceOptions: [NSReadOnlyPersistentStoreOption: true], type: .sqlite)
      }
    }
    private static func protectedCopy(
      from source: URL, to destination: URL, expected: NativeStoreBaseline.State, succeeds: Bool
    ) throws {
      let manager = FileManager.default
      let directory = source.deletingLastPathComponent()
      let before = try hashes(in: directory)
      let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      for file in files {
        try manager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
      }
      try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
      defer {
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        for file in files {
          try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
      }
      try NativeStoreBaseline.require(
        !manager.isWritableFile(atPath: directory.path), "Source is writable")
      var copied = false
      do {
        try copyStore(from: source, to: destination)
        copied = true
      } catch {
        let failure = error as NSError
        try NativeStoreBaseline.require(
          !succeeds && failure.domain == "NSSQLiteErrorDomain" && failure.code == 8,
          "Unexpected protected-copy error: \(failure.domain)/\(failure.code)")
        log("OBSERVED: protected journal-free copy refused NSSQLiteErrorDomain/8")
      }
      try NativeStoreBaseline.require(copied == succeeds, "Protected-copy result changed")
      let after = try hashes(in: directory)
      try NativeStoreBaseline.require(
        after == before, "Protected source filenames or bytes changed")
      log("PASS: \(directory.lastPathComponent) complete generation bytes/names unchanged")
      if copied {
        // Copying inherits 0444 source modes; make only the new disposable candidate writable.
        for file in try manager.contentsOfDirectory(
          at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        { try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        try verifyTwice(destination, expected: expected)
        try child("write-native-upgrade", store: destination)
        try child("verify-native-upgrade", store: destination)
        log("PASS: named V1 transaction survives a fresh-process reopen")
      }
    }
    private static func versionedStore(_ url: URL) throws -> StudyStore {
      let schema = Schema(versionedSchema: NativeUpgradeSchema.self)
      let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
      return StudyStore(
        modelContainer: try ModelContainer(
          for: schema, migrationPlan: NativeUpgradePlan.self, configurations: configuration))
    }
    private static func verifyTwice(_ url: URL, expected: NativeStoreBaseline.State) throws {
      try encode(expected, to: expectedURL(url))
      for _ in 0..<2 { try child("verify-native-upgrade", store: url) }
    }
    private static func child(_ command: String, store: URL, status: Int32 = 0) throws {
      let process = Process()
      process.executableURL = Bundle.main.executableURL
      process.arguments = [command, store.path]
      process.standardOutput = FileHandle.standardOutput
      process.standardError = FileHandle.standardError
      try process.run()
      process.waitUntilExit()
      try NativeStoreBaseline.require(
        process.terminationReason == .exit && process.terminationStatus == status,
        "\(command) process failed: \(process.terminationStatus)")
    }
    private static func requireDisposable(_ url: URL) throws {
      let root = url.resolvingSymlinksInPath().deletingLastPathComponent()
        .deletingLastPathComponent()
      let temporary = URL.temporaryDirectory.resolvingSymlinksInPath()
      try NativeStoreBaseline.require(
        root.deletingLastPathComponent() == temporary
          && root.lastPathComponent.hasPrefix("native-upgrade-")
          && (try Data(contentsOf: root.appending(path: ".disposable"))) == marker,
        "Upgrade child commands require the probe's marked temporary fixture")
    }
    private static func hashes(in directory: URL) throws -> [String: String] {
      var result: [String: String] = [:]
      for file in try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        try NativeStoreBaseline.require(
          values.isRegularFile == true && values.isSymbolicLink == false,
          "This fixture probe does not cover directories or symbolic links")
        result[file.lastPathComponent] = SHA256.hash(data: try Data(contentsOf: file))
          .map { String(format: "%02x", $0) }.joined()
      }
      return result
    }
    private static func expectedURL(_ url: URL) -> URL {
      url.appendingPathExtension("upgrade.plist")
    }
    private static func encode(_ value: some Encodable, to url: URL) throws {
      let encoder = PropertyListEncoder()
      encoder.outputFormat = .binary
      try encoder.encode(value).write(to: url, options: .atomic)
    }
    private static func log(_ message: String) {
      FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
  }
#endif
