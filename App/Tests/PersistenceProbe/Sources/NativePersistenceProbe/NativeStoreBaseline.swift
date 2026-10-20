#if DEBUG
  import CryptoKit
  import Foundation
  import StudyCore
  import SwiftData

  @testable import StudyPersistence

  /// Debug-only migration evidence. The selected production schema and model encoders write it.
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
      let sidecar = url.appendingPathExtension("baseline.plist")
      if command == "write-native-baseline" {
        let provenance = try sourceProvenance()
        try require(
          provenance.hash == writerSourceHash,
          "Baseline writer sources differ from the pinned committed writer; do not regenerate v0.")
        try require(
          !FileManager.default.fileExists(atPath: url.path)
            && !FileManager.default.fileExists(atPath: sidecar.path)
            && !FileManager.default.fileExists(atPath: url.path + "-wal")
            && !FileManager.default.fileExists(atPath: url.path + "-shm"),
          "Baseline writing requires a fresh disposable store path.")
        let store = try await StudyStore.open(at: url)
        try await store.populateNativeBaseline()
        let expected = try await store.nativeBaselineState()
        try validateCoverage(expected)
        let manifest = Manifest(
          formatVersion: 1, writerCommit: writerCommit, writerSourceHash: provenance.hash,
          sourcePaths: provenance.paths, schemaKind: "unversioned", accountIDs: accounts,
          expected: expected)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(manifest).write(to: sidecar, options: .atomic)
        print(
          "PASS: baseline writer \(writerCommit), \(expected.records.count) records / 10 model types / 2 accounts"
        )
      } else {
        try require(command == "read-native-baseline", "Unknown baseline operation")
        try require(
          FileManager.default.fileExists(atPath: url.path), "The frozen baseline store is missing.")
        let manifest = try PropertyListDecoder().decode(
          Manifest.self, from: Data(contentsOf: sidecar))
        try require(
          manifest.formatVersion == 1 && manifest.writerCommit == writerCommit
            && manifest.writerSourceHash == writerSourceHash && manifest.schemaKind == "unversioned"
            && manifest.accountIDs == accounts && manifest.sourcePaths.count == 67,
          "Unexpected baseline provenance or format.")
        try validateCoverage(manifest.expected)
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
    private static func sourceProvenance() throws -> (paths: [String], hash: String) {
      let probe = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      let shared = probe.appending(path: "../../../Shared").standardizedFileURL
        .resolvingSymlinksInPath()
      let sourcePrefix = shared.path + "/"
      var paths = ["Package.swift"]
      for directory in ["Sources/StudyCore", "Sources/StudyPersistence"] {
        guard
          let files = FileManager.default.enumerator(
            at: shared.appending(path: directory), includingPropertiesForKeys: [.isRegularFileKey])
        else { throw Failure(description: "Pinned Shared sources are unavailable") }
        for case let file as URL in files where file.pathExtension == "swift" {
          let canonicalFile = file.standardizedFileURL.resolvingSymlinksInPath()
          let values = try canonicalFile.resourceValues(forKeys: [.isRegularFileKey])
          if values.isRegularFile == true {
            try require(
              canonicalFile.path.hasPrefix(sourcePrefix),
              "Pinned Shared sources resolve outside the source root")
            paths.append(String(canonicalFile.path.dropFirst(sourcePrefix.count)))
          }
        }
      }
      paths.sort()
      var digest = SHA256()
      digest.update(data: Data("usagi-native-baseline-source-v1\u{0000}".utf8))
      for path in paths {
        digest.update(data: Data((path + "\u{0000}").utf8))
        digest.update(data: try Data(contentsOf: shared.appending(path: path)))
        digest.update(data: Data([0]))
      }
      return (paths, digest.finalize().map { String(format: "%02x", $0) }.joined())
    }
  }

  extension StudyStore {
    fileprivate func nativeBaselineState() throws -> NativeStoreBaseline.State {
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

    fileprivate func populateNativeBaseline() throws {
      for (index, accountID) in NativeStoreBaseline.accounts.enumerated() {
        let credential = "baseline-credential-\(index)"
        let sourceID = "baseline-source-\(index)"
        let source = nativeBaselineSource(index: index)
        try importLegacyAccount(
          source, sourceID: sourceID, verifiedAccountID: accountID,
          verifiedUsername: source.profile.username, credentialID: credential)
        let identity = WaniKaniAccount(
          id: accountID, username: source.profile.username, level: source.profile.level,
          onVacation: source.profile.vacationStartedAt != nil, startedAt: source.profile.startedAt,
          profile: source.profile)
        let handoff = try prepareLegacyHandoff(
          source, sourceID: sourceID, accountID: accountID, credentialID: credential,
          identity: identity, preferences: .init())
        if index == 0 { _ = try activateLegacyHandoff(handoff) }
        var options = StudySessionOptions()
        options.groupMeaningReading = true
        options.incorrectAnswerDelay = 0
        var session = try StudySession(
          items: [
            source.assignments[0].sessionItem(id: 0, isLesson: false),
            source.assignments[3].sessionItem(id: 1, isLesson: false),
          ], options: options, seed: UInt64(index + 1))
        if let first = session.nextQuestion() {
          _ = try session.mark(index == 0 ? .incorrect : .correct, for: first, now: 100)
          if index == 1, let reading = session.nextQuestion(continuingCurrentItem: true) {
            _ = try session.mark(.incorrect, for: reading, now: 101)
          }
        }
        session.setWrappingUp(true)
        try saveSession(session, accountID: accountID, expectedRevision: nil)
        try transaction {
          let account = try modelContext.fetch(FetchDescriptor<AccountRecord>()).first {
            $0.accountID == accountID
          }!
          account.state.systems = [
            .init(
              id: 1, name: "Baseline SRS", unlockingStage: 0, startingStage: 1,
              passingStage: 5, burningStage: 9,
              stages: (0...9).map {
                .init(position: $0, interval: [0, 9].contains($0) ? nil : 3600)
              })
          ]
          account.state.catalogRefreshID = UUID()
          for row in try materialRecords(accountID: accountID) {
            if row.subjectID == 42 {
              let original = row.material
              row.attemptedRevision = row.revision
              row.attemptedMaterial = original
              row.revision = UUID()
              row.pending = true
              row.material.meaningNote += "\nnewer unsubmitted edit 🐰"
              row.issue = .init(
                reason: .materialChanged, httpStatus: 409,
                serverAssignment: nil, detectedAt: Date(timeIntervalSince1970: 200))
              row.recoveryBaseline = .init(remote: .init(id: 9042, value: original))
            } else if row.subjectID == 43 {
              row.recoveryBaseline = .init(remote: nil)
            }
          }
          if index == 0,
            let review = try modelContext.fetch(FetchDescriptor<ReviewRecord>()).first(where: {
              $0.accountID == accountID && $0.subjectID == 43
            })
          {
            review.originalAssignment = nil
          }
        }
        guard
          let archived = try pendingReviews(accountID: accountID).first(where: {
            $0.subjectID == 44
          })
        else {
          throw NativeStoreBaseline.Failure(
            description: "Missing pending baseline archive review for \(accountID)")
        }
        let assignment = try modelContext.fetch(FetchDescriptor<AssignmentRecord>()).first {
          $0.accountID == accountID && $0.subjectID == 44
        }
        _ = try archiveReview(
          .init(
            id: UUID(), saved: archived, remote: nil, checkedAt: Date(timeIntervalSince1970: 300),
            generation: uploadGeneration, credentialID: credential,
            assignmentRevision: assignment?.revision))
        try recordRateLimit(
          WaniKaniClient.APIError.rateLimited(retryAt: Date(timeIntervalSince1970: 4_102_444_800)),
          accountID: accountID)
      }
      try selectNativeApplication(sourceID: "baseline-fresh-selection")
      try transaction {
        modelContext.insert(
          ImportReceipt(sourceID: "unbound-baseline-source", digest: "unbound-fixture"))
      }
    }

    private func nativeBaselineSource(index: Int) -> LegacyStudyExport {
      var profile = StudyAccountProfile(username: "baseline-user-\(index)")
      profile.level = 4
      profile.maxLevelGranted = 60
      profile.startedAt = 1
      profile.subscribed = true
      profile.subscriptionEndsAt = 4_102_444_800
      profile.vacationStartedAt = index == 0 ? nil : 50
      profile.profileURL = "https://example.invalid/baseline/\(index)"
      var source = LegacyStudyExport(schemaVersion: 15, profile: profile)
      for (offset, id) in (Int64(42)...46).enumerated() {
        let kind: SubjectKind = id == 44 ? .radical : id == 43 || id == 46 ? .vocabulary : .kanji
        var subject = CatalogSubject(id: id, kind: kind)
        subject.level = 4
        subject.hiddenAt = id == 45 ? 15 : nil
        subject.lessonPosition = offset
        subject.spacedRepetitionSystemID = 1
        subject.isKanaOnlyVocabulary = id == 46
        subject.partOfSpeechNames = ["Noun", "Unknown 99"]
        subject.slug = "baseline-\(id)"
        subject.documentURL = "https://example.invalid/subject/\(id)"
        subject.japanese = id == 44 ? "" : id == 46 ? "ねこ" : "猫"
        subject.meanings = [
          .init("Cat \(index)", role: .primary), .init("Kitty", role: .secondary),
          .init("Feline", role: .auxiliaryWhitelist), .init("Dog", role: .blacklist),
        ]
        subject.readings =
          kind == .radical
          ? []
          : [
            .init("ねこ", isPrimary: true, kind: .kunyomi),
            .init("びょう", isPrimary: false, kind: .onyomi),
          ]
        subject.componentSubjectIDs = id == 42 ? [44] : []
        subject.amalgamationSubjectIDs = id == 44 ? [42] : []
        subject.meaningMnemonic = "Meaning <kanji>猫</kanji>\naccount \(index)"
        subject.meaningHint = "Meaning hint"
        subject.readingMnemonic = "Reading mnemonic"
        subject.readingHint = "Reading hint"
        subject.deprecatedMnemonic = "Old mnemonic"
        subject.characterImageURL = id == 44 ? "https://example.invalid/radical.svg" : ""
        subject.hasCharacterImageFile = id == 44
        subject.visuallySimilarKanji = "苗"
        subject.visuallySimilarKanjiIDs = [45]
        subject.sentences = [.init(japanese: "猫です。", english: "It is a cat.")]
        subject.partsOfSpeech = [1, 99]
        subject.audio = [.init(url: "https://example.invalid/\(id).mp3", voiceActorID: 7)]
        source.subjects.append(subject)
        var assignment = CatalogAssignment(id: id + 100, subjectID: id, kind: kind)
        assignment.level = 4
        assignment.srsStage = id == 45 ? 0 : 3
        assignment.availableAt = 100
        assignment.startedAt = id == 45 ? nil : 1
        assignment.unlockedAt = 1
        assignment.passedAt = id == 46 ? 20 : nil
        assignment.burnedAt = id == 46 ? 30 : nil
        assignment.resurrectedAt = id == 46 ? 40 : nil
        assignment.hidden = index == 0 ? false : nil
        assignment.isKanaOnlyVocabulary = id == 46
        source.assignments.append(assignment)
        source.progress.append(
          .init(
            subjectID: id, level: 4, srsStage: assignment.srsStage, kind: kind,
            lastMistakeLocalTime: "2026-10-20 12:34:56", legacyRevision: 8,
            lastMistakeAt: index == 0 ? nil : 1_792_467_296))
        if id == 43 || id == 44 {
          source.pendingReviews.append(
            .init(
              assignment: assignment,
              submission: .init(
                itemID: offset, subjectID: id, assignmentID: assignment.id, isLesson: false,
                meaningWrong: true, readingWrong: kind != .radical,
                meaningWrongCount: 2, readingWrongCount: kind == .radical ? 0 : 1, createdAt: 120)))
        }
        if id <= 44 {
          source.materials.append(
            .init(
              serverID: id + 200,
              value: .init(
                subjectID: id, meaningNote: "  account \(index)\u{0000}note\n猫  ",
                readingNote: "ねこ", meaningSynonyms: ["Kitty", "猫, animal"]),
              pending: id == 43, legacyRevision: 9))
        }
      }
      var level = CatalogLevelProgression(id: 5)
      level.level = 4
      level.createdAt = 1
      level.unlockedAt = 2
      level.startedAt = 3
      level.passedAt = 4
      level.completedAt = 5
      level.abandonedAt = 6
      source.levels = [level]
      var statistic = CatalogReviewStatistic(
        id: 343,
        answers: .init(
          subjectID: 43, type: .vocabulary, meaningCorrect: 9, meaningIncorrect: 2,
          meaningCurrentStreak: 3, readingCorrect: 8, readingIncorrect: 1,
          readingCurrentStreak: 4, hidden: index == 1))
      statistic.createdAt = 10
      statistic.meaningMaxStreak = 5
      statistic.readingMaxStreak = 6
      statistic.percentageCorrect = 85
      source.statistics = [statistic]
      var voice = StudyVoiceActor(id: 7)
      voice.name = "Baseline voice"
      voice.description = "Synthetic voice \(index)"
      voice.gender = 1
      source.voices = [voice]
      source.audio = [
        .init(
          subjectID: 43, voiceActorID: 7, level: 4,
          url: "https://example.invalid/43.mp3")
      ]
      source.cursors = [
        "assignments_updated_after": "2026-10-20T00:00:00Z",
        "subjects_updated_after": "2026-10-19T00:00:00Z",
      ]
      var oldAssignment = CatalogAssignment(id: 141, subjectID: 42, kind: .kanji)
      oldAssignment.level = 4
      oldAssignment.srsStage = 2
      oldAssignment.availableAt = 90
      oldAssignment.startedAt = 1
      source.supersededAssignments = [oldAssignment]
      return source
    }
  }
#endif
