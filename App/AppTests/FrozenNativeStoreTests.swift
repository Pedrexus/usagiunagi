import CoreData
import CryptoKit
import Darwin
import Foundation
import SQLite3
import StudyCore
import Testing

@testable import StudyPersistence

private final class FrozenStoreBundle {}

@Suite(.timeLimit(.minutes(1))) struct FrozenNativeStoreTests {
  enum AdoptionCase: String, CaseIterable, Sendable {
    case control, payloadMalformed, cacheMissing, metadataMalformed
  }
  private enum StoreImage { case original, selected }
  private struct AdoptionSelection: Decodable, Equatable {
    let formatVersion: Int
    let schema: String
    let phase: String
    let candidate: UUID
    let retained: UUID
    let source: [String: String]
    let validation: String?
  }

  private enum RestartPhase: String {
    case seed, reopen, seedAbrupt, reopenAbrupt
    case seedVerification, reopenVerification, seedCandidate, reopenCandidate
    var abrupt: Bool { self == .seedAbrupt || self == .reopenAbrupt }
    var seeds: Bool { [.seed, .seedAbrupt, .seedVerification, .seedCandidate].contains(self) }
    var opening: OpeningPoint? {
      switch self {
      case .seedVerification, .reopenVerification: .verification
      case .seedCandidate, .reopenCandidate: .candidate
      default: nil
      }
    }
  }
  private enum OpeningPoint: String, Codable { case verification, candidate }
  private struct OpeningRestartReceipt: Codable {
    let id: UUID
    let producerPID: Int32
    let point: OpeningPoint
    let files: [String: Data]
  }
  private struct RestartReceipt: Codable {
    let version: Int
    let id: UUID
    let producerPID: Int32
    let abrupt: Bool
    let expected: NativeStoreBaseline.State
    let selection: Data
    let main: Data?
    let wal: Data?
  }
  private let restartTimestamp: Int64 = 2_000_000_000
  private var restartSubmission: StudyReviewSubmission {
    .init(
      itemID: 0, subjectID: 42, assignmentID: 142, isLesson: false,
      meaningWrong: true, readingWrong: false, meaningWrongCount: 1, readingWrongCount: 0,
      createdAt: restartTimestamp)
  }

  @Test(
    .enabled(
      if: ProcessInfo.processInfo.environment["USAGI_NATIVE_RESTART_PHASE"] != nil,
      "Requires Mainboard's two-process native-store-restart task"))
  func persistedStoreReopensInAnotherTestHost() async throws {
    let process = ProcessInfo.processInfo
    try #require(process.arguments.contains("--review-fixture"))
    let phase = try #require(
      process.environment["USAGI_NATIVE_RESTART_PHASE"].flatMap(RestartPhase.init(rawValue:)))
    let id = try #require(
      process.environment["USAGI_NATIVE_RESTART_ID"].flatMap(UUID.init(uuidString:)))
    let manager = FileManager.default
    let root = URL.applicationSupportDirectory.appending(path: "NativeStoreRestartFixtures")
    if phase.seeds {
      try manager.createDirectory(
        at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    let rootInfo = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    try #require(rootInfo.isDirectory == true && rootInfo.isSymbolicLink == false)
    let directory = root.appending(path: "frozen-native-\(id)")
    let receiptURL = root.appending(path: "\(id).plist")
    let frozen = try frozenURL()
    let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
    let original = try family(in: frozen.deletingLastPathComponent())
    if let point = phase.opening {
      try await interruptedOpening(
        point, seeds: phase.seeds, id: id, directory: directory, receiptURL: receiptURL,
        original: original, expected: manifest.expected)
      try #require(try family(in: frozen.deletingLastPathComponent()) == original)
      return
    }
    let marker = "\nFresh iPhone test host \(id) \u{0}🐰"
    let accountID = NativeStoreBaseline.accounts[0]
    let now = Date(timeIntervalSince1970: Double(restartTimestamp))
    switch phase {
    case .seed, .seedAbrupt:
      try #require(
        !manager.fileExists(atPath: directory.path) && !manager.fileExists(atPath: receiptURL.path))
      try manager.createDirectory(at: directory, withIntermediateDirectories: false)
      for (name, bytes) in original { try bytes.write(to: directory.appending(path: name)) }
      let opened = try await StudyStore.openApplication(in: directory)
      try #require(try await opened.nativeBaselineState() == manifest.expected)
      let locations = try selectedURLs(in: directory)
      let mainURL = locations.selected.appending(path: "study.store")
      let walURL = locations.selected.appending(path: "study.store-wal")
      let mainBefore = phase.abrupt ? try Data(contentsOf: mainURL) : nil
      let walBefore =
        phase.abrupt && manager.fileExists(atPath: walURL.path) ? try Data(contentsOf: walURL) : nil
      var expectedAccount = try #require(try await opened.accountState(accountID: accountID))
      let progress = try #require(expectedAccount.progress.firstIndex { $0.subjectID == 42 })
      expectedAccount.progress[progress].lastMistakeAt = restartTimestamp
      let saved = try #require(
        try await opened.materials(accountID: accountID).first {
          $0.material.subjectID == 42
        })
      var material = saved.material
      material.meaningNote += marker
      _ = try await opened.saveMaterial(
        material, accountID: accountID, expectedRevision: saved.revision)
      var review = try await opened.openReviews(accountID: accountID, now: now)
      try #require(review.subject?.id == 42 && review.saved.session.currentDecision == .incorrect)
      let originalSession = review.saved.session
      review = try await opened.changeReview(
        .advance, accountID: accountID, expectedRevision: review.saved.revision, now: now)
      for kind in [StudyQuestionKind.meaning, .reading] {
        let question = try #require(review.question)
        try #require(question.kind == kind)
        let answered = try await opened.answerReview(
          kind == .meaning ? "Cat 0" : "ねこ", question: question, accountID: accountID,
          expectedRevision: review.saved.revision, now: now)
        try #require(answered.grade == .precise)
        review = answered.state
      }
      try #require(review.question == nil && review.success?.subjectFinished == true)
      try #require(review.saved.session.completedSubmissions == [restartSubmission])
      try #require(review.saved.session.options == originalSession.options)
      try #require(review.saved.session.queuedIDs == originalSession.queuedIDs)
      try #require(review.saved.session.wrappingUp == originalSession.wrappingUp)
      try #require(Set(review.saved.session.items.keys) == Set(originalSession.items.keys))
      for (key, item) in originalSession.items where key != restartSubmission.itemID {
        let retainedItem = try #require(review.saved.session.items[key])
        try #require(
          try NativeStoreBaseline.encoded(item) == NativeStoreBaseline.encoded(retainedItem))
      }
      try #require(
        review.saved.session.tasksAnswered == 3 && review.saved.session.tasksAnsweredCorrectly == 2)
      let actualAccount = try #require(try await opened.accountState(accountID: accountID))
      try #require(
        try NativeStoreBaseline.encoded(actualAccount)
          == NativeStoreBaseline.encoded(expectedAccount))
      let expected = try await opened.nativeBaselineState()
      try #require(expected.records.count == manifest.expected.records.count + 1)
      try #require(expected.schema == manifest.expected.schema)
      try #require(expected.schemaVersion == manifest.expected.schemaVersion)
      for before in manifest.expected.records
      where
        !(before.accountID == accountID
        && (before.model == "AccountRecord" || before.model == "SessionRecord"
          || (before.model == "MaterialRecord" && before.identity == "\(accountID)/42")))
      {
        try #require(
          expected.records.first { $0.model == before.model && $0.identity == before.identity }
            == before)
      }
      try #require(
        try family(in: directory) == original && family(in: locations.retained) == original)
      let main = phase.abrupt ? try Data(contentsOf: mainURL) : nil
      let wal = phase.abrupt ? try Data(contentsOf: walURL) : nil
      if phase.abrupt {
        try #require(main == mainBefore)
        try #require(wal?.isEmpty == false && wal != walBefore)
      }
      let receipt = RestartReceipt(
        version: 3, id: id, producerPID: process.processIdentifier, abrupt: phase.abrupt,
        expected: expected, selection: locations.selector, main: main, wal: wal)
      try PropertyListEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
      if phase.abrupt {
        let message = "NATIVE WAL READY FOR ABRUPT EXIT: \(id), PID \(process.processIdentifier)\n"
        try FileHandle.standardError.write(contentsOf: Data(message.utf8))
        withExtendedLifetime(opened) { _exit(86) }
      }
      print("NATIVE RESTART SEEDED: \(id), PID \(process.processIdentifier)")
    case .reopen, .reopenAbrupt:
      let info = try receiptURL.resourceValues(
        forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      try #require(info.isRegularFile == true && info.isSymbolicLink == false)
      try #require((info.fileSize ?? 0) > 0 && (info.fileSize ?? 0) <= 16 * 1024 * 1024)
      let receipt = try PropertyListDecoder().decode(
        RestartReceipt.self, from: Data(contentsOf: receiptURL))
      try #require(receipt.version == 3 && receipt.id == id && receipt.abrupt == phase.abrupt)
      try #require(receipt.producerPID > 0 && receipt.producerPID != process.processIdentifier)
      let directoryInfo = try directory.resourceValues(forKeys: [
        .isDirectoryKey, .isSymbolicLinkKey,
      ])
      try #require(directoryInfo.isDirectory == true && directoryInfo.isSymbolicLink == false)
      let locations = try selectedURLs(in: directory)
      try #require(locations.selector == receipt.selection)
      try #require(
        try family(in: directory) == original && family(in: locations.retained) == original)
      if phase.abrupt {
        let main = try #require(receipt.main)
        let wal = try #require(receipt.wal)
        try #require(!main.isEmpty && !wal.isEmpty)
        try #require(
          try Data(contentsOf: locations.selected.appending(path: "study.store")) == main)
        try #require(
          try Data(contentsOf: locations.selected.appending(path: "study.store-wal")) == wal)
      }
      do {
        let opened = try await StudyStore.openApplication(in: directory)
        try #require(try await opened.nativeBaselineState() == receipt.expected)
        let saved = try #require(
          try await opened.materials(accountID: accountID).first {
            $0.material.subjectID == 42
          })
        try #require(saved.material.meaningNote.hasSuffix(marker))
        for _ in 0..<2 {
          let resumed = try await opened.openReviews(accountID: accountID, now: now)
          try #require(resumed.question == nil && resumed.success == nil)
          try #require(resumed.saved.session.completedSubmissions == [restartSubmission])
          let pending = try #require(
            try await opened.pendingReviews(accountID: accountID).first { $0.subjectID == 42 })
          try #require(pending.submission == restartSubmission && !pending.attempted)
          try #require(pending.issue == nil)
          try #require(try await opened.nativeBaselineState() == receipt.expected)
        }
      }
      try #require(try selectedURLs(in: directory).selector == receipt.selection)
      try #require(
        try family(in: directory) == original && family(in: locations.retained) == original)
      print(
        "NATIVE RESTART REOPENED: \(id), PID \(receipt.producerPID) → \(process.processIdentifier), abrupt \(phase.abrupt), 39 exact records including completed answer"
      )
      remove(directory)
      try #require(!manager.fileExists(atPath: directory.path))
      try manager.removeItem(at: receiptURL)
    case .seedVerification, .reopenVerification, .seedCandidate, .reopenCandidate:
      Issue.record("Opening interruption phase did not use its dedicated path")
    }
    try #require(try family(in: frozen.deletingLastPathComponent()) == original)
  }

  private func interruptedOpening(
    _ point: OpeningPoint, seeds: Bool, id: UUID, directory: URL, receiptURL: URL,
    original: [String: Data], expected: NativeStoreBaseline.State
  ) async throws {
    let manager = FileManager.default
    let process = ProcessInfo.processInfo
    let selectorURL = directory.appending(path: "store-selection.plist")
    if seeds {
      try #require(
        !manager.fileExists(atPath: directory.path) && !manager.fileExists(atPath: receiptURL.path))
      try manager.createDirectory(at: directory, withIntermediateDirectories: false)
      for (name, bytes) in original { try bytes.write(to: directory.appending(path: name)) }
      let prefix = directory.resolvingSymlinksInPath().path + "/"
      let center = NotificationCenter.default
      let observer = center.addObserver(
        forName: .NSPersistentStoreCoordinatorStoresDidChange, object: nil, queue: nil
      ) { notification in
        let added = notification.userInfo?[NSAddedPersistentStoresKey] as? [NSPersistentStore] ?? []
        let paths = added.compactMap { $0.url?.resolvingSymlinksInPath().path }
        guard
          paths.contains(where: {
            $0.hasPrefix(prefix + (point == .verification ? "preparations/" : "generations/"))
              && $0.hasSuffix(point == .verification ? "/verification/study.store" : "/study.store")
          })
        else { return }
        do {
          let files = try artifacts(in: directory)
          let selector = try #require(files["store-selection.plist"])
          let selection = try PropertyListDecoder().decode(AdoptionSelection.self, from: selector)
          try #require(selection.phase == "preparing" && selection.validation == nil)
          let path =
            point == .verification
            ? "preparations/\(selection.candidate)/verification/study.store"
            : "generations/\(selection.candidate)/study.store"
          try #require(paths.contains(prefix + path))
          try #require(selection.source == original.mapValues(digest))
          try #require(try family(in: directory) == original)
          try #require(
            try family(in: directory.appending(path: "generations/\(selection.retained)"))
              == original)
          let receipt = OpeningRestartReceipt(
            id: id, producerPID: process.processIdentifier, point: point, files: files)
          try PropertyListEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
          let message =
            "NATIVE OPENING READY FOR ABRUPT EXIT: \(id), \(point.rawValue), PID \(process.processIdentifier)\n"
          try FileHandle.standardError.write(contentsOf: Data(message.utf8))
          _exit(86)
        } catch {
          let message = "NATIVE OPENING CHECKPOINT FAILED: \(error)\n"
          try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
          _exit(87)
        }
      }
      defer { center.removeObserver(observer) }
      _ = try await StudyStore.openApplication(in: directory)
      Issue.record("The \(point.rawValue) store opened without the required process interruption")
      return
    }
    let info = try receiptURL.resourceValues(
      forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    try #require(info.isRegularFile == true && info.isSymbolicLink == false)
    try #require((info.fileSize ?? 0) > 0 && (info.fileSize ?? 0) <= 64 * 1024 * 1024)
    let receipt = try PropertyListDecoder().decode(
      OpeningRestartReceipt.self, from: Data(contentsOf: receiptURL))
    try #require(receipt.id == id && receipt.point == point)
    try #require(receipt.producerPID > 0 && receipt.producerPID != process.processIdentifier)
    try #require(try artifacts(in: directory) == receipt.files)
    let selector = try #require(receipt.files["store-selection.plist"])
    let previous = try PropertyListDecoder().decode(AdoptionSelection.self, from: selector)
    try #require(previous.phase == "preparing" && previous.validation == nil)
    try #require(previous.source == original.mapValues(digest))
    let abandoned = "generations/\(previous.candidate)/study.store"
    try #require(
      point == .candidate
        ? receipt.files[abandoned]?.isEmpty == false : receipt.files[abandoned] == nil)
    do {
      let reopened = try await StudyStore.openApplication(in: directory)
      try #require(try await reopened.nativeBaselineState() == expected)
    }
    let selectedBytes = try Data(contentsOf: selectorURL)
    let selected = try PropertyListDecoder().decode(AdoptionSelection.self, from: selectedBytes)
    try #require(selected.phase == "selected" && selected.validation?.count == 64)
    try #require(selected.retained == previous.retained && selected.candidate != previous.candidate)
    try #require(selected.source == previous.source)
    do {
      let reopened = try await StudyStore.openApplication(in: directory)
      try #require(try await reopened.nativeBaselineState() == expected)
    }
    try #require(try Data(contentsOf: selectorURL) == selectedBytes)
    let after = try artifacts(in: directory)
    for (path, bytes) in receipt.files where path != "store-selection.plist" {
      try #require(after[path] == bytes)
    }
    try #require(try family(in: directory) == original)
    try #require(
      try family(in: directory.appending(path: "generations/\(selected.retained)")) == original)
    print(
      "NATIVE OPENING REOPENED: \(id), \(point.rawValue), PID \(receipt.producerPID) → \(process.processIdentifier), 38 exact records, abandoned files unchanged"
    )
    remove(directory)
    try #require(!manager.fileExists(atPath: directory.path))
    try manager.removeItem(at: receiptURL)
  }

  @Test(arguments: AdoptionCase.allCases)
  func firstAdoptionDamageKeepsEveryImageAcrossRetriesAndRefusesSourceChanges(
    _ test: AdoptionCase
  ) async throws {
    let manager = FileManager.default
    let frozen = try frozenURL()
    let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
    let frozenFamily = try family(in: frozen.deletingLastPathComponent())
    let baseline = try Data(contentsOf: frozen.appendingPathExtension("baseline.plist"))
    let directory = manager.temporaryDirectory.appending(path: "frozen-native-\(UUID())")
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { remove(directory) }
    for (name, bytes) in frozenFamily { try bytes.write(to: directory.appending(path: name)) }
    let source = directory.appending(path: "study.store")
    switch test {
    case .control: break
    case .payloadMalformed:
      try mutate(
        .init(field: "AccountRecord.state", key: "profile", damage: .truncated),
        store: source, issue: Data(), image: .original)
    case .cacheMissing: try mutateMetadata(.cacheMissing, store: source, image: .original)
    case .metadataMalformed: try mutateMetadata(.metadataMalformed, store: source, image: .original)
    }
    let original = try family(in: directory)
    let hashes = original.mapValues(digest)
    let selectorURL = directory.appending(path: "store-selection.plist")
    var previous: AdoptionSelection?
    var previousBytes: Data?
    for _ in 0..<2 {
      let before = try artifacts(in: directory)
      if test == .control {
        let opened = try await StudyStore.openApplication(in: directory)
        #expect(try await opened.nativeBaselineState() == manifest.expected)
      } else {
        do {
          _ = try await StudyStore.openApplication(in: directory)
          Issue.record("Damaged first-adoption input opened: \(test.rawValue)")
        } catch is CancellationError {
          throw CancellationError()
        } catch StudyStoreOpeningError.alreadyOpen {
          throw StudyStoreOpeningError.alreadyOpen
        } catch StudyStoreOpeningError.sourceChanged {
          throw StudyStoreOpeningError.sourceChanged
        } catch {
          let failure = error as NSError
          print("ADOPTION REFUSED: \(test.rawValue), \(failure.domain)/\(failure.code)")
        }
      }
      let bytes = try Data(contentsOf: selectorURL)
      let selected = try PropertyListDecoder().decode(AdoptionSelection.self, from: bytes)
      #expect(selected.formatVersion == 1)
      #expect(selected.schema == StudySchemaV1.versionIdentifier.description)
      #expect(selected.phase == (test == .control ? "selected" : "preparing"))
      #expect(selected.candidate != selected.retained && selected.source == hashes)
      #expect(test == .control ? selected.validation?.count == 64 : selected.validation == nil)
      #expect(try family(in: directory) == original)
      #expect(
        try family(in: directory.appending(path: "generations/\(selected.retained)")) == original)
      if let previous {
        #expect(selected.retained == previous.retained)
        if test == .control {
          #expect(selected == previous && bytes == previousBytes)
        } else {
          #expect(selected.candidate != previous.candidate)
          #expect(
            try directory.appending(path: "generations/\(previous.candidate)")
              .resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        }
      }
      let after = try artifacts(in: directory)
      let allowed =
        test == .control
        ? Set(previous.map { ["generations/\($0.candidate)/study.store-shm"] } ?? [])
        : ["store-selection.plist"]
      for (path, data) in before where !allowed.contains(path) { #expect(after[path] == data) }
      if test == .control, previous != nil {
        #expect(Set(after.keys).subtracting(before.keys).isSubset(of: allowed))
      }
      previous = selected
      previousBytes = bytes
    }
    if test != .control {
      // A repaired/replaced original is a different source, not permission to discard its capture.
      let before = try artifacts(in: directory)
      for name in ["study.store", "study.store-wal", "study.store-shm"] {
        let file = directory.appending(path: name)
        if let data = frozenFamily[name] {
          try data.write(to: file)
        } else if manager.fileExists(atPath: file.path) {
          try manager.removeItem(at: file)
        }
      }
      do {
        _ = try await StudyStore.openApplication(in: directory)
        Issue.record("Changed first-adoption source was silently accepted")
      } catch StudyStoreOpeningError.sourceChanged {}
      let after = try artifacts(in: directory)
      let allowed = Set([
        "store-selection.plist", "study.store", "study.store-wal", "study.store-shm",
      ])
      for (path, data) in before where !allowed.contains(path) { #expect(after[path] == data) }
      #expect(try family(in: directory) == frozenFamily)
      let selection = try PropertyListDecoder().decode(
        AdoptionSelection.self, from: Data(contentsOf: selectorURL))
      #expect(selection.phase == "preparing" && selection.source == hashes)
      #expect(
        selection.retained == previous?.retained && selection.candidate != previous?.candidate)
    }
    #expect(try family(in: frozen.deletingLastPathComponent()) == frozenFamily)
    #expect(try Data(contentsOf: frozen.appendingPathExtension("baseline.plist")) == baseline)
  }

  enum PermissionCase: String, CaseIterable, Sendable {
    case newLease, selection, preparations, generations
  }

  @Test(arguments: PermissionCase.allCases)
  func unwritableAdoptionPreservesEveryAttemptAndRecoversAfterPermissionRestoration(
    _ test: PermissionCase
  ) async throws {
    let manager = FileManager.default
    let frozen = try frozenURL()
    let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
    let frozenFamily = try family(in: frozen.deletingLastPathComponent())
    let directory = manager.temporaryDirectory.appending(path: "frozen-native-\(UUID())")
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let blocked: URL
    switch test {
    case .newLease, .selection: blocked = directory
    case .preparations, .generations:
      blocked = directory.appending(path: test.rawValue)
      try manager.createDirectory(at: blocked, withIntermediateDirectories: true)
    }
    defer {
      try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path)
      remove(directory)
    }
    for (name, bytes) in frozenFamily { try bytes.write(to: directory.appending(path: name)) }
    if test == .selection {
      try Data().write(to: directory.appending(path: "store-owner.lock"))
    }
    try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: blocked.path)
    let selectorURL = directory.appending(path: "store-selection.plist")
    var previous: AdoptionSelection?
    for _ in 0..<2 {
      let before = try artifacts(in: directory)
      do {
        _ = try await StudyStore.openApplication(in: directory)
        Issue.record("Unwritable first-adoption input opened: \(test.rawValue)")
      } catch {
        let error = error as NSError
        #expect(error.domain == (test == .newLease ? NSPOSIXErrorDomain : NSCocoaErrorDomain))
        #expect(
          error.code
            == (test == .newLease
              ? Int(POSIXErrorCode.EACCES.rawValue)
              : CocoaError.Code.fileWriteNoPermission.rawValue))
      }
      let attributes = try manager.attributesOfItem(atPath: blocked.path)
      #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o500)
      #expect(try family(in: directory) == frozenFamily)
      let after = try artifacts(in: directory)
      for (path, bytes) in before where path != "store-selection.plist" {
        #expect(after[path] == bytes)
      }
      switch test {
      case .newLease, .selection:
        #expect(after == before)
        #expect(!manager.fileExists(atPath: selectorURL.path))
      case .preparations, .generations:
        let selection = try PropertyListDecoder().decode(
          AdoptionSelection.self, from: Data(contentsOf: selectorURL))
        #expect(selection.phase == "preparing" && selection.validation == nil)
        #expect(selection.source == frozenFamily.mapValues(digest))
        #expect(selection.candidate != selection.retained)
        if let previous {
          #expect(selection.retained == previous.retained)
          #expect(selection.candidate != previous.candidate)
        }
        previous = selection
      }
    }
    let beforeRetry = try artifacts(in: directory)
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path)
    do {
      let opened = try await StudyStore.openApplication(in: directory)
      #expect(try await opened.nativeBaselineState() == manifest.expected)
    }
    let selection = try PropertyListDecoder().decode(
      AdoptionSelection.self, from: Data(contentsOf: selectorURL))
    #expect(selection.phase == "selected" && selection.validation?.count == 64)
    #expect(selection.source == frozenFamily.mapValues(digest))
    if let previous {
      #expect(selection.retained == previous.retained && selection.candidate != previous.candidate)
    }
    let afterRetry = try artifacts(in: directory)
    for (path, bytes) in beforeRetry where path != "store-selection.plist" {
      #expect(afterRetry[path] == bytes)
    }
    #expect(try family(in: directory) == frozenFamily)
    #expect(
      try family(in: directory.appending(path: "generations/\(selection.retained)")) == frozenFamily
    )
    #expect(try family(in: frozen.deletingLastPathComponent()) == frozenFamily)
  }

  enum MetadataCase: String, CaseIterable, Sendable {
    case control, metadataMissing, metadataMalformed, metadataMissingHashes
    case cacheMissing, cacheMalformed
    var table: String {
      self == .cacheMissing || self == .cacheMalformed ? "Z_MODELCACHE" : "Z_METADATA"
    }
    var column: String { table == "Z_METADATA" ? "Z_PLIST" : "Z_CONTENT" }
    var removesRow: Bool { self == .metadataMissing || self == .cacheMissing }
  }
  private struct MetadataRow: Equatable {
    let id: Int64
    let uuid: String?
    let data: Data
  }

  @Test(arguments: MetadataCase.allCases)
  func selectedMetadataDamageNeverRepairsOrReplacesSavedData(_ test: MetadataCase) async throws {
    let manager = FileManager.default
    let frozen = try frozenURL()
    let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
    let frozenFamily = try family(in: frozen.deletingLastPathComponent())
    let baseline = try Data(contentsOf: frozen.appendingPathExtension("baseline.plist"))
    let directory = manager.temporaryDirectory.appending(path: "frozen-native-\(UUID())")
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { remove(directory) }
    for (name, bytes) in frozenFamily { try bytes.write(to: directory.appending(path: name)) }
    do {
      let intact = try await StudyStore.openApplication(in: directory)
      #expect(try await intact.nativeBaselineState() == manifest.expected)
    }
    let (selector, selected, retained) = try selectedURLs(in: directory)
    let original = try family(in: directory)
    let retainedFamily = try family(in: retained)
    let generations = directory.appending(path: "generations")
    let generationNames = try manager.contentsOfDirectory(atPath: generations.path).sorted()
    if test != .control {
      try mutateMetadata(test, store: selected.appending(path: "study.store"))
    }
    let damagedFamily = try family(in: selected).filter { $0.key != "study.store-shm" }
    for _ in 0..<2 {
      if test == .control {
        let opened = try await StudyStore.openApplication(in: directory)
        #expect(try await opened.nativeBaselineState() == manifest.expected)
      } else {
        do {
          _ = try await StudyStore.openApplication(in: directory)
          Issue.record("Damaged metadata opened: \(test.rawValue)")
        } catch is CancellationError {
          throw CancellationError()
        } catch StudyStoreOpeningError.alreadyOpen {
          throw StudyStoreOpeningError.alreadyOpen
        } catch {
          let failure = error as NSError
          print("METADATA REFUSED: \(test.rawValue), \(failure.domain)/\(failure.code)")
        }
      }
      #expect(try family(in: directory) == original)
      #expect(try family(in: retained) == retainedFamily)
      #expect(try Data(contentsOf: directory.appending(path: "store-selection.plist")) == selector)
      #expect(try manager.contentsOfDirectory(atPath: generations.path).sorted() == generationNames)
      #expect(try family(in: selected).filter { $0.key != "study.store-shm" } == damagedFamily)
    }
    #expect(try family(in: frozen.deletingLastPathComponent()) == frozenFamily)
    #expect(try Data(contentsOf: frozen.appendingPathExtension("baseline.plist")) == baseline)
  }

  struct PayloadCase: Sendable, CustomStringConvertible {
    enum Damage: String, Sendable { case mistyped, truncated, null, valid }
    let field: String
    let key: String
    let damage: Damage
    var description: String { field + "." + damage.rawValue }
    var table: String { "Z" + field.split(separator: ".")[0].uppercased() }
    var column: String { "Z" + field.split(separator: ".")[1].uppercased() }
  }
  static let payloadCases: [PayloadCase] = {
    // Independent, closed test whitelist: all fifteen persisted Codable paths in the frozen store.
    let fields: [(path: String, key: String, optional: Bool)] = [
      ("SnapshotRecord.snapshot", "currentLevel", false),
      ("SessionRecord.session", "isPractice", false),
      ("ReviewRecord.submission", "subjectID", false),
      ("ReviewRecord.originalItem", "subjectID", false),
      ("ReviewRecord.originalAssignment", "subjectID", true),
      ("ReviewRecord.issue", "reason", true),
      ("ImportReceipt.handoff", "sourceID", true),
      ("CatalogRecord.subject", "id", false),
      ("AssignmentRecord.assignment", "subjectID", false),
      ("AccountRecord.state", "profile", false),
      ("MaterialRecord.issue", "reason", true),
      ("MaterialRecord.attemptedMaterial", "subjectID", true),
      ("MaterialRecord.recoveryBaseline", "remote", true),
      ("MaterialRecord.material", "subjectID", false),
      ("ArchivedReviewRecord.answer", "id", false),
    ]
    return fields.flatMap { field in
      (field.optional ? [PayloadCase.Damage.mistyped] : [.mistyped, .null]).map {
        PayloadCase(field: field.path, key: field.key, damage: $0)
      }
    } + [
      .init(field: "AccountRecord.state", key: "profile", damage: .truncated),
      .init(field: "MaterialRecord.issue", key: "reason", damage: .truncated),
      .init(field: "ReviewRecord.issue", key: "reason", damage: .valid),
    ]
  }()

  @Test(arguments: Self.payloadCases)
  func selectedPayloadDamageRefusesSafelyAndPreservesAllStoreImages(
    _ test: PayloadCase
  ) async throws {
    #expect(Self.payloadCases.count == 27)
    let manager = FileManager.default
    let frozen = try frozenURL()
    let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
    let frozenFamily = try family(in: frozen.deletingLastPathComponent())
    let baseline = try Data(contentsOf: frozen.appendingPathExtension("baseline.plist"))
    let directory = manager.temporaryDirectory.appending(path: "frozen-native-\(UUID())")
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { remove(directory) }
    for (name, bytes) in frozenFamily { try bytes.write(to: directory.appending(path: name)) }
    do {
      let intact = try await StudyStore.openApplication(in: directory)
      #expect(try await intact.nativeBaselineState() == manifest.expected)
    }
    let (selector, selected, retained) = try selectedURLs(in: directory)
    let selectorURL = directory.appending(path: "store-selection.plist")
    let generations = directory.appending(path: "generations")
    let original = try family(in: directory)
    let retainedFamily = try family(in: retained)
    let generationNames = try manager.contentsOfDirectory(atPath: generations.path).sorted()
    let issue = try #require(
      manifest.expected.records.first {
        $0.model == "MaterialRecord" && $0.fields["issue"] != Data("null".utf8)
      }?.fields["issue"])
    _ = try JSONDecoder().decode(StudyUploadIssue.self, from: issue)
    try mutate(test, store: selected.appending(path: "study.store"), issue: issue)
    let damagedFamily = try family(in: selected).filter { $0.key != "study.store-shm" }
    var validControl: NativeStoreBaseline.State?
    for _ in 0..<2 {
      if test.damage == .valid {
        let opened = try await StudyStore.openApplication(in: directory)
        let actual = try await opened.nativeBaselineState()
        if let validControl {
          #expect(actual == validControl)
        } else {
          #expect(actual.schema == manifest.expected.schema)
          #expect(actual.schemaVersion == manifest.expected.schemaVersion)
          try #require(actual.records.count == manifest.expected.records.count)
          let changes = zip(manifest.expected.records, actual.records).filter { $0 != $1 }
          try #require(changes.count == 1)
          let (before, after) = try #require(changes.first)
          #expect(before.model == "ReviewRecord" && after.model == before.model)
          #expect(after.identity == before.identity && after.accountID == before.accountID)
          #expect(before.fields["issue"] == Data("null".utf8) && after.fields["issue"] == issue)
          #expect(
            before.fields.filter { $0.key != "issue" }
              == after.fields.filter { $0.key != "issue" })
          validControl = actual
        }
      } else {
        do {
          _ = try await StudyStore.openApplication(in: directory)
          Issue.record("Damaged selected payload opened: \(test)")
        } catch StudyStoreOpeningError.invalidGeneration {}
      }
      #expect(try family(in: directory) == original)
      #expect(try family(in: retained) == retainedFamily)
      #expect(try Data(contentsOf: selectorURL) == selector)
      #expect(try manager.contentsOfDirectory(atPath: generations.path).sorted() == generationNames)
      #expect(try family(in: selected).filter { $0.key != "study.store-shm" } == damagedFamily)
    }
    #expect(try family(in: frozen.deletingLastPathComponent()) == frozenFamily)
    #expect(try Data(contentsOf: frozen.appendingPathExtension("baseline.plist")) == baseline)
  }

  @Test(arguments: [false, true])
  func frozenStoreAdoptionPreservesEveryFieldAndKeepsNewWritesAfterReopening(
    committedWAL: Bool
  ) async throws {
    let manager = FileManager.default
    let frozen = try frozenURL()
    let baseline = frozen.appendingPathExtension("baseline.plist")
    let frozenBytes = try Data(contentsOf: frozen)
    let baselineBytes = try Data(contentsOf: baseline)
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

  private func frozenURL() throws -> URL {
    let url = try #require(
      Bundle(for: FrozenStoreBundle.self).url(forResource: "native-v0-186c1cc3", withExtension: nil)
    ).appending(path: "study.store")
    try #require(
      digest(Data(contentsOf: url))
        == "f82be6077bbe12593c95c3ef27b7df576e65dde06965b0a297dbd12be3a3bf94")
    try #require(
      digest(Data(contentsOf: url.appendingPathExtension("baseline.plist")))
        == "bf3c676dd2ca92219fd1eea95e492c6a1e90aa43f2f0201db16a0f177c7e968b")
    return url
  }

  private func selectedURLs(in directory: URL) throws -> (
    selector: Data, selected: URL, retained: URL
  ) {
    let selector = try Data(contentsOf: directory.appending(path: "store-selection.plist"))
    let fields = try #require(
      PropertyListSerialization.propertyList(from: selector, format: nil) as? [String: Any])
    try #require(fields["phase"] as? String == "selected")
    let candidate = try #require(fields["candidate"] as? String)
    let retained = try #require(fields["retained"] as? String)
    try #require(UUID(uuidString: candidate) != nil && UUID(uuidString: retained) != nil)
    try #require(candidate != retained)
    let generations = directory.appending(path: "generations")
    return (selector, generations.appending(path: candidate), generations.appending(path: retained))
  }

  private func withFixtureDatabase(
    at store: URL, image: StoreImage, _ body: (OpaquePointer) throws -> Void
  ) throws {
    // Original mutation is permitted only before any application selection or preparation exists.
    let root =
      FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path + "/frozen-native-"
    try #require(store.resolvingSymlinksInPath().path.hasPrefix(root))
    try #require(store.lastPathComponent == "study.store")
    let parent = store.deletingLastPathComponent()
    switch image {
    case .selected:
      try #require(parent.deletingLastPathComponent().lastPathComponent == "generations")
      try #require(UUID(uuidString: parent.lastPathComponent) != nil)
    case .original:
      try #require(
        parent.deletingLastPathComponent().resolvingSymlinksInPath().path + "/frozen-native-"
          == root)
      try #require(parent.lastPathComponent.hasPrefix("frozen-native-"))
      try #require(
        Set(try FileManager.default.contentsOfDirectory(atPath: parent.path)).isSubset(
          of: ["study.store", "study.store-wal", "study.store-shm"]))
    }
    var pointer: OpaquePointer?
    let status = sqlite3_open_v2(store.path, &pointer, SQLITE_OPEN_READWRITE, nil)
    defer { if let pointer { sqlite3_close(pointer) } }
    try #require(status == SQLITE_OK)
    let database = try #require(pointer)
    try body(database)
  }

  private func metadataRow(_ test: MetadataCase, database: OpaquePointer) throws -> MetadataRow? {
    var query: OpaquePointer?
    let uuid = test.table == "Z_METADATA" ? "Z_UUID" : "NULL"
    try #require(
      sqlite3_prepare_v2(
        database, "SELECT rowid, \(uuid), \(test.column) FROM \(test.table)", -1,
        &query, nil) == SQLITE_OK)
    let row = try #require(query)
    defer { sqlite3_finalize(row) }
    let status = sqlite3_step(row)
    if status == SQLITE_DONE { return nil }
    try #require(status == SQLITE_ROW && sqlite3_column_type(row, 2) == SQLITE_BLOB)
    let count = Int(sqlite3_column_bytes(row, 2))
    try #require(count > 0 && count <= 16 * 1024 * 1024)
    let value = MetadataRow(
      id: sqlite3_column_int64(row, 0),
      uuid: sqlite3_column_text(row, 1).map { String(cString: $0) },
      data: Data(bytes: try #require(sqlite3_column_blob(row, 2)), count: count))
    try #require(sqlite3_step(row) == SQLITE_DONE)
    return value
  }

  private func mutateMetadata(
    _ test: MetadataCase, store: URL, image: StoreImage = .selected
  ) throws {
    try withFixtureDatabase(at: store, image: image) { database in
      let before = try #require(try metadataRow(test, database: database))
      let other: MetadataCase = test.table == "Z_METADATA" ? .cacheMalformed : .metadataMalformed
      let unrelated = try metadataRow(other, database: database)
      var data = Data([0x7b])
      if test == .metadataMissingHashes {
        let original = try #require(
          PropertyListSerialization.propertyList(from: before.data, format: nil) as? [String: Any])
        try #require(original[NSStoreModelVersionHashesKey] != nil)
        var changed = original
        changed.removeValue(forKey: NSStoreModelVersionHashesKey)
        data = try PropertyListSerialization.data(
          fromPropertyList: changed, format: .binary, options: 0)
        let restored = try #require(
          PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        try #require(
          NSDictionary(dictionary: restored).isEqual(
            to: original.filter { $0.key != NSStoreModelVersionHashesKey }))
      }
      let literal = "x'" + data.map { String(format: "%02x", $0) }.joined() + "'"
      let sql =
        test.removesRow
        ? "DELETE FROM \(test.table) WHERE rowid = \(before.id)"
        : "UPDATE \(test.table) SET \(test.column) = \(literal) WHERE rowid = \(before.id)"
      try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
      try #require(sqlite3_changes(database) == 1 && sqlite3_total_changes(database) == 1)
      let after = try metadataRow(test, database: database)
      try #require(
        test.removesRow
          ? after == nil : after == MetadataRow(id: before.id, uuid: before.uuid, data: data))
      try #require(try metadataRow(other, database: database) == unrelated)
    }
  }

  private func mutate(
    _ test: PayloadCase, store: URL, issue: Data, image: StoreImage = .selected
  ) throws {
    try withFixtureDatabase(at: store, image: image) { database in
      let predicate = test.field == "ReviewRecord.issue" ? "1" : "\(test.column) IS NOT NULL"
      var query: OpaquePointer?
      try #require(
        sqlite3_prepare_v2(
          database,
          "SELECT Z_PK, \(test.column) FROM \(test.table) WHERE \(predicate) ORDER BY Z_PK LIMIT 1",
          -1, &query, nil) == SQLITE_OK)
      let row = try #require(query)
      defer { sqlite3_finalize(row) }
      try #require(sqlite3_step(row) == SQLITE_ROW)
      let rowID = sqlite3_column_int64(row, 0)
      let original: Data
      if sqlite3_column_type(row, 1) == SQLITE_NULL {
        try #require(test.field == "ReviewRecord.issue")
        original = issue
      } else {
        try #require(sqlite3_column_type(row, 1) == SQLITE_BLOB)
        original = Data(
          bytes: try #require(sqlite3_column_blob(row, 1)), count: Int(sqlite3_column_bytes(row, 1))
        )
      }
      try #require(sqlite3_step(row) == SQLITE_DONE)
      let replacement: Data?
      switch test.damage {
      case .valid: replacement = original
      case .truncated: replacement = Data("{".utf8)
      case .null: replacement = nil
      case .mistyped:
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        try #require(object[test.key] != nil && !(object[test.key] is [Any]))
        object[test.key] = [String]()
        replacement = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
      }
      let literal =
        replacement.map { "x'" + $0.map { String(format: "%02x", $0) }.joined() + "'" } ?? "NULL"
      try #require(
        sqlite3_exec(
          database, "UPDATE \(test.table) SET \(test.column) = \(literal) WHERE Z_PK = \(rowID)",
          nil,
          nil, nil) == SQLITE_OK)
      try #require(sqlite3_changes(database) == 1)
      var readback: OpaquePointer?
      try #require(
        sqlite3_prepare_v2(
          database, "SELECT \(test.column) FROM \(test.table) WHERE Z_PK = \(rowID)", -1,
          &readback, nil) == SQLITE_OK)
      let check = try #require(readback)
      defer { sqlite3_finalize(check) }
      try #require(sqlite3_step(check) == SQLITE_ROW)
      if let replacement {
        try #require(sqlite3_column_type(check, 0) == SQLITE_BLOB)
        let actual = Data(
          bytes: try #require(sqlite3_column_blob(check, 0)),
          count: Int(sqlite3_column_bytes(check, 0)))
        try #require(actual == replacement)
      } else {
        try #require(sqlite3_column_type(check, 0) == SQLITE_NULL)
      }
      try #require(sqlite3_step(check) == SQLITE_DONE)
    }
  }

  private func artifacts(in directory: URL) throws -> [String: Data] {
    let root = directory.resolvingSymlinksInPath()
    let entries = try #require(
      FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]))
    var files: [String: Data] = [:]
    var bytes = 0
    for case let file as URL in entries {
      let path = file.resolvingSymlinksInPath().path
      try #require(path.hasPrefix(root.path + "/"))
      if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
        try #require(files.count < 512)
        try #require(
          try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 <= 16 * 1024 * 1024)
        let data = try Data(contentsOf: file)
        bytes += data.count
        try #require(bytes <= 32 * 1024 * 1024)
        files[String(path.dropFirst(root.path.count + 1))] = data
      }
    }
    return files
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
