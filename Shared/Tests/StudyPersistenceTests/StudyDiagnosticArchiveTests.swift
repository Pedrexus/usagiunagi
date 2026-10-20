import Foundation
import StudyCore
import SwiftData
import Testing

@testable import StudyPersistence

struct StudyDiagnosticArchiveTests {
  private let now = Date(timeIntervalSince1970: 2_000_000_000)
  private let account = "diagnostic-account"
  private let sourceID = "/private/diagnostic-source"

  @Test func binaryRoundTripKeepsExactAccountWorkAndExcludesPrivateBindings() async throws {
    let store = try await populated()
    let before = try await store.diagnosticDocument(accountID: account, generatedAt: now)
    let data = try await StudyDiagnosticArchive(store: store, accountID: account).data()
    #expect(data.starts(with: Data("bplist00".utf8)))
    let decoded = try PropertyListDecoder().decode(StudyDiagnosticDocument.self, from: data)
    #expect(decoded.formatVersion == 1 && decoded.accountID == account)
    #expect(decoded.receiptScope == .verifiedAccountHandoffsOnly)
    #expect(try canonical(decoded.account) == canonical(before.account))
    #expect(try canonical(decoded.snapshots) == canonical(before.snapshots))
    #expect(try canonical(decoded.catalog) == canonical(before.catalog))
    #expect(try canonical(decoded.assignments) == canonical(before.assignments))
    #expect(try canonical(decoded.session) == canonical(before.session))
    #expect(try canonical(decoded.reviews) == canonical(before.reviews))
    #expect(try canonical(decoded.materials) == canonical(before.materials))
    #expect(try canonical(decoded.archivedReviews) == canonical(before.archivedReviews))
    #expect(decoded.retryAt == now && decoded.imports.count == 1)
    #expect(decoded.imports[0].sourceDigest == before.imports[0].sourceDigest)
    #expect(!decoded.imports[0].activated)
    #expect(decoded.catalog.count == 3 && decoded.assignments.count == 2)
    #expect(decoded.account.systems?.count == 1 && decoded.account.catalogRefreshID != nil)
    #expect(decoded.account.supersededAssignments.count == 1)
    #expect(decoded.session != nil && decoded.reviews.count == 1)
    #expect(decoded.reviews[0].attempted && decoded.reviews[0].issue?.reason == .uncertain)
    #expect(decoded.materials.count == 3 && decoded.archivedReviews.count == 1)
    #expect(decoded.materials[0].recoveryBaseline == nil)
    #expect(decoded.materials[1].recoveryBaseline != nil)
    #expect(decoded.materials[1].recoveryBaseline?.remote == nil)
    #expect(decoded.materials[2].recoveryBaseline?.remote?.id == 503)
    #expect(decoded.materials[1].attemptedRevision != decoded.materials[1].revision)
    #expect(decoded.materials[1].attemptedMaterial?.meaningNote == "Earlier pending note")
    #expect(decoded.materials[1].value.meaningNote == "Current 未送信 note")
    let text = String(decoding: try canonical(decoded), as: UTF8.self)
    for secret in [
      "credential-secret", "private-preference-email", sourceID,
      "other-person", "unbound-secret", "native-application:",
    ] {
      #expect(!text.contains(secret))
    }
    #expect(!text.contains("credentialID") && !text.contains("unboundCount"))
    let after = try await store.diagnosticDocument(accountID: account, generatedAt: now)
    #expect(try canonical(before) == canonical(after))
  }

  @Test func reopenedStoreAndIndependentExportsPreserveRevisionsAndOldBytes() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let before: StudyDiagnosticDocument
    do {
      let store = try await populated(at: url)
      before = try await store.diagnosticDocument(accountID: account, generatedAt: now)
    }
    let reopened = try await StudyStore.open(at: url)
    let restored = try await reopened.diagnosticDocument(accountID: account, generatedAt: now)
    #expect(try canonical(before) == canonical(restored))
    let archive = StudyDiagnosticArchive(store: reopened, accountID: account)
    let first = try await archive.data()
    let original = try #require(restored.materials.first)
    _ = try await reopened.saveMaterial(
      .init(subjectID: original.value.subjectID, meaningNote: "Later note"), accountID: account,
      expectedRevision: original.revision)
    let second = try await archive.data()
    let firstDocument = try PropertyListDecoder().decode(StudyDiagnosticDocument.self, from: first)
    let secondDocument = try PropertyListDecoder().decode(
      StudyDiagnosticDocument.self, from: second)
    #expect(first != second)
    #expect(firstDocument.materials[0].value == original.value)
    #expect(firstDocument.materials[0].revision == original.revision)
    #expect(secondDocument.materials[0].value.meaningNote == "Later note")
    #expect(secondDocument.materials[0].revision != original.revision)
  }

  @Test func concurrentCommitsCannotMixProgressAndMaterialGenerations() async throws {
    let store = try await populated()
    try await store.setDiagnosticTestGeneration(0, accountID: account)
    async let writes: Void = writeGenerations(in: store)
    for _ in 0..<24 {
      let data = try await StudyDiagnosticArchive(store: store, accountID: account).data()
      let document = try PropertyListDecoder().decode(StudyDiagnosticDocument.self, from: data)
      let progress = try #require(document.account.progress.first)
      #expect(document.materials[0].value.meaningNote == String(progress.legacyRevision))
      #expect(document.reviews[0].attempted && document.materials[1].pending)
      await Task.yield()
    }
    try await writes
  }

  @Test func cancellationAndInvalidAccountsNeverChangeSavedWork() async throws {
    let store = try await populated()
    let before = try await store.diagnosticDocument(accountID: account, generatedAt: now)
    let archive = StudyDiagnosticArchive(store: store, accountID: account)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await archive.data()
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    for id in ["", "missing"] {
      await #expect(throws: StudyStoreError.self) {
        try await StudyDiagnosticArchive(store: store, accountID: id).data()
      }
    }
    let after = try await store.diagnosticDocument(accountID: account, generatedAt: now)
    #expect(try canonical(before) == canonical(after))
    let sample = StudySnapshot(
      accountID: "sample", username: "sample", currentLevel: 1, assignments: [], statistics: [],
      levels: [], subjects: [], isSample: true)
    try await store.insertDiagnosticTestSample(sample)
    await #expect(throws: StudyStoreError.self) {
      try await StudyDiagnosticArchive(store: store, accountID: "sample").data()
    }
  }

  @Test func accountSelectionAndReceiptValidationNeverUsePrefixOwnership() async throws {
    let store = try await populated()
    let selected = StudyDiagnosticArchive(store: store, accountID: account)
    try await store.injectInvalidDiagnosticReceipt(accountID: "diagnostic-account-other")
    let document = try PropertyListDecoder().decode(
      StudyDiagnosticDocument.self, from: await selected.data())
    #expect(document.accountID == account && document.account.profile.username == "person")
    #expect(document.imports.count == 1)
    await #expect(throws: StudyBootstrapError.self) {
      try await StudyDiagnosticArchive(store: store, accountID: "diagnostic-account-other").data()
    }
  }

  private func writeGenerations(in store: StudyStore) async throws {
    for generation in 1...24 {
      try await store.setDiagnosticTestGeneration(generation, accountID: account)
      await Task.yield()
    }
  }
  private func populated(at url: URL? = nil) async throws -> StudyStore {
    let store = try await StudyStore.open(at: url ?? URL(filePath: "/unused"), inMemory: url == nil)
    for (id, name) in [(account, "person"), ("diagnostic-account-other", "other-person")] {
      _ = try await store.importLegacyAccount(
        fixture(username: name), sourceID: sourceID, verifiedAccountID: id,
        verifiedUsername: name, credentialID: "credential-secret-\(id)")
      try await store.enrichDiagnosticTestFixture(accountID: id, sourceID: sourceID, now: now)
    }
    try await store.selectNativeApplication(sourceID: "global-private-source")
    return store
  }
  private func fixture(username: String) -> LegacyStudyExport {
    var profile = StudyAccountProfile(username: username)
    profile.level = 1
    profile.maxLevelGranted = 3
    var source = LegacyStudyExport(schemaVersion: 15, profile: profile)
    for id in Int64(1)...3 {
      var subject = CatalogSubject(id: id, kind: .vocabulary)
      subject.level = 1
      subject.japanese = "猫\(id)"
      subject.meanings = [.init("cat", role: .primary)]
      subject.readings = [.init("ねこ", isPrimary: true, kind: .kunyomi)]
      subject.sentences = [.init(japanese: "猫です。", english: "It is a cat.")]
      source.subjects.append(subject)
      var assignment = CatalogAssignment(id: id + 100, subjectID: id, kind: .vocabulary)
      assignment.level = 1
      assignment.srsStage = 3
      assignment.availableAt = 100
      assignment.startedAt = 10
      source.assignments.append(assignment)
      source.materials.append(
        .init(
          serverID: id + 200,
          value: .init(subjectID: id, meaningNote: id == 2 ? "Current 未送信 note" : "Note"),
          pending: true, legacyRevision: id))
      source.progress.append(
        .init(
          subjectID: id, level: 1, srsStage: 3, kind: .vocabulary,
          lastMistakeLocalTime: "2026-10-20 12:00:00", legacyRevision: id,
          lastMistakeAt: 2_000_000_000))
    }
    source.pendingReviews = [
      .init(
        assignment: source.assignments[1],
        submission: .init(
          itemID: 2, subjectID: 2, assignmentID: 102, isLesson: false,
          meaningWrong: true, readingWrong: false, meaningWrongCount: 2, readingWrongCount: 0,
          createdAt: 2_000_000_000))
    ]
    var level = CatalogLevelProgression(id: 300)
    level.level = 1
    level.startedAt = 10
    source.levels = [level]
    source.statistics = [.init(id: 400, answers: .init(subjectID: 1, type: .vocabulary))]
    var voice = StudyVoiceActor(id: 7)
    voice.name = "Fixture voice"
    source.voices = [voice]
    source.audio = [
      .init(
        subjectID: 1, voiceActorID: 7, level: 1,
        url: "https://example.invalid/cat.mp3")
    ]
    source.cursors = ["subjects_updated_after": "2026-10-20T00:00:00Z"]
    source.supersededAssignments = [source.assignments[0]]
    return source
  }
  private func canonical(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(value)
  }
  private func temporaryFolder() throws -> URL {
    let folder = URL.temporaryDirectory.appending(path: "diagnostic-test-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    return folder
  }
}

extension StudyStore {
  fileprivate func enrichDiagnosticTestFixture(accountID: String, sourceID: String, now: Date)
    throws
  {
    try transaction {
      let account = try #require(
        try modelContext.fetch(
          FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.accountID == accountID })
        ).first)
      var state = account.state
      state.catalogRefreshID = UUID()
      state.systems = [
        .init(
          id: 1, name: "Fixture SRS", unlockingStage: 0, startingStage: 1, passingStage: 2,
          burningStage: 3,
          stages: [
            .init(position: 0, interval: nil),
            .init(position: 1, interval: 3600),
            .init(position: 2, interval: 7200),
            .init(position: 3, interval: nil),
          ])
      ]
      account.state = state
      let materials = try MaterialRecord.fetch(in: modelContext, accountID: accountID)
      let second = try #require(materials.first { $0.subjectID == 2 })
      second.attemptedRevision = UUID()
      second.attemptedMaterial = .init(subjectID: 2, meaningNote: "Earlier pending note")
      second.recoveryBaseline = .init(remote: nil)
      let third = try #require(materials.first { $0.subjectID == 3 })
      third.issue = .init(
        reason: .materialChanged, httpStatus: 409,
        serverAssignment: nil, detectedAt: now)
      third.recoveryBaseline = .init(
        remote: .init(
          id: 503, value: .init(subjectID: 3, meaningNote: "Server note")))
      let review = try #require(try pendingReviews(accountID: accountID).first)
      let record = try #require(try reviewRecord(review))
      record.issue = .init(
        reason: .uncertain, httpStatus: nil,
        serverAssignment: nil, detectedAt: now)
      let archived = ArchivedStudyReview(
        id: UUID(), saved: review, subject: try catalog(accountID: accountID).first?.summary,
        cachedAssignment: review.originalAssignment, cachedProgress: nil,
        observedAssignment: review.originalAssignment, checkedAt: now, archivedAt: now)
      modelContext.insert(ArchivedReviewRecord(archived))
      modelContext.insert(UploadPauseRecord(accountID: accountID, retryAt: now))
      var preferences = LegacyStudyPreferences()
      preferences.customAvatarEmail = "private-preference-email"
      let receiptID = "ios:" + accountID + ":" + sourceID
      let receipt = try #require(
        try modelContext.fetch(
          FetchDescriptor<ImportReceipt>(predicate: #Predicate { $0.sourceID == receiptID })
        ).first)
      receipt.handoff = .init(
        sourceID: sourceID, accountID: accountID,
        credentialID: "credential-secret-\(accountID)", preferences: preferences)
      let unbound = "unbound-secret-" + accountID
      modelContext.insert(ImportReceipt(sourceID: unbound, digest: "unbound-secret"))
      var session = try StudySession(
        items: [
          .init(id: 1, subjectID: 1, assignmentID: 101, srsStage: 3)
        ], seed: .max)
      let nextQuestion = session.nextQuestion()
      let question = try #require(nextQuestion)
      _ = try session.mark(.incorrect, for: question, now: 2_000_000_000)
      modelContext.insert(SessionRecord(accountID: accountID, session: session, revision: UUID()))
    }
  }
  fileprivate func setDiagnosticTestGeneration(_ value: Int, accountID: String) throws {
    try transaction {
      let account = try #require(
        try modelContext.fetch(
          FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.accountID == accountID })
        ).first)
      account.state.progress[0].legacyRevision = Int64(value)
      let material = try #require(
        try MaterialRecord.fetch(in: modelContext, accountID: accountID).first {
          $0.subjectID == 1
        })
      material.material.meaningNote = String(value)
      material.revision = UUID()
    }
  }
  fileprivate func insertDiagnosticTestSample(_ snapshot: StudySnapshot) throws {
    try transaction { modelContext.insert(SnapshotRecord(snapshot, credentialID: "sample")) }
  }
  fileprivate func injectInvalidDiagnosticReceipt(accountID: String) throws {
    try transaction {
      let receipt = ImportReceipt(sourceID: "mismatched-receipt-key", digest: "fixture")
      receipt.handoff = .init(
        sourceID: "different-source", accountID: accountID,
        credentialID: "credential-secret", preferences: nil)
      modelContext.insert(receipt)
    }
  }
}
