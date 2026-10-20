import Foundation
import SQLite3
import StudyCore
import Testing

@testable import StudyPersistence

struct StudyStoreOpeningTests {
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
