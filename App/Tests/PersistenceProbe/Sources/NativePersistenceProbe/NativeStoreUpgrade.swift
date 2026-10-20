#if DEBUG
  import CoreData
  import CryptoKit
  import Darwin
  import Foundation
  import SQLite3
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
      "probe-application-payload-corruption", "inspect-application-payload",
      "probe-application-payload-validation", "inspect-application-raw-payload",
      "probe-application-metadata-corruption", "inspect-application-metadata",
      "probe-application-adoption-corruption",
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
      if command == "probe-application-payload-corruption" {
        try payloadExperiment(frozen: url)
        return
      }
      if command == "probe-application-payload-validation" {
        try payloadExperiment(frozen: url, validateRaw: true)
        return
      }
      if command == "probe-application-metadata-corruption" {
        try metadataExperiment(frozen: url)
        return
      }
      if command == "probe-application-adoption-corruption" {
        try adoptionExperiment(frozen: url)
        return
      }
      try requireDisposable(url)
      if command == "inspect-application-raw-payload" {
        do {
          try validateRawPayloads(application: url)
          log("RAW PAYLOADS VALID: all declared V1 Codable projections checked")
          _exit(0)
        } catch {
          let failure = error as NSError
          log("RAW PAYLOADS REFUSED: \(failure.domain)/\(failure.code): \(failure)")
          _exit(74)
        }
      }
      if command == "inspect-application-payload" || command == "inspect-application-metadata" {
        do {
          let store = try await StudyStore.openApplication(in: url.deletingLastPathComponent())
          let state = try await store.nativeBaselineState()
          log("APPLICATION OPENER ACCEPTED: \(state.records.count) records")
          _exit(0)
        } catch {
          let failure = error as NSError
          log("APPLICATION OPENER REFUSED: \(failure.domain)/\(failure.code): \(failure)")
          _exit(74)
        }
      }
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

    private enum PayloadField: String, CaseIterable {
      case snapshot = "SnapshotRecord.snapshot"
      case session = "SessionRecord.session"
      case submission = "ReviewRecord.submission"
      case originalItem = "ReviewRecord.originalItem"
      case originalAssignment = "ReviewRecord.originalAssignment"
      case reviewIssue = "ReviewRecord.issue"
      case handoff = "ImportReceipt.handoff"
      case subject = "CatalogRecord.subject"
      case assignment = "AssignmentRecord.assignment"
      case account = "AccountRecord.state"
      case materialIssue = "MaterialRecord.issue"
      case attemptedMaterial = "MaterialRecord.attemptedMaterial"
      case recoveryBaseline = "MaterialRecord.recoveryBaseline"
      case material = "MaterialRecord.material"
      case archive = "ArchivedReviewRecord.answer"
      var table: String { "Z" + rawValue.split(separator: ".")[0].uppercased() }
      var column: String { "Z" + rawValue.split(separator: ".")[1].uppercased() }
      var optional: Bool {
        [
          .originalAssignment, .reviewIssue, .handoff, .materialIssue, .attemptedMaterial,
          .recoveryBaseline,
        ].contains(self)
      }
      var key: String {
        switch self {
        case .snapshot: "currentLevel"
        case .session: "isPractice"
        case .submission, .originalItem, .originalAssignment, .assignment, .attemptedMaterial,
          .material:
          "subjectID"
        case .reviewIssue, .materialIssue: "reason"
        case .handoff: "sourceID"
        case .subject, .archive: "id"
        case .account: "profile"
        case .recoveryBaseline: "remote"
        }
      }
    }
    private enum PayloadDamage: String { case truncated, mistyped, null }
    private struct PayloadCase {
      let field: PayloadField
      let damage: PayloadDamage
      var id: String { field.rawValue + "." + damage.rawValue }
    }
    private struct PayloadOutcome: Codable {
      let field: String
      let damage: String
      let openerExercised: Bool
      let termination: String
      let status: Int32
      let originalUnchanged: Bool
      let retainedUnchanged: Bool
      let selectionUnchanged: Bool
      let generationNamesUnchanged: Bool
      let candidateChangedFiles: [String]
      let output: String
      var preserved: Bool {
        originalUnchanged && retainedUnchanged && selectionUnchanged && generationNamesUnchanged
          && Set(candidateChangedFiles).isSubset(of: ["study.store-shm"])
      }
      var accepted: Bool {
        guard preserved else { return false }
        if !openerExercised { return damage == "null" && termination == "sqlConstraint" }
        return termination == "exit" && status == (damage == "valid-control" ? 0 : 74)
      }
    }

    private static func payloadExperiment(frozen: URL, validateRaw: Bool = false) throws {
      let manager = FileManager.default
      try requirePayloadCapacity()
      let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
      let source = frozen.deletingLastPathComponent()
      let sourceSize = try manager.contentsOfDirectory(
        at: source, includingPropertiesForKeys: [.fileSizeKey]
      )
      .reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
      try NativeStoreBaseline.require(
        sourceSize <= 16 * 1024 * 1024, "Payload fixture exceeds 16 MiB bound")
      let pristine = try hashes(in: source)
      let root = URL.temporaryDirectory.appending(path: "native-upgrade-\(UUID())")
      try manager.createDirectory(at: root, withIntermediateDirectories: true)
      try marker.write(to: root.appending(path: ".disposable"), options: .atomic)
      log("DISPOSABLE PAYLOAD PROBE: \(root.path)")
      var outcomes: [PayloadOutcome] = []
      let cases =
        [
          PayloadCase(field: .account, damage: .truncated),
          PayloadCase(field: .materialIssue, damage: .truncated),
        ] + PayloadField.allCases.map { PayloadCase(field: $0, damage: .mistyped) }
        + PayloadField.allCases.filter { !$0.optional }.map {
          PayloadCase(field: $0, damage: .null)
        }
      try NativeStoreBaseline.require(
        cases.count == 26, "Payload matrix changed from its reviewed bound")
      for test in cases {
        try requirePayloadCapacity()
        let directory = root.appending(path: test.id)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, bytes) in try applicationSource(in: source) {
          try bytes.write(to: directory.appending(path: name))
        }
        let url = directory.appending(path: "study.store")
        try encode(manifest.expected, to: directory.appendingPathExtension("expected.plist"))
        try child(
          "verify-application-opening", store: url,
          output: root.appending(path: test.id + ".intact.log"))
        let selector = directory.appending(path: "store-selection.plist")
        let selection = try Data(contentsOf: selector)
        guard
          let fields = try PropertyListSerialization.propertyList(
            from: selection, format: nil) as? [String: Any],
          fields["phase"] as? String == "selected",
          let candidate = fields["candidate"] as? String, UUID(uuidString: candidate) != nil,
          let retained = fields["retained"] as? String, UUID(uuidString: retained) != nil
        else { throw NativeStoreBaseline.Failure(description: "Missing verified selection") }
        let generations = directory.appending(path: "generations")
        let names = Set(try manager.contentsOfDirectory(atPath: generations.path))
        let original = try applicationSource(in: directory)
        let retainedURL = generations.appending(path: retained)
        let retainedBytes = try applicationSource(in: retainedURL)
        let candidateURL = generations.appending(path: candidate).appending(path: "study.store")
        func outcome(
          _ damage: String, exercised: Bool, reason: String, status: Int32,
          before: [String: String], after: [String: String], output: URL
        ) throws -> PayloadOutcome {
          .init(
            field: test.field.rawValue, damage: damage, openerExercised: exercised,
            termination: reason, status: status,
            originalUnchanged: try applicationSource(in: directory) == original,
            retainedUnchanged: try applicationSource(in: retainedURL) == retainedBytes,
            selectionUnchanged: try Data(contentsOf: selector) == selection,
            generationNamesUnchanged: Set(try manager.contentsOfDirectory(atPath: generations.path))
              == names,
            candidateChangedFiles: Set(before.keys).union(after.keys).filter {
              before[$0] != after[$0]
            }.sorted(),
            output: output.path)
        }
        if test.field == .reviewIssue {
          let expected = try populateReviewIssue(
            application: url, selected: candidateURL, expected: manifest.expected)
          try encode(expected, to: directory.appendingPathExtension("expected.plist"))
          let before = try hashes(in: candidateURL.deletingLastPathComponent())
          let output = root.appending(path: "ReviewRecord.issue.valid-control.log")
          let control = try child(
            "verify-application-opening", store: url, status: nil, output: output)
          let result = try outcome(
            "valid-control", exercised: true,
            reason: control.reason == .exit ? "exit" : "uncaughtSignal", status: control.status,
            before: before, after: hashes(in: candidateURL.deletingLastPathComponent()),
            output: output)
          outcomes.append(result)
          try encode(outcomes, to: root.appending(path: "payload-outcomes.plist"))
          try NativeStoreBaseline.require(
            result.accepted, "Populated review issue failed exact-state control")
          log("PASS CONTROL: one populated ReviewRecord.issue; exact 38-record state preserved")
        }
        if validateRaw {
          let validation = try child(
            "inspect-application-raw-payload", store: url,
            status: nil,
            output: root.appending(path: test.id + ".valid-raw.log"))
          log("VALID RAW RESULT: \(validation.reason), status=\(validation.status)")
          guard validation.reason == .exit && validation.status == 0 else {
            log("FAIL: raw preflight could not validate an intact fixture; no corruption attempted")
            _exit(1)
          }
        }
        let beforeMutation = try hashes(in: candidateURL.deletingLastPathComponent())
        let constraint = try corruptPayload(test, application: url, target: .selected(candidateURL))
        let corrupted = try hashes(in: candidateURL.deletingLastPathComponent())
        let output = root.appending(path: test.id + ".child.log")
        let result: (reason: Process.TerminationReason, status: Int32)
        if let constraint {
          try Data("UNEXERCISED: SQLite rejected NULL with code \(constraint)\n".utf8).write(
            to: output)
          result = (.exit, constraint)
        } else {
          result = try child(
            validateRaw ? "inspect-application-raw-payload" : "inspect-application-payload",
            store: url, status: nil, output: output)
        }
        let after = try hashes(in: candidateURL.deletingLastPathComponent())
        let recorded = try outcome(
          test.damage.rawValue, exercised: constraint == nil,
          reason: constraint != nil
            ? "sqlConstraint" : (result.reason == .exit ? "exit" : "uncaughtSignal"),
          status: result.status, before: constraint == nil ? corrupted : beforeMutation,
          after: after, output: output)
        outcomes.append(recorded)
        try encode(outcomes, to: root.appending(path: "payload-outcomes.plist"))
        log(
          "PAYLOAD RESULT: \(test.id), \(recorded.termination)/\(recorded.status), opener=\(recorded.openerExercised), output=\(output.path)"
        )
        if recorded.accepted && recorded.openerExercised {
          try requireDisposable(url)
          try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: retainedURL.path)
          try manager.removeItem(at: directory)
          try manager.removeItem(at: directory.appendingPathExtension("expected.plist"))
        }
      }
      try encode(outcomes, to: root.appending(path: "payload-outcomes.plist"))
      try NativeStoreBaseline.require(try hashes(in: source) == pristine, "Frozen fixture changed")
      try NativeStoreBaseline.require(
        outcomes.count == 27 && outcomes.allSatisfy(\.preserved),
        "Payload opening changed DB/WAL, original/retained/selection bytes or generation membership"
      )
      log(
        "PASS: frozen fixture, original, retained, selection, selected DB/WAL and generation names preserved; only SHM may change"
      )
      guard outcomes.allSatisfy(\.accepted) else {
        log("FAIL: malformed payload did not safely refuse; signals and acceptance remain failures")
        _exit(1)
      }
      let refused = outcomes.filter { $0.openerExercised && $0.damage != "valid-control" }.count
      let unexercised = outcomes.filter { !$0.openerExercised }.count
      log(
        "PASS: \(refused) actual opener refusals, 1 exact-state control; \(unexercised) SQL NULL attempts UNEXERCISED"
      )
      if validateRaw {
        log(
          "EXPERIMENT ONLY: raw projections; production-opener acceptance is a separate command")
      }
      log("SCOPE: disposable selected-store payloads on Mac, not corruption recovery or iOS proof")
    }

    private enum AdoptionCase: String, CaseIterable {
      case control, payloadMalformed, cacheMissing, metadataMalformed
    }
    private struct AdoptionSelection: Codable, Equatable {
      let formatVersion: Int
      let schema: String
      let phase: String
      let candidate: UUID
      let retained: UUID
      let source: [String: String]
      let validation: String?
    }
    private struct AdoptionAttempt: Codable {
      let scenario: String
      let attempt: Int
      let expectedStatus: Int32
      let termination: String
      let status: Int32
      let selection: AdoptionSelection?
      let selectionValid: Bool
      let selectionContinuity: Bool
      let sourceUnchanged: Bool
      let retainedMatchesSource: Bool
      let changedPriorPaths: [String]
      let unexpectedChangedPriorPaths: [String]
      let addedPaths: [String]
      let output: String
      var accepted: Bool {
        termination == "exit" && status == expectedStatus && selectionValid
          && selectionContinuity && sourceUnchanged && retainedMatchesSource
          && unexpectedChangedPriorPaths.isEmpty
      }
    }
    private static func adoptionExperiment(frozen: URL) throws {
      let manager = FileManager.default
      try requirePayloadCapacity()
      let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
      let source = frozen.deletingLastPathComponent()
      let pristine = try hashes(in: source)
      let originalSource = try applicationSource(in: source)
      try NativeStoreBaseline.require(
        AdoptionCase.allCases.count == 4
          && originalSource.values.reduce(0) { $0 + $1.count } <= 16 * 1024 * 1024,
        "Adoption matrix or source exceeds its reviewed bound")
      let root = URL.temporaryDirectory.appending(path: "native-upgrade-\(UUID())")
      try manager.createDirectory(at: root, withIntermediateDirectories: true)
      try marker.write(to: root.appending(path: ".disposable"), options: .atomic)
      log("DISPOSABLE ADOPTION PROBE: \(root.path)")
      var outcomes: [AdoptionAttempt] = []
      for test in AdoptionCase.allCases {
        try requirePayloadCapacity()
        let directory = root.appending(path: test.rawValue)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, bytes) in originalSource {
          try bytes.write(to: directory.appending(path: name))
        }
        let url = directory.appending(path: "study.store")
        try encode(manifest.expected, to: directory.appendingPathExtension("expected.plist"))
        switch test {
        case .control: break
        case .payloadMalformed:
          try NativeStoreBaseline.require(
            corruptPayload(
              .init(field: .account, damage: .truncated), application: url, target: .unselected)
              == nil,
            "Required malformed adoption payload was not changed")
        case .cacheMissing:
          _ = try corruptMetadata(.cacheMissing, application: url, target: .unselected)
        case .metadataMalformed:
          _ = try corruptMetadata(.metadataMalformed, application: url, target: .unselected)
        }
        let mutatedSource = try applicationSource(in: directory)
        let sourceHashes = mutatedSource.mapValues {
          SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
        }
        let selector = directory.appending(path: "store-selection.plist")
        var previousSelection: AdoptionSelection?
        var previousSelector: Data?
        for attempt in 1...2 {
          let before = try adoptionArtifacts(in: directory)
          let output = root.appending(path: "\(test.rawValue).\(attempt).child.log")
          let result = try child(
            test == .control ? "verify-application-opening" : "inspect-application-metadata",
            store: url, status: nil, output: output)
          let after = try adoptionArtifacts(in: directory)
          let selectionData = try? Data(contentsOf: selector)
          let selection = selectionData.flatMap {
            try? PropertyListDecoder().decode(AdoptionSelection.self, from: $0)
          }
          var retainedMatchesSource = false
          var selectionValid = false
          var selectionContinuity = false
          if let selection {
            let retained = directory.appending(path: "generations/\(selection.retained)")
            retainedMatchesSource = (try? hashes(in: retained)) == sourceHashes
            selectionValid =
              selection.formatVersion == 1
              && selection.schema == StudySchemaV1.versionIdentifier.description
              && selection.phase == (test == .control ? "selected" : "preparing")
              && selection.source == sourceHashes && selection.candidate != selection.retained
              && (test == .control
                ? selection.validation?.count == 64 : selection.validation == nil)
            if let previousSelection {
              selectionContinuity =
                selection.retained == previousSelection.retained
                && (test == .control
                  ? selection == previousSelection && selectionData == previousSelector
                  : selection.candidate != previousSelection.candidate)
            } else {
              selectionContinuity = attempt == 1
            }
          }
          let changed = before.keys.filter { before[$0] != after[$0] }.sorted()
          let allowed =
            test == .control
            ? previousSelection.map { ["generations/\($0.candidate)/study.store-shm"] } ?? []
            : ["store-selection.plist"]
          let added = after.keys.filter { before[$0] == nil }.sorted()
          let unexpected =
            changed.filter { !allowed.contains($0) }
            + (test == .control && attempt == 2 ? added.filter { !allowed.contains($0) } : [])
          let recorded = AdoptionAttempt(
            scenario: test.rawValue, attempt: attempt, expectedStatus: test == .control ? 0 : 74,
            termination: result.reason == .exit ? "exit" : "uncaughtSignal", status: result.status,
            selection: selection, selectionValid: selectionValid,
            selectionContinuity: selectionContinuity,
            sourceUnchanged: try applicationSource(in: directory) == mutatedSource,
            retainedMatchesSource: retainedMatchesSource, changedPriorPaths: changed,
            unexpectedChangedPriorPaths: unexpected, addedPaths: added, output: output.path)
          outcomes.append(recorded)
          try encode(outcomes, to: root.appending(path: "adoption-outcomes.plist"))
          try NativeStoreBaseline.require(
            try hashes(in: source) == pristine, "Frozen fixture changed")
          log(
            "ADOPTION RESULT: \(test.rawValue)/\(attempt), \(recorded.termination)/\(recorded.status)"
          )
          guard recorded.accepted else {
            log("FAIL: adoption did not safely refuse/preserve; stopped, all images retained")
            _exit(1)
          }
          previousSelection = selection
          previousSelector = selectionData
        }
      }
      try NativeStoreBaseline.require(
        outcomes.count == 8 && outcomes.allSatisfy(\.accepted), "Incomplete adoption matrix")
      // Only successful marked images are removed, after the entire retry matrix has passed.
      for test in AdoptionCase.allCases {
        let directory = root.appending(path: test.rawValue)
        try requireDisposable(directory.appending(path: "study.store"))
        guard
          let retained = outcomes.first(where: { $0.scenario == test.rawValue })?.selection?
            .retained
        else { throw NativeStoreBaseline.Failure(description: "Missing passed retained image") }
        try manager.setAttributes(
          [.posixPermissions: 0o700],
          ofItemAtPath: directory.appending(path: "generations/\(retained)").path)
        try manager.removeItem(at: directory)
        try manager.removeItem(at: directory.appendingPathExtension("expected.plist"))
      }
      log(
        "PASS: 4 adoption scenarios / 8 fresh opener attempts, including unchanged failed retries")
      log(
        "PASS: original/retained bytes and all abandoned artifacts preserved; no failed selection")
      log(
        "SCOPE: disposable Mac first adoption only; no interruption, iOS corruption or full G7 proof"
      )
    }
    private static func adoptionArtifacts(in directory: URL) throws -> [String: String] {
      let canonical = directory.resolvingSymlinksInPath().path
      guard
        let files = FileManager.default.enumerator(
          at: directory,
          includingPropertiesForKeys: [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
          ])
      else { throw NativeStoreBaseline.Failure(description: "Cannot enumerate adoption artifacts") }
      var result: [String: String] = [:]
      var bytes = 0
      for case let file as URL in files {
        let path = file.resolvingSymlinksInPath().path
        let values = try file.resourceValues(
          forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        try NativeStoreBaseline.require(
          values.isSymbolicLink == false && path.hasPrefix(canonical + "/")
            && result.count < 512, "Unsupported or oversized disposable adoption image")
        let relative = String(path.dropFirst(canonical.count + 1))
        if values.isDirectory == true {
          result[relative + "/"] = "directory"
        } else {
          bytes += values.fileSize ?? 32 * 1024 * 1024 + 1
          try NativeStoreBaseline.require(
            values.isRegularFile == true && bytes <= 32 * 1024 * 1024,
            "Disposable adoption artifacts exceed their 32 MiB bound")
          result[relative] = SHA256.hash(data: try Data(contentsOf: file))
            .map { String(format: "%02x", $0) }.joined()
        }
      }
      return result
    }

    private enum MetadataCase: String, CaseIterable {
      case control, metadataMissing, metadataMalformed, metadataMissingHashes
      case cacheMissing, cacheMalformed
      var table: String {
        switch self {
        case .cacheMissing, .cacheMalformed: "Z_MODELCACHE"
        default: "Z_METADATA"
        }
      }
      var column: String { table == "Z_METADATA" ? "Z_PLIST" : "Z_CONTENT" }
      var removesRow: Bool { self == .metadataMissing || self == .cacheMissing }
    }
    private struct MetadataRow: Equatable {
      let id: Int64
      let uuid: String?
      let data: Data
    }
    private struct MetadataChange: Codable {
      let table: String
      let column: String
      let rowID: Int64
      let deletedRow: Bool
      let affectedRows: Int32
      let beforeSHA256: String
      let afterSHA256: String?
    }
    private struct MetadataOutcome: Codable {
      let scenario: String
      let mutation: MetadataChange?
      let opening: PayloadOutcome
    }
    private static func metadataExperiment(frozen: URL) throws {
      let manager = FileManager.default
      try requirePayloadCapacity()
      let manifest = try NativeStoreBaseline.frozenManifest(at: frozen)
      let source = frozen.deletingLastPathComponent()
      let pristine = try hashes(in: source)
      let originalSource = try applicationSource(in: source)
      try NativeStoreBaseline.require(
        originalSource.values.reduce(0) { $0 + $1.count } <= 16 * 1024 * 1024,
        "Metadata fixture exceeds 16 MiB bound")
      let root = URL.temporaryDirectory.appending(path: "native-upgrade-\(UUID())")
      try manager.createDirectory(at: root, withIntermediateDirectories: true)
      try marker.write(to: root.appending(path: ".disposable"), options: .atomic)
      log("DISPOSABLE METADATA PROBE: \(root.path)")
      try NativeStoreBaseline.require(
        MetadataCase.allCases.count == 6, "Metadata matrix changed from its reviewed bound")
      var outcomes: [MetadataOutcome] = []
      for test in MetadataCase.allCases {
        try requirePayloadCapacity()
        let directory = root.appending(path: test.rawValue)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, bytes) in originalSource {
          try bytes.write(to: directory.appending(path: name))
        }
        let url = directory.appending(path: "study.store")
        try encode(manifest.expected, to: directory.appendingPathExtension("expected.plist"))
        try child(
          "verify-application-opening", store: url,
          output: root.appending(path: test.rawValue + ".intact.log"))
        let selector = directory.appending(path: "store-selection.plist")
        let selection = try Data(contentsOf: selector)
        guard
          let fields = try PropertyListSerialization.propertyList(from: selection, format: nil)
            as? [String: Any], fields["phase"] as? String == "selected",
          let candidate = fields["candidate"] as? String, UUID(uuidString: candidate) != nil,
          let retained = fields["retained"] as? String, UUID(uuidString: retained) != nil
        else { throw NativeStoreBaseline.Failure(description: "Missing verified selection") }
        let generations = directory.appending(path: "generations")
        let names = Set(try manager.contentsOfDirectory(atPath: generations.path))
        let original = try applicationSource(in: directory)
        let retainedURL = generations.appending(path: retained)
        let retainedBytes = try applicationSource(in: retainedURL)
        let selected = generations.appending(path: candidate).appending(path: "study.store")
        let mutation = try corruptMetadata(test, application: url, target: .selected(selected))
        let before = try hashes(in: selected.deletingLastPathComponent())
        let output = root.appending(path: test.rawValue + ".child.log")
        let result = try child(
          test == .control ? "verify-application-opening" : "inspect-application-metadata",
          store: url, status: nil, output: output)
        let after = try hashes(in: selected.deletingLastPathComponent())
        let opening = PayloadOutcome(
          field: test.table + "." + test.column,
          damage: test == .control ? "valid-control" : test.rawValue, openerExercised: true,
          termination: result.reason == .exit ? "exit" : "uncaughtSignal", status: result.status,
          originalUnchanged: try applicationSource(in: directory) == original,
          retainedUnchanged: try applicationSource(in: retainedURL) == retainedBytes,
          selectionUnchanged: try Data(contentsOf: selector) == selection,
          generationNamesUnchanged: Set(try manager.contentsOfDirectory(atPath: generations.path))
            == names,
          candidateChangedFiles: Set(before.keys).union(after.keys).filter {
            before[$0] != after[$0]
          }.sorted(), output: output.path)
        outcomes.append(.init(scenario: test.rawValue, mutation: mutation, opening: opening))
        try encode(outcomes, to: root.appending(path: "metadata-outcomes.plist"))
        try NativeStoreBaseline.require(
          try hashes(in: source) == pristine, "Frozen fixture changed")
        log("METADATA RESULT: \(test.rawValue), \(opening.termination)/\(opening.status)")
        guard opening.accepted else {
          log("FAIL: metadata opener did not safely refuse/preserve; stopped, image retained")
          _exit(1)
        }
        try requireDisposable(url)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: retainedURL.path)
        try manager.removeItem(at: directory)
        try manager.removeItem(at: directory.appendingPathExtension("expected.plist"))
      }
      log("PASS: 5 actual metadata/cache opener refusals and 1 exact 38-record control")
      log("PASS: original/retained/selector/generation names and selected DB/WAL preserved")
      log("SCOPE: selected-generation Mac metadata/cache only; no adoption or iOS failure proof")
    }
    private static func metadataRow(
      _ test: MetadataCase, database: OpaquePointer
    ) throws -> MetadataRow? {
      var statement: OpaquePointer?
      let uuid = test.table == "Z_METADATA" ? "Z_UUID" : "NULL"
      try NativeStoreBaseline.require(
        sqlite3_prepare_v2(
          database, "SELECT rowid, \(uuid), \(test.column) FROM \(test.table)", -1,
          &statement, nil) == SQLITE_OK,
        "Cannot prepare the closed-whitelist metadata query")
      guard let statement else {
        throw NativeStoreBaseline.Failure(description: "Missing metadata query")
      }
      defer { sqlite3_finalize(statement) }
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return nil }
      try NativeStoreBaseline.require(
        status == SQLITE_ROW && sqlite3_column_type(statement, 2) == SQLITE_BLOB,
        "Metadata row has no BLOB")
      let count = Int(sqlite3_column_bytes(statement, 2))
      guard count > 0, count <= 16 * 1024 * 1024,
        let bytes = sqlite3_column_blob(statement, 2)
      else { throw NativeStoreBaseline.Failure(description: "Metadata BLOB size unsupported") }
      let row = MetadataRow(
        id: sqlite3_column_int64(statement, 0),
        uuid: sqlite3_column_text(statement, 1).map { String(cString: $0) },
        data: Data(bytes: bytes, count: count))
      try NativeStoreBaseline.require(
        sqlite3_step(statement) == SQLITE_DONE, "Metadata query found multiple rows")
      return row
    }
    private static func corruptMetadata(
      _ test: MetadataCase, application: URL, target: CorruptionTarget
    ) throws -> MetadataChange? {
      if test == .control { return nil }
      return try payloadDatabase(application: application, target: target) { database in
        guard let row = try metadataRow(test, database: database) else {
          throw NativeStoreBaseline.Failure(description: "No populated metadata/cache row")
        }
        let other: MetadataCase = test.table == "Z_METADATA" ? .cacheMalformed : .metadataMalformed
        let unrelated = try metadataRow(other, database: database)
        var trigger: OpaquePointer?
        try NativeStoreBaseline.require(
          sqlite3_prepare_v2(
            database, "SELECT 1 FROM sqlite_master WHERE type = 'trigger' LIMIT 1", -1,
            &trigger, nil) == SQLITE_OK,
          "Cannot check disposable SQL trigger safety")
        guard let trigger else {
          throw NativeStoreBaseline.Failure(description: "Missing trigger query")
        }
        defer { sqlite3_finalize(trigger) }
        try NativeStoreBaseline.require(
          sqlite3_step(trigger) == SQLITE_DONE, "Fixture contains SQL triggers")
        var data = Data([0x7b])
        if test == .metadataMissingHashes {
          guard
            let original = try PropertyListSerialization.propertyList(from: row.data, format: nil)
              as? [String: Any], original[NSStoreModelVersionHashesKey] != nil
          else { throw NativeStoreBaseline.Failure(description: "Missing original model hashes") }
          var changed = original
          changed.removeValue(forKey: NSStoreModelVersionHashesKey)
          data = try PropertyListSerialization.data(
            fromPropertyList: changed, format: .binary, options: 0)
          guard
            let readback = try PropertyListSerialization.propertyList(from: data, format: nil)
              as? [String: Any]
          else { throw NativeStoreBaseline.Failure(description: "Changed metadata is not a plist") }
          try NativeStoreBaseline.require(
            readback[NSStoreModelVersionHashesKey] == nil
              && NSDictionary(dictionary: readback).isEqual(
                to: original.filter {
                  $0.key != NSStoreModelVersionHashesKey
                }),
            "Metadata mutation changed unrelated plist keys")
        }
        let literal = "x'" + data.map { String(format: "%02x", $0) }.joined() + "'"
        let sql =
          test.removesRow
          ? "DELETE FROM \(test.table) WHERE rowid = \(row.id)"
          : "UPDATE \(test.table) SET \(test.column) = \(literal) WHERE rowid = \(row.id)"
        try NativeStoreBaseline.require(
          sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
            && sqlite3_changes(database) == 1 && sqlite3_total_changes(database) == 1,
          "Metadata mutation did not change exactly one row")
        let after = try metadataRow(test, database: database)
        try NativeStoreBaseline.require(
          (test.removesRow
            ? after == nil : after == MetadataRow(id: row.id, uuid: row.uuid, data: data))
            && metadataRow(other, database: database) == unrelated,
          "Metadata mutation failed exact readback or changed the other metadata table")
        return MetadataChange(
          table: test.table, column: test.column, rowID: row.id, deletedRow: test.removesRow,
          affectedRows: sqlite3_changes(database),
          beforeSHA256: SHA256.hash(data: row.data).map { String(format: "%02x", $0) }.joined(),
          afterSHA256: after.map {
            SHA256.hash(data: $0.data).map { String(format: "%02x", $0) }.joined()
          })
      }
    }

    private static func validateRawPayloads(application: URL) throws {
      try requireDisposable(application)
      let manager = FileManager.default
      let directory = application.deletingLastPathComponent()
      let root = directory.deletingLastPathComponent()
      let selection = try Data(contentsOf: directory.appending(path: "store-selection.plist"))
      guard
        let fields = try PropertyListSerialization.propertyList(
          from: selection, format: nil) as? [String: Any],
        fields["phase"] as? String == "selected",
        let candidate = fields["candidate"] as? String, UUID(uuidString: candidate) != nil
      else { throw NativeStoreBaseline.Failure(description: "Missing selected payload source") }
      let verification = root.appending(path: "raw-verification-\(UUID())")
      let reference = root.appending(path: "raw-reference-\(UUID())")
      for (from, to) in [
        (directory.appending(path: "generations/\(candidate)"), verification),
        (directory, reference),
      ] {
        try manager.createDirectory(at: to, withIntermediateDirectories: true)
        for (name, bytes) in try applicationSource(in: from) {
          try bytes.write(to: to.appending(path: name))
        }
      }
      let options = [NSReadOnlyPersistentStoreOption: true]
      let url = verification.appending(path: "study.store")
      let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
        type: .sqlite, at: url, options: options)
      let expected = try NSPersistentStoreCoordinator.metadataForPersistentStore(
        type: .sqlite, at: reference.appending(path: "study.store"), options: options)
      let model = try NSPersistentStoreCoordinator.cachedModelForPersistentStore(
        at: url, options: options)
      guard
        let frozenModel = NSManagedObjectModel.makeManagedObjectModel(for: StudySchemaV1.schema),
        let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data],
        let expectedHashes = expected[NSStoreModelVersionHashesKey] as? [String: Data],
        metadata[NSStoreTypeKey] as? String == NSSQLiteStoreType,
        hashes == expectedHashes && hashes == model.entityVersionHashesByName,
        hashes == frozenModel.entityVersionHashesByName,
        Set(hashes.keys) == Set(NativeStoreBaseline.models)
      else {
        throw NativeStoreBaseline.Failure(description: "Raw projection model identity changed")
      }
      let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
      let persistent = try coordinator.addPersistentStore(
        type: .sqlite, at: url, options: options)
      defer { try? coordinator.remove(persistent) }
      let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
      context.persistentStoreCoordinator = coordinator
      try context.performAndWait {
        func decode<Value: Decodable>(_ type: Value.Type, _ data: Data) throws {
          _ = try JSONDecoder().decode(type, from: data)
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
        var seen: Set<String> = []
        for entity in StudySchemaV1.schema.entities.sorted(by: { $0.name < $1.name }) {
          let attributes = entity.attributes.filter(\.isCodable).sorted { $0.name < $1.name }
          guard !attributes.isEmpty else { continue }
          let request = NSFetchRequest<NSDictionary>(entityName: entity.name)
          guard
            let description = NSEntityDescription.entity(forEntityName: entity.name, in: context)
          else { throw NativeStoreBaseline.Failure(description: "Missing raw entity") }
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
          let rows = try context.fetch(request)
          for attribute in attributes {
            let key = entity.name + "." + attribute.name
            guard let validate = validators[key] else {
              throw NativeStoreBaseline.Failure(description: "Uncovered V1 payload: \(key)")
            }
            var dataCount = 0
            var nullCount = 0
            for row in rows {
              if let data = row[attribute.name] as? Data {
                try validate(data)
                dataCount += 1
              } else if attribute.isOptional,
                row[attribute.name] == nil || row[attribute.name] is NSNull
              {
                nullCount += 1
              } else {
                throw NativeStoreBaseline.Failure(description: "Raw Data unavailable: \(key)")
              }
            }
            seen.insert(key)
            log("RAW FIELD: \(key), Data=\(dataCount), null=\(nullCount)")
          }
        }
        try NativeStoreBaseline.require(
          seen == Set(validators.keys), "Not all 15 V1 fields fetched")
      }
    }

    private enum CorruptionTarget {
      case selected(URL)
      case unselected
    }
    private static func payloadDatabase<Value>(
      application: URL, target: CorruptionTarget, _ body: (OpaquePointer) throws -> Value
    ) throws -> Value {
      try requireDisposable(application)
      let directory = application.deletingLastPathComponent().resolvingSymlinksInPath()
      let candidate: URL
      switch target {
      case .selected(let selected):
        candidate = selected.resolvingSymlinksInPath()
        try NativeStoreBaseline.require(
          candidate.deletingLastPathComponent().deletingLastPathComponent().path
            == directory.appending(path: "generations").path
            && UUID(uuidString: candidate.deletingLastPathComponent().lastPathComponent) != nil
            && candidate.lastPathComponent == "study.store",
          "SQL corruption requires an existing selected store in the marked disposable image")
      case .unselected:
        candidate = application.resolvingSymlinksInPath()
        let manager = FileManager.default
        let folder = try application.deletingLastPathComponent().resourceValues(
          forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let file = try application.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let names = Set(try manager.contentsOfDirectory(atPath: directory.path))
        try NativeStoreBaseline.require(
          candidate.path == directory.appending(path: "study.store").path
            && folder.isDirectory == true && folder.isSymbolicLink == false
            && file.isRegularFile == true && file.isSymbolicLink == false
            && names.contains("study.store")
            && names.isSubset(of: ["study.store", "study.store-wal", "study.store-shm"]),
          "Unselected corruption requires only original files before any disposable app open")
      }
      var database: OpaquePointer?
      let opened = sqlite3_open_v2(candidate.path, &database, SQLITE_OPEN_READWRITE, nil)
      guard opened == SQLITE_OK, let database else {
        if let database { sqlite3_close(database) }
        throw NativeStoreBaseline.Failure(description: "Disposable SQL open failed: \(opened)")
      }
      defer { sqlite3_close(database) }
      return try body(database)
    }

    private static func payloadRow(
      _ field: PayloadField, database: OpaquePointer, id: Int64? = nil
    ) throws -> (id: Int64, data: Data?) {
      let predicate =
        id.map { "Z_PK = \($0)" }
        ?? "\(field.column) IS NOT NULL ORDER BY Z_PK LIMIT 1"
      var statement: OpaquePointer?
      try NativeStoreBaseline.require(
        sqlite3_prepare_v2(
          database, "SELECT Z_PK, \(field.column) FROM \(field.table) WHERE \(predicate)", -1,
          &statement, nil) == SQLITE_OK,
        "Cannot prepare the closed-whitelist payload query")
      guard let statement else {
        throw NativeStoreBaseline.Failure(description: "Missing payload query")
      }
      defer { sqlite3_finalize(statement) }
      try NativeStoreBaseline.require(
        sqlite3_step(statement) == SQLITE_ROW, "Missing selected payload row: \(field.rawValue)")
      let rowID = sqlite3_column_int64(statement, 0)
      let data: Data?
      if sqlite3_column_type(statement, 1) == SQLITE_NULL {
        data = nil
      } else {
        try NativeStoreBaseline.require(
          sqlite3_column_type(statement, 1) == SQLITE_BLOB, "Payload is not a BLOB")
        let count = Int(sqlite3_column_bytes(statement, 1))
        if count == 0 {
          data = Data()
        } else if let bytes = sqlite3_column_blob(statement, 1) {
          data = Data(bytes: bytes, count: count)
        } else {
          throw NativeStoreBaseline.Failure(description: "Missing payload bytes")
        }
      }
      try NativeStoreBaseline.require(
        sqlite3_step(statement) == SQLITE_DONE, "Payload query returned multiple rows")
      return (rowID, data)
    }

    private static func replacePayload(
      _ field: PayloadField, database: OpaquePointer, id: Int64, with data: Data?
    ) throws -> Int32? {
      let before = try payloadRow(field, database: database, id: id).data
      let literal =
        data.map { "x'" + $0.map { String(format: "%02x", $0) }.joined() + "'" } ?? "NULL"
      let result = sqlite3_exec(
        database, "UPDATE \(field.table) SET \(field.column) = \(literal) WHERE Z_PK = \(id)", nil,
        nil, nil)
      if result == SQLITE_CONSTRAINT && data == nil {
        let code = sqlite3_extended_errcode(database)
        try NativeStoreBaseline.require(
          sqlite3_changes(database) == 0
            && payloadRow(field, database: database, id: id).data == before,
          "A rejected NULL mutation changed its payload")
        return code
      }
      try NativeStoreBaseline.require(
        result == SQLITE_OK && sqlite3_changes(database) == 1,
        "The single selected payload was not changed: \(field.rawValue), SQLite \(result)")
      try NativeStoreBaseline.require(
        payloadRow(field, database: database, id: id).data == data,
        "The exact selected payload did not survive SQL readback")
      return nil
    }

    private static func populateReviewIssue(
      application: URL, selected: URL, expected: NativeStoreBaseline.State
    ) throws -> NativeStoreBaseline.State {
      guard let target = expected.records.first(where: { $0.model == "ReviewRecord" }),
        target.fields["issue"] == Data("null".utf8),
        let donor = expected.records.first(where: {
          $0.model == "MaterialRecord" && $0.fields["issue"] != Data("null".utf8)
        }),
        let issue = donor.fields["issue"], let account = target.accountID,
        let subjectData = target.fields["subjectID"]
      else {
        throw NativeStoreBaseline.Failure(description: "Missing exact review-issue control source")
      }
      _ = try JSONDecoder().decode(StudyUploadIssue.self, from: issue)
      let subjectID = try JSONDecoder().decode(Int64.self, from: subjectData)
      try payloadDatabase(application: application, target: .selected(selected)) { database in
        var statement: OpaquePointer?
        try NativeStoreBaseline.require(
          sqlite3_prepare_v2(
            database, "SELECT Z_PK FROM ZREVIEWRECORD WHERE ZACCOUNTID = ? AND ZSUBJECTID = ?", -1,
            &statement, nil) == SQLITE_OK,
          "Cannot prepare review-issue control identity")
        guard let statement else {
          throw NativeStoreBaseline.Failure(description: "Missing review-issue identity")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        try NativeStoreBaseline.require(
          sqlite3_bind_text(statement, 1, account, -1, transient) == SQLITE_OK
            && sqlite3_bind_int64(statement, 2, subjectID) == SQLITE_OK
            && sqlite3_step(statement) == SQLITE_ROW,
          "Missing exact review-issue control identity")
        let rowID = sqlite3_column_int64(statement, 0)
        try NativeStoreBaseline.require(
          sqlite3_step(statement) == SQLITE_DONE, "Duplicate review-issue identity")
        try NativeStoreBaseline.require(
          payloadRow(.reviewIssue, database: database, id: rowID).data == nil,
          "Review issue was already populated")
        try NativeStoreBaseline.require(
          replacePayload(.reviewIssue, database: database, id: rowID, with: issue) == nil,
          "Valid review issue was rejected")
      }
      let records = expected.records.map { record in
        guard record.model == target.model && record.identity == target.identity else {
          return record
        }
        return NativeStoreBaseline.Record(
          model: record.model, identity: record.identity, accountID: record.accountID,
          fields: record.fields.merging(["issue": issue]) { _, replacement in replacement })
      }
      return .init(schemaVersion: expected.schemaVersion, schema: expected.schema, records: records)
    }

    private static func corruptPayload(
      _ test: PayloadCase, application: URL, target: CorruptionTarget
    ) throws -> Int32? {
      try payloadDatabase(application: application, target: target) { database in
        let row = try payloadRow(test.field, database: database)
        guard let original = row.data else {
          throw NativeStoreBaseline.Failure(description: "No populated payload to corrupt")
        }
        let data: Data?
        switch test.damage {
        case .truncated: data = Data("{".utf8)
        case .null: data = nil
        case .mistyped:
          guard let object = try JSONSerialization.jsonObject(with: original) as? [String: Any],
            object[test.field.key] != nil
          else {
            throw NativeStoreBaseline.Failure(
              description: "Missing reviewed payload key: \(test.field.rawValue)")
          }
          var changed = object
          changed[test.field.key] = [String]()
          let encoded = try JSONSerialization.data(withJSONObject: changed, options: .sortedKeys)
          guard let restored = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
          else {
            throw NativeStoreBaseline.Failure(
              description: "Mistyped payload is not a valid JSON object")
          }
          try NativeStoreBaseline.require(
            NSDictionary(dictionary: restored.filter { $0.key != test.field.key }).isEqual(
              to: object.filter { $0.key != test.field.key })
              && (restored[test.field.key] as? [String]) == []
              && !(object[test.field.key] is [Any]),
            "Mistyped mutation changed unrelated JSON fields or retained the original type")
          data = encoded
        }
        let constraint = try replacePayload(test.field, database: database, id: row.id, with: data)
        log(
          "MUTATED DISPOSABLE: \(test.id), exactly one row/readback; constraint=\(constraint.map(String.init) ?? "none")"
        )
        return constraint
      }
    }

    private static func requirePayloadCapacity() throws {
      let attributes = try FileManager.default.attributesOfFileSystem(
        forPath: URL.temporaryDirectory.path)
      try NativeStoreBaseline.require(
        ((attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0) >= 512 * 1024 * 1024,
        "Payload probe requires at least 512 MiB free; it never fills a volume to simulate failure")
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
    @discardableResult private static func child(
      _ command: String, store: URL, status: Int32? = 0, output: URL? = nil
    ) throws -> (reason: Process.TerminationReason, status: Int32) {
      let process = Process()
      process.executableURL = Bundle.main.executableURL
      process.arguments = [command, store.path]
      let outputHandle: FileHandle?
      if let output {
        try Data().write(to: output)
        outputHandle = try FileHandle(forWritingTo: output)
      } else {
        outputHandle = nil
      }
      defer { try? outputHandle?.close() }
      process.standardOutput = outputHandle ?? FileHandle.standardOutput
      process.standardError = outputHandle ?? FileHandle.standardError
      try process.run()
      if let output {
        let deadline = Date.now.addingTimeInterval(10)
        while process.isRunning {
          let attributes = try? FileManager.default.attributesOfItem(atPath: output.path)
          let count = (attributes?[.size] as? NSNumber)?.int64Value ?? Int64.max
          var lowCapacity = false
          do { try requirePayloadCapacity() } catch { lowCapacity = true }
          if Date.now >= deadline || count > 1024 * 1024 || lowCapacity {
            process.terminate()
            let grace = Date.now.addingTimeInterval(1)
            while process.isRunning && Date.now < grace { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw NativeStoreBaseline.Failure(
              description:
                "Payload child exceeded its 10s/1MiB/free-space bound; image retained: \(output.path)"
            )
          }
          Thread.sleep(forTimeInterval: 0.05)
        }
      }
      process.waitUntilExit()
      if let status {
        try NativeStoreBaseline.require(
          process.terminationReason == .exit && process.terminationStatus == status,
          "\(command) process failed: \(process.terminationStatus)")
      }
      return (process.terminationReason, process.terminationStatus)
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
