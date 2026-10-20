import CoreData
import CryptoKit
import Foundation
import SQLite3
import StudyCore
import Synchronization
import Testing

@testable import StudyPersistence

struct StudyStoreOpeningTests {
  @Test(.timeLimit(.minutes(1)), arguments: [false, true])
  func cancellationDuringOpeningPreservesDataAndAllowsRetry(selected: Bool) async throws {
    let folder = temporaryFolder()
    let seedFolder = temporaryFolder()
    defer {
      removeFolder(folder)
      removeFolder(seedFolder)
    }
    let writer = try await StudyStore.open(at: seedFolder.appending(path: "study.store"))
    defer { withExtendedLifetime(writer) {} }
    for account in ["first", "second"] {
      _ = try await writer.importLegacyAccount(
        source(username: account), sourceID: "source-\(account)", verifiedAccountID: account,
        verifiedUsername: account, credentialID: "credential-\(account)")
    }
    let expected = try await writer.generationSnapshot()
    let original = try family(in: seedFolder)
    try write(original, in: folder)
    if selected {
      let first = try await StudyStore.openApplication(in: folder)
      #expect(try await first.generationSnapshot() == expected)
    }
    let selectionURL = folder.appending(path: "store-selection.plist")
    let previousSelection = selected ? try Data(contentsOf: selectionURL) : nil
    let prefix = folder.resolvingSymlinksInPath().path + "/"
    let target: String?
    if selected {
      let id = try #require(try selection(in: folder)["candidate"] as? String)
      target = prefix + "generations/\(id)/study.store"
    } else {
      target = nil
    }
    let cancellation = Mutex<(operation: Task<StudyStore, any Error>?, paths: [String])>((nil, []))
    do {
      let start = AsyncStream<Void>.makeStream()
      let center = NotificationCenter.default
      let observer = center.addObserver(
        forName: .NSPersistentStoreCoordinatorStoresDidChange, object: nil, queue: nil
      ) { notification in
        // No Core Data object escapes this callback or is mutated by the test.
        let added = notification.userInfo?[NSAddedPersistentStoresKey] as? [NSPersistentStore] ?? []
        guard
          let path = added.compactMap({ $0.url?.resolvingSymlinksInPath().path }).first(where: {
            path in
            if let target { return path == target }
            return path.hasPrefix(prefix + "preparations/") && path.hasSuffix("/study.store")
          })
        else { return }
        cancellation.withLock {
          $0.paths.append(path)
          $0.operation?.cancel()
        }
      }
      defer {
        center.removeObserver(observer)
        cancellation.withLock { $0.operation = nil }
      }
      let operation = Task {
        var iterator = start.stream.makeAsyncIterator()
        _ = await iterator.next()
        return try await StudyStore.openApplication(in: folder)
      }
      cancellation.withLock { $0.operation = operation }
      start.continuation.yield(())
      start.continuation.finish()
      do {
        _ = try await operation.value
        Issue.record("Opening returned an owner after observed cancellation")
      } catch is CancellationError {}
    }
    #expect(!cancellation.withLock { $0.paths }.isEmpty)
    #expect(try family(in: folder) == original)
    #expect(try family(in: seedFolder) == original)
    let interrupted = try selection(in: folder)
    #expect(interrupted["phase"] as? String == (selected ? "selected" : "preparing"))
    let retainedID = try #require(interrupted["retained"] as? String)
    let retained = folder.appending(path: "generations/\(retainedID)")
    #expect(try family(in: retained) == original)
    let abandoned = try #require(interrupted["candidate"] as? String)
    let work = folder.appending(path: "preparations/\(abandoned)/preparation.plist")
    let preparation = selected ? nil : try Data(contentsOf: work)
    let reopened = try await StudyStore.openApplication(in: folder)
    #expect(try await reopened.generationSnapshot() == expected)
    #expect(try selection(in: folder)["phase"] as? String == "selected")
    #expect(try family(in: folder) == original && family(in: retained) == original)
    if let previousSelection {
      #expect(try Data(contentsOf: selectionURL) == previousSelection)
    } else {
      #expect(try selection(in: folder)["candidate"] as? String != abandoned)
      #expect(try Data(contentsOf: work) == preparation)
      #expect(
        try folder.appending(path: "generations/\(abandoned)")
          .resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    }
  }

  @Test func adoptionPreservesSourceWALSchemaIdentitiesAndExactCommittedState() async throws {
    let folder = temporaryFolder()
    defer { removeFolder(folder) }
    let writer = try await StudyStore.open(at: folder.appending(path: "study.store"))
    defer { withExtendedLifetime(writer) {} }
    for account in ["first", "second"] {
      _ = try await writer.importLegacyAccount(
        source(username: account), sourceID: "source-\(account)", verifiedAccountID: account,
        verifiedUsername: account, credentialID: "credential-\(account)")
    }
    let expected = try await writer.generationSnapshot()
    let original = try family(in: folder)
    #expect(try #require(original["study.store-wal"]).count > 0)
    let opened = try await StudyStore.openApplication(in: folder)
    #expect(try await opened.generationSnapshot() == expected)
    #expect(try family(in: folder) == original)
    let selection = try selection(in: folder)
    #expect(selection["phase"] as? String == "selected")
    #expect(selection["schema"] as? String == StudySchemaV1.versionIdentifier.description)
    let retained = try #require(selection["retained"] as? String)
    let retainedFolder = folder.appending(path: "generations/\(retained)")
    #expect(try family(in: retainedFolder) == original)
    for account in ["first", "second"] {
      let review = try #require(try await opened.pendingReviews(accountID: account).first)
      #expect(review.subjectID == 47 && review.submission.meaningWrongCount == 1)
      let material = try #require(try await opened.materials(accountID: account).first)
      #expect(
        material.material.subjectID == 47 && material.material.meaningNote == "Private 日本\u{0}ÿ")
      #expect(material.serverID == 947 && material.pending)
      _ = try await opened.saveMaterial(
        .init(subjectID: 47, meaningNote: "New native note"), accountID: account,
        expectedRevision: material.revision)
    }
    // Native writes never mutate the original or retained rollback images.
    #expect(try family(in: folder) == original)
    #expect(try family(in: retainedFolder) == original)
    #expect(try await opened.generationSnapshot() != expected)
    #expect(try await writer.generationSnapshot() == expected)
  }

  @Test func freshSelectionOwnsOneLeaseAndReopensTheSameGenerationWithItsNewWrites() async throws {
    let folder = temporaryFolder()
    defer { removeFolder(folder) }
    let expected: StudyGenerationSnapshot
    let selectedBytes: Data
    do {
      let first = try await StudyStore.openApplication(in: folder)
      _ = try await first.generationSnapshot(requiringEmpty: true)
      do {
        _ = try await StudyStore.openApplication(in: folder)
        Issue.record("A second application owner acquired the same store lease")
      } catch StudyStoreOpeningError.alreadyOpen {}
      _ = try await first.importLegacyAccount(
        source(username: "first"), sourceID: "first-source", verifiedAccountID: "first",
        verifiedUsername: "first", credentialID: "first-credential")
      expected = try await first.generationSnapshot()
      selectedBytes = try Data(contentsOf: folder.appending(path: "store-selection.plist"))
      #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "study.store").path))
    }
    let reopened = try await StudyStore.openApplication(in: folder)
    #expect(try await reopened.generationSnapshot() == expected)
    #expect(try Data(contentsOf: folder.appending(path: "store-selection.plist")) == selectedBytes)
    #expect(try await reopened.pendingReviews(accountID: "first").count == 1)
    _ = try await reopened.saveMaterial(
      .init(subjectID: 48, meaningNote: "After reopen"), accountID: "first", expectedRevision: nil)
    #expect(try await reopened.materials(accountID: "first").map(\.material.subjectID) == [47, 48])
  }

  @Test(arguments: ["corrupt", "zero-byte", "foreign-schema", "orphan-wal"])
  func unsupportedSourceNeverSelectsAnEmptyReplacementOrChangesSource(_ kind: String) async throws {
    let folder = temporaryFolder()
    defer { removeFolder(folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: kind == "orphan-wal" ? "study.store-wal" : "study.store")
    if kind == "foreign-schema" {
      var database: OpaquePointer?
      #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
      let handle = try #require(database)
      defer { sqlite3_close(handle) }
      #expect(
        sqlite3_exec(
          handle, "CREATE TABLE unrelated(value TEXT); INSERT INTO unrelated VALUES('kept');", nil,
          nil, nil) == SQLITE_OK)
    } else {
      try (kind == "zero-byte" ? Data() : Data("not a native store".utf8)).write(to: url)
    }
    let original = try family(in: folder)
    await #expect(throws: (any Error).self) { try await StudyStore.openApplication(in: folder) }
    #expect(try family(in: folder) == original)
    if FileManager.default.fileExists(atPath: folder.appending(path: "store-selection.plist").path)
    {
      #expect(try selection(in: folder)["phase"] as? String == "preparing")
    }
    // An interrupted preparation must refuse the same source again, never adopt its empty candidate.
    await #expect(throws: (any Error).self) { try await StudyStore.openApplication(in: folder) }
    #expect(try family(in: folder) == original)
    if kind == "orphan-wal" {
      #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "study.store").path))
    }
  }

  @Test(arguments: ["partial-capture", "partial-candidate", "complete-unselected-candidate"])
  func interruptedPreparationKeepsItsSourceAndAbandonedArtifactsWhileSelectingAFreshCandidate(
    _ checkpoint: String
  ) async throws {
    let folder = temporaryFolder()
    let seedFolder = temporaryFolder()
    defer {
      removeFolder(folder)
      removeFolder(seedFolder)
    }
    let writer = try await StudyStore.open(at: seedFolder.appending(path: "study.store"))
    defer { withExtendedLifetime(writer) {} }
    for account in ["first", "second"] {
      _ = try await writer.importLegacyAccount(
        source(username: account), sourceID: "source-\(account)", verifiedAccountID: account,
        verifiedUsername: account, credentialID: "credential-\(account)")
    }
    let expected = try await writer.generationSnapshot()
    var originalReviews: [String: [SavedReview]] = [:]
    var originalMaterials: [String: SavedStudyMaterial] = [:]
    for account in ["first", "second"] {
      originalReviews[account] = try await writer.pendingReviews(accountID: account)
      let material = try #require(try await writer.materials(accountID: account).first)
      originalMaterials[account] = material
    }
    let original = try family(in: seedFolder)
    #expect(try #require(original["study.store-wal"]).count > 0)
    try write(original, in: folder)
    #expect(try family(in: seedFolder) == original)
    let retainedID = UUID().uuidString
    let abandonedID = UUID().uuidString
    let retainedFolder = folder.appending(path: "generations/\(retainedID)")
    let abandonedFolder = folder.appending(path: "generations/\(abandonedID)")
    let work = folder.appending(path: "preparations/\(abandonedID)")
    try FileManager.default.createDirectory(at: abandonedFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    let fingerprints = original.mapValues {
      SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
    }
    let preparing: [String: Any] = [
      "formatVersion": 1, "schema": StudySchemaV1.versionIdentifier.description,
      "phase": "preparing", "candidate": abandonedID, "retained": retainedID,
      "source": fingerprints,
    ]
    let preparation = try PropertyListSerialization.data(
      fromPropertyList: preparing, format: .binary, options: 0)
    try preparation.write(to: folder.appending(path: "store-selection.plist"))
    try preparation.write(to: work.appending(path: "preparation.plist"))
    let main = try #require(original["study.store"])
    if checkpoint == "partial-capture" {
      try write(["study.store": Data(main.prefix(97))], in: work.appending(path: "capture"))
    } else {
      try write(original, in: retainedFolder)
      if checkpoint == "partial-candidate" {
        try write(["study.store": Data(main.prefix(97))], in: abandonedFolder)
      } else {
        try write(original, in: abandonedFolder)
      }
    }
    // These are deterministic restart images, not a claim that a process was killed mid-copy.
    let interrupted = try files(in: folder)
    let selectedSnapshot: StudyGenerationSnapshot
    let selectedBytes: Data
    let selectedID: String
    do {
      let opened = try await StudyStore.openApplication(in: folder)
      #expect(try await opened.generationSnapshot() == expected)
      let selected = try selection(in: folder)
      selectedID = try #require(selected["candidate"] as? String)
      #expect(selected["phase"] as? String == "selected")
      #expect(selected["schema"] as? String == StudySchemaV1.versionIdentifier.description)
      #expect(selected["retained"] as? String == retainedID)
      #expect(selected["source"] as? [String: String] == fingerprints)
      #expect(selectedID != abandonedID && selectedID != retainedID)
      #expect(try family(in: folder) == original)
      #expect(try family(in: retainedFolder) == original)
      let after = try files(in: folder)
      for (path, bytes) in interrupted where path != "store-selection.plist" {
        #expect(after[path] == bytes, "Interrupted artifact changed: \(path)")
      }
      for account in ["first", "second"] {
        let oldReviews = try #require(originalReviews[account])
        #expect(try await opened.pendingReviews(accountID: account) == oldReviews)
        #expect(oldReviews.count == 1 && oldReviews.allSatisfy(\.attempted))
        let oldMaterial = try #require(originalMaterials[account])
        let material = try #require(try await opened.materials(accountID: account).first)
        #expect(material.revision == oldMaterial.revision)
        #expect(material.material == oldMaterial.material && material.issue == oldMaterial.issue)
        #expect(material.pending && material.serverID == oldMaterial.serverID)
        #expect(material.attemptedRevision == oldMaterial.attemptedRevision)
        #expect(material.attemptedMaterial == oldMaterial.attemptedMaterial)
      }
      _ = try await opened.saveMaterial(
        .init(subjectID: 48, meaningNote: "After interrupted preparation 日本"),
        accountID: "first", expectedRevision: nil)
      selectedSnapshot = try await opened.generationSnapshot()
      selectedBytes = try Data(contentsOf: folder.appending(path: "store-selection.plist"))
    }
    let reopened = try await StudyStore.openApplication(in: folder)
    #expect(try await reopened.generationSnapshot() == selectedSnapshot)
    #expect(try Data(contentsOf: folder.appending(path: "store-selection.plist")) == selectedBytes)
    #expect(try selection(in: folder)["candidate"] as? String == selectedID)
    #expect(try family(in: folder) == original)
    #expect(try family(in: retainedFolder) == original)
    #expect(try family(in: seedFolder) == original)
    let afterReopen = try files(in: folder)
    for (path, bytes) in interrupted where path != "store-selection.plist" {
      #expect(afterReopen[path] == bytes, "Interrupted artifact changed after reopen: \(path)")
    }
  }

  @Test(arguments: [
    "missing-selection", "missing-selected-store", "corrupt-selection", "future-selection",
  ])
  func selectedGenerationDamageNeverCreatesANewEmptyGeneration(_ damage: String) async throws {
    let folder = temporaryFolder()
    let sourceFolder = temporaryFolder()
    defer {
      removeFolder(folder)
      removeFolder(sourceFolder)
    }
    let source = try await StudyStore.openApplication(in: sourceFolder)
    defer { withExtendedLifetime(source) {} }
    _ = try await source.importLegacyAccount(
      self.source(username: "first"), sourceID: "source", verifiedAccountID: "first",
      verifiedUsername: "first", credentialID: "credential")
    // Damage a never-opened image; releasing a setup container can checkpoint its WAL asynchronously.
    let seed = try files(in: sourceFolder)
    try FileManager.default.copyItem(at: sourceFolder, to: folder)
    #expect(try files(in: sourceFolder) == seed)
    #expect(try files(in: folder) == seed)
    let selectionURL = folder.appending(path: "store-selection.plist")
    var selected = try selection(in: folder)
    if damage == "missing-selection" {
      try FileManager.default.removeItem(at: selectionURL)
    } else if damage == "missing-selected-store" {
      let candidate = try #require(selected["candidate"] as? String)
      let generation = folder.appending(path: "generations/\(candidate)")
      for name in ["study.store", "study.store-wal", "study.store-shm"] {
        let file = generation.appending(path: name)
        if FileManager.default.fileExists(atPath: file.path) {
          try FileManager.default.removeItem(at: file)
        }
      }
    } else if damage == "future-selection" {
      selected["futureField"] = "unrecognized"
      try PropertyListSerialization.data(fromPropertyList: selected, format: .binary, options: 0)
        .write(to: selectionURL)
    } else {
      try Data("unreadable selection".utf8).write(to: selectionURL)
    }
    let before = try files(in: folder)
    await #expect(throws: (any Error).self) { try await StudyStore.openApplication(in: folder) }
    let after = try files(in: folder)
    let changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
    #expect(after == before, "Changed relative files: \(changed)")
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "study.store").path))
  }

  private func source(username: String) -> LegacyStudyExport {
    var source = LegacyStudyExport(schemaVersion: 15, profile: .init(username: username))
    source.profile.level = 1
    source.profile.maxLevelGranted = 3
    var subject = CatalogSubject(id: 47, kind: .kanji)
    subject.level = 1
    subject.japanese = "一"
    subject.meanings = [.init("One", role: .primary)]
    source.subjects = [subject]
    var assignment = CatalogAssignment(id: 147, subjectID: 47, kind: .kanji)
    assignment.srsStage = 3
    assignment.startedAt = 1
    assignment.availableAt = 1
    source.pendingReviews = [
      .init(
        assignment: assignment,
        submission: .init(
          itemID: 0, subjectID: 47, assignmentID: 147, isLesson: false, meaningWrong: true,
          readingWrong: false, meaningWrongCount: 1, readingWrongCount: 0, createdAt: 100))
    ]
    source.materials = [
      .init(
        serverID: 947, value: .init(subjectID: 47, meaningNote: "Private 日本\u{0}ÿ"), pending: true,
        legacyRevision: 17)
    ]
    return source
  }
  private func temporaryFolder() -> URL {
    URL.temporaryDirectory.appending(path: "store-opening's 日本-\(UUID())")
  }
  private func selection(in folder: URL) throws -> [String: Any] {
    try #require(
      PropertyListSerialization.propertyList(
        from: Data(contentsOf: folder.appending(path: "store-selection.plist")), format: nil)
        as? [String: Any])
  }
  private func family(in folder: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for name in ["study.store", "study.store-wal", "study.store-shm"] {
      let file = folder.appending(path: name)
      if FileManager.default.fileExists(atPath: file.path) {
        result[name] = try Data(contentsOf: file)
      }
    }
    return result
  }
  private func write(_ image: [String: Data], in folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (name, bytes) in image { try bytes.write(to: folder.appending(path: name)) }
  }
  private func files(in folder: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    let root = folder.standardizedFileURL.resolvingSymlinksInPath()
    let prefix = root.path + "/"
    let items = try #require(
      FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
    for case let entry as URL in items {
      let file = entry.standardizedFileURL.resolvingSymlinksInPath()
      if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
        try #require(file.path.hasPrefix(prefix))
        result[String(file.path.dropFirst(prefix.count))] = try Data(contentsOf: file)
      }
    }
    return result
  }
  private func removeFolder(_ folder: URL) {
    // Retained rollback images are intentionally read-only; disposable test cleanup owns them.
    if let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) {
      for case let file as URL in items {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
      }
    }
    try? FileManager.default.removeItem(at: folder)
  }
}
