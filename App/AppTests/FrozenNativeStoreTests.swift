import CryptoKit
import Foundation
import StudyCore
import Testing

@testable import StudyPersistence

private final class FrozenStoreBundle {}

@Suite(.timeLimit(.minutes(1))) struct FrozenNativeStoreTests {
  @Test(arguments: [false, true])
  func frozenStoreAdoptionPreservesEveryFieldAndKeepsNewWritesAfterReopening(
    committedWAL: Bool
  ) async throws {
    let manager = FileManager.default
    let frozen = try #require(
      Bundle(for: FrozenStoreBundle.self).url(forResource: "native-v0-186c1cc3", withExtension: nil)
    )
    .appending(path: "study.store")
    let baseline = frozen.appendingPathExtension("baseline.plist")
    let frozenBytes = try Data(contentsOf: frozen)
    let baselineBytes = try Data(contentsOf: baseline)
    try #require(
      digest(frozenBytes) == "f82be6077bbe12593c95c3ef27b7df576e65dde06965b0a297dbd12be3a3bf94")
    try #require(
      digest(baselineBytes) == "bf3c676dd2ca92219fd1eea95e492c6a1e90aa43f2f0201db16a0f177c7e968b")
    let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
    #expect(manifest.expected.records.count == 38)
    let directory = manager.temporaryDirectory.appending(path: "frozen-native-\(UUID())")
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { remove(directory) }
    let frozenFamily = try family(in: frozen.deletingLastPathComponent())
    for (name, bytes) in frozenFamily { try bytes.write(to: directory.appending(path: name)) }
    let writer: StudyStore?
    let expected: NativeStoreBaseline.State
    if committedWAL {
      let seed = try await StudyStore.open(at: directory.appending(path: "study.store"))
      writer = seed
      #expect(try await seed.nativeBaselineState() == manifest.expected)
      let account = NativeStoreBaseline.accounts[0]
      let saved = try #require(
        try await seed.materials(accountID: account).first { $0.material.subjectID == 42 })
      var material = saved.material
      material.meaningNote += "\nCommitted only in the iPhone WAL \u{0}🐰"
      _ = try await seed.saveMaterial(
        material, accountID: account, expectedRevision: saved.revision)
      expected = try await seed.nativeBaselineState()
      #expect(expected != manifest.expected && expected.records.count == 38)
      for (before, after) in zip(manifest.expected.records, expected.records)
      where before.model != "MaterialRecord" || before.identity != "\(account)/42" {
        #expect(after == before, "Unexpected WAL seed edit to \(before.model)/\(before.identity)")
      }
      let committed = try #require(
        try await seed.materials(accountID: account).first { $0.material.subjectID == 42 })
      #expect(committed.material == material && committed.revision != saved.revision)
    } else {
      writer = nil
      expected = manifest.expected
    }
    // Keep the old writer quiet and alive so closing it cannot checkpoint/remove the WAL.
    defer { withExtendedLifetime(writer) {} }
    let original = try family(in: directory)
    if committedWAL {
      #expect(try #require(original["study.store-wal"]).count > 0)
      #expect(original["study.store"] == frozenBytes)
    }
    let selectionURL = directory.appending(path: "store-selection.plist")
    let selectionBytes: Data
    let retained: URL
    do {
      let first = try await StudyStore.openApplication(in: directory)
      #expect(try await first.nativeBaselineState() == expected)
      selectionBytes = try Data(contentsOf: selectionURL)
      let selection = try #require(
        PropertyListSerialization.propertyList(from: selectionBytes, format: nil) as? [String: Any])
      #expect(selection["phase"] as? String == "selected")
      let candidate = try #require(selection["candidate"] as? String)
      let retainedID = try #require(selection["retained"] as? String)
      #expect(UUID(uuidString: candidate) != nil && UUID(uuidString: retainedID) != nil)
      #expect(candidate != retainedID)
      retained = directory.appending(path: "generations/\(retainedID)")
      #expect(try family(in: directory) == original)
      #expect(try family(in: retained) == original)
    }
    let edited: NativeStoreBaseline.State
    do {
      let reopened = try await StudyStore.openApplication(in: directory)
      #expect(try await reopened.nativeBaselineState() == expected)
      #expect(try Data(contentsOf: selectionURL) == selectionBytes)
      let account = NativeStoreBaseline.accounts[0]
      let saved = try #require(
        try await reopened.materials(accountID: account).first { $0.material.subjectID == 42 })
      var material = saved.material
      material.meaningNote += "\nFrozen iPhone adoption edit \u{0}🐰"
      _ = try await reopened.saveMaterial(
        material, accountID: account, expectedRevision: saved.revision)
      edited = try await reopened.nativeBaselineState()
      #expect(edited != expected && edited.records.count == 38)
      #expect(edited.schema == expected.schema)
      #expect(edited.schemaVersion == expected.schemaVersion)
      for (before, after) in zip(expected.records, edited.records)
      where before.model != "MaterialRecord" || before.identity != "\(account)/42" {
        #expect(after == before, "Unexpected edit to \(before.model)/\(before.identity)")
      }
      let changed = try #require(
        try await reopened.materials(accountID: account).first { $0.material.subjectID == 42 })
      #expect(changed.material == material && changed.revision != saved.revision)
    }
    do {
      let reopened = try await StudyStore.openApplication(in: directory)
      #expect(try await reopened.nativeBaselineState() == edited)
      #expect(try Data(contentsOf: selectionURL) == selectionBytes)
      #expect(try family(in: directory) == original)
      #expect(try family(in: retained) == original)
    }
    #expect(try Data(contentsOf: frozen) == frozenBytes)
    #expect(try Data(contentsOf: baseline) == baselineBytes)
    #expect(try family(in: frozen.deletingLastPathComponent()) == frozenFamily)
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func family(in directory: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for name in ["study.store", "study.store-wal", "study.store-shm"] {
      let url = directory.appending(path: name)
      if FileManager.default.fileExists(atPath: url.path) {
        result[name] = try Data(contentsOf: url)
      }
    }
    return result
  }

  private func remove(_ directory: URL) {
    let manager = FileManager.default
    if let entries = manager.enumerator(at: directory, includingPropertiesForKeys: nil) {
      for case let entry as URL in entries {
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: entry.path)
      }
    }
    try? manager.removeItem(at: directory)
  }
}
