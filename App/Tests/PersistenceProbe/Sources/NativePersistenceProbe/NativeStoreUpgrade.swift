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

  /// Disposable checks of schema-copy APIs and the production opener, never real app stores.
  enum NativeStoreUpgrade {
    static let commands = [
      "probe-native-upgrade", "verify-native-upgrade", "seed-native-upgrade-wal",
      "write-native-upgrade",
      "probe-application-opening", "initialize-application-opening",
      "verify-application-opening", "write-application-opening", "lease-application-opening",
      "refuse-application-opening",
    ]
    private static let marker = Data("usagi-native-upgrade-disposable-v1".utf8)

    static func run(_ command: String, url: URL) async throws {
      if command == "probe-native-upgrade" {
        try experiment(frozen: url)
        return
      }
      if command == "probe-application-opening" {
        try applicationExperiment(frozen: url)
        return
      }
      try requireDisposable(url)
      if command.hasSuffix("application-opening") {
        try await applicationCommand(command, url: url)
        return
      }
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

    private static func applicationCommand(_ command: String, url: URL) async throws {
      let directory = url.deletingLastPathComponent()
      if command == "refuse-application-opening" {
        do {
          _ = try await StudyStore.openApplication(in: directory)
          throw NativeStoreBaseline.Failure(description: "A second process acquired the writer")
        } catch StudyStoreOpeningError.alreadyOpen {
          log("PASS: second process refused while the application actor owns its lease")
        }
        return
      }
      let store = try await StudyStore.openApplication(in: directory)
      defer { withExtendedLifetime(store) {} }
      let actual = try await store.nativeBaselineState()
      let expectedFile = directory.appendingPathExtension("expected.plist")
      if command == "initialize-application-opening" {
        try NativeStoreBaseline.require(
          actual.records.isEmpty && actual.schema.map(\.name) == NativeStoreBaseline.models,
          "Fresh application generation is not empty or has a different model set")
        try encode(actual, to: expectedFile)
        log("PASS: fresh installation selects one empty named application generation")
        return
      }
      let expected = try PropertyListDecoder().decode(
        NativeStoreBaseline.State.self, from: Data(contentsOf: expectedFile))
      try NativeStoreBaseline.require(
        actual == expected, "Application opening changed exact schema, records or stored fields")
      if command == "lease-application-opening" {
        try child("refuse-application-opening", store: url)
        return
      }
      if command == "verify-application-opening" {
        log("PASS: production application opener restored \(actual.records.count) exact records")
        return
      }
      try NativeStoreBaseline.require(command == "write-application-opening", "Unknown command")
      let accountID = NativeStoreBaseline.accounts[0]
      guard let saved = try await store.session(accountID: accountID),
        let material = try await store.materials(accountID: accountID).first(where: {
          $0.material.subjectID == 42
        })
      else { throw NativeStoreBaseline.Failure(description: "Missing baseline session or note") }
      var session = saved.session
      var revision = saved.revision
      let completed = session.completedIDs.count
      for tick in 0..<4 {
        guard let question = session.nextQuestion(continuingCurrentItem: true) else { break }
        _ = try session.mark(.correct, for: question, now: 1_700_001_000 + Int64(tick))
        revision = try await store.saveSession(
          session, accountID: accountID, expectedRevision: revision)
        if session.completedIDs.count > completed { break }
      }
      try NativeStoreBaseline.require(
        session.completedIDs.count > completed,
        "The post-activation answer did not complete an item")
      var note = material.material
      note.meaningNote += "\napplication generation edit \u{0000}🐰"
      try await store.saveMaterial(note, accountID: accountID, expectedRevision: material.revision)
      try encode(try await store.nativeBaselineState(), to: expectedFile)
      log("CHECKPOINT: application answer/outbox and note committed before abrupt process exit")
      _exit(86)
    }

    private static func applicationExperiment(frozen: URL) throws {
      let manager = FileManager.default
      let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
      let source = frozen.deletingLastPathComponent()
      let pristine = try hashes(in: source)
      let root = URL.temporaryDirectory.appending(path: "native-upgrade-\(UUID())")
      try manager.createDirectory(at: root, withIntermediateDirectories: true)
      try marker.write(to: root.appending(path: ".disposable"), options: .atomic)
      log("DISPOSABLE APPLICATION PROBE: \(root.path)")

      let walSource = root.appending(path: "wal-source")
      try manager.copyItem(at: source, to: walSource)
      let walStore = walSource.appending(path: frozen.lastPathComponent)
      try encode(manifest.expected, to: expectedURL(walStore))
      let beforeWAL = try applicationSource(in: walSource)
      try child("seed-native-upgrade-wal", store: walStore, status: 86)
      let committedWAL = try applicationSource(in: walSource)
      try NativeStoreBaseline.require(
        committedWAL["study.store"] == beforeWAL["study.store"]
          && committedWAL["study.store-wal"]?.isEmpty == false,
        "The source transaction was not committed exclusively in a populated WAL")
      let walExpected = try PropertyListDecoder().decode(
        NativeStoreBaseline.State.self, from: Data(contentsOf: expectedURL(walStore)))

      for (name, origin, expected) in [
        ("base-application", source, manifest.expected),
        ("wal-application", walSource, walExpected),
      ] {
        let directory = root.appending(path: name)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = try applicationSource(in: origin)
        for (name, data) in bytes { try data.write(to: directory.appending(path: name)) }
        try encode(expected, to: directory.appendingPathExtension("expected.plist"))
        let url = directory.appending(path: "study.store")
        try child("verify-application-opening", store: url)
        let selection = try Data(contentsOf: directory.appending(path: "store-selection.plist"))
        try child("verify-application-opening", store: url)
        try child("lease-application-opening", store: url)
        try child("write-application-opening", store: url, status: 86)
        for _ in 0..<2 { try child("verify-application-opening", store: url) }
        try NativeStoreBaseline.require(
          try applicationSource(in: directory) == bytes
            && Data(contentsOf: directory.appending(path: "store-selection.plist")) == selection,
          "Reopen/write changed the original source image or selected a different generation")
        log("PASS: \(name) exact adoption, lease, committed answer/note and two fresh reopens")
      }

      let fresh = root.appending(path: "fresh-application/study.store")
      try child("initialize-application-opening", store: fresh)
      let selector = fresh.deletingLastPathComponent().appending(path: "store-selection.plist")
      let selected = try Data(contentsOf: selector)
      for _ in 0..<2 { try child("verify-application-opening", store: fresh) }
      try child("lease-application-opening", store: fresh)
      try NativeStoreBaseline.require(
        try applicationSource(in: fresh.deletingLastPathComponent()).isEmpty
          && Data(contentsOf: selector) == selected && hashes(in: source) == pristine,
        "Fresh reopen created an unselected store, or the pinned fixture changed")
      log("PASS: original frozen filenames/SHA-256 unchanged; no real account or network")
      log("SCOPE: production Mac opener/restarts, not mid-copy interruption, disk-full, V2 or iOS")
    }

    private static func applicationSource(in directory: URL) throws -> [String: Data] {
      var result: [String: Data] = [:]
      for name in ["study.store", "study.store-wal", "study.store-shm"] {
        let url = directory.appending(path: name)
        if FileManager.default.fileExists(atPath: url.path) {
          result[name] = try Data(contentsOf: url)
        }
      }
      return result
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
