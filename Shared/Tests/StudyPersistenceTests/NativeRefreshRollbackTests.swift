import Foundation
import StudyCore
import StudyTestSupport
import SwiftData
import Synchronization
import Testing

@testable import StudyPersistence

private let rollbackAccount = "fixture-user-id"
private let rollbackCredential = "rollback-primary"
private let rollbackOtherAccount = "rollback-other"

private struct RefreshSaveAttempt: Sendable {
  let dirty: Bool
  let insertedCatalog: [Int64]
  let deletedCatalog: [Int64]
  let changedJapanese: String?
  let changedAssignmentStage: Int?
  let changedMaterialNote: String?
  let newAccountLevel: Int?
  let newCursors: [String: String]?
  let newSnapshotLevel: Int?
}

/// Records synchronous save notifications; never substitutes for the real persistent store.
private final class RefreshSaveWitness: Sendable {
  private struct Events: Sendable {
    var attempts: [RefreshSaveAttempt] = []
    var successes = 0
  }
  private let events = Mutex(Events())
  func record(_ attempt: RefreshSaveAttempt) { events.withLock { $0.attempts.append(attempt) } }
  func succeeded() { events.withLock { $0.successes += 1 } }
  var attempts: [RefreshSaveAttempt] { events.withLock { $0.attempts } }
  var successes: Int { events.withLock { $0.successes } }
}

private struct RejectedRefresh: Sendable {
  let error: (any Error)?
  let attempts: [RefreshSaveAttempt]
  let successfulSaves: Int
  let dirtyAfterRollback: Bool
  let restored: [String: Data]
}

struct NativeRefreshRollbackTests {
  @Test func readOnlyDefaultStoreRejectsRefreshAfterDirtyMutationsAndRollsBackAcrossReopen()
    async throws
  {
    let folder = URL.temporaryDirectory.appending(path: "native-refresh-rollback-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let seed = try await seed(at: url)
    let outcome: RejectedRefresh
    do {
      let configuration = ModelConfiguration(
        schema: seed.schema, url: url, allowsSave: false, cloudKitDatabase: .none)
      let container = try ModelContainer(for: seed.schema, configurations: configuration)
      #expect(container.configurations.count == 1)
      #expect(container.configurations.allSatisfy { !$0.allowsSave && !$0.isStoredInMemoryOnly })
      let reader = StudyStore(modelContainer: container)
      #expect(try await reader.refreshRollbackState() == seed.state)
      outcome = try await reader.rejectReadOnlyRefresh(seed.download, baseline: seed.baseline)
    }
    let failure = try #require(outcome.error) as NSError
    #expect(failure.domain == NSCocoaErrorDomain)
    #expect(failure.code == CocoaError.Code.fileWriteNoPermission.rawValue)
    // A read-only/preflight rejection before this real dirty save must fail this test.
    #expect(outcome.attempts.count == 1)
    let attempt = try #require(outcome.attempts.first)
    #expect(attempt.dirty)
    #expect(attempt.insertedCatalog.contains(6) && attempt.deletedCatalog.contains(3))
    #expect(attempt.changedJapanese == "更新")
    #expect(attempt.changedAssignmentStage == 6)
    #expect(attempt.changedMaterialNote == "Changed server material")
    #expect(attempt.newAccountLevel == seed.download.profile.level)
    #expect(attempt.newCursors == seed.download.cursors)
    #expect(attempt.newSnapshotLevel == seed.download.profile.level)
    #expect(outcome.successfulSaves == 0 && !outcome.dirtyAfterRollback)
    #expect(outcome.restored == seed.state)
    let reopened = try await StudyStore.open(at: url)
    #expect(try await reopened.refreshRollbackState() == seed.state)
  }

  private func seed(at url: URL) async throws -> (
    schema: Schema, baseline: RefreshBaseline, state: [String: Data], download: StudyDownload
  ) {
    let initial = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    var source = LegacyStudyExport(schemaVersion: 15, profile: initial.profile)
    source.subjects = initial.subjects
    source.assignments = initial.assignments
    for id: Int64 in [2, 3, 5] {
      let kind = try #require(initial.subjects.first { $0.id == id }).kind
      var assignment = CatalogAssignment(id: 100 + id, subjectID: id, kind: kind)
      assignment.level = 1
      assignment.srsStage = 2
      assignment.startedAt = 1
      assignment.availableAt = 1
      source.assignments.append(assignment)
    }
    source.progress = source.assignments.map {
      .init(
        subjectID: $0.subjectID, level: $0.level, srsStage: $0.srsStage, kind: $0.kind,
        lastMistakeLocalTime: "2026-10-20 10:00:00", legacyRevision: 7, lastMistakeAt: 100)
    }
    source.pendingReviews = [
      .init(
        assignment: source.assignments[0],
        submission: .init(
          itemID: 0, subjectID: 1, assignmentID: 101, isLesson: false,
          meaningWrong: true, readingWrong: false, meaningWrongCount: 2, readingWrongCount: 0,
          createdAt: 200))
    ]
    source.materials = [
      .init(
        serverID: 201,
        value: .init(
          subjectID: 1, meaningNote: "Original server material",
          readingNote: "いち\nExact", meaningSynonyms: ["Single", "一"]), pending: false,
        legacyRevision: 9),
      .init(
        serverID: 203, value: .init(subjectID: 3, meaningNote: "Clean material to prune"),
        pending: false, legacyRevision: 3),
      .init(
        serverID: 205,
        value: .init(
          subjectID: 5, meaningNote: "Pending 🐰\nExact whitespace  ",
          readingNote: "Hidden reading", meaningSynonyms: ["Pending", "一つ"]), pending: true,
        legacyRevision: 8),
    ]
    source.levels = initial.levels
    source.statistics = initial.statistics
    source.voices = initial.voices
    source.audio = StudyAccountState(download: initial).audio
    source.cursors = [
      "subjects_updated_after": "old-subject-cursor",
      "assignments_updated_after": "old-assignment-cursor",
      "study_materials_updated_after": "old-material-cursor",
      "voice_actors_updated_after": "old-voice-cursor",
      "review_stats_updated_after": "old-statistics-cursor",
    ]
    let writer = try await StudyStore.open(at: url)
    _ = try await writer.importLegacyAccount(
      source, sourceID: "rollback-primary",
      verifiedAccountID: rollbackAccount, verifiedUsername: source.profile.username,
      credentialID: rollbackCredential)
    var other = source
    other.profile.username = "Other synthetic account"
    _ = try await writer.importLegacyAccount(
      other, sourceID: "rollback-other",
      verifiedAccountID: rollbackOtherAccount, verifiedUsername: other.profile.username,
      credentialID: "rollback-other")
    let item = try #require(source.assignments.first { $0.subjectID == 5 })
    var session = try StudySession(items: [item.sessionItem(id: 0, isLesson: false)], seed: 1)
    let nextQuestion = session.nextQuestion()
    let question = try #require(nextQuestion)
    _ = try session.mark(.correct, for: question, now: 300)
    #expect(session.completedIDs.isEmpty)
    try await writer.saveSession(session, accountID: rollbackAccount, expectedRevision: nil)
    let state = try await writer.refreshRollbackState()
    let baseline = try await writer.refreshBaseline(accountID: rollbackAccount)
    var profile = initial.profile
    profile.level += 1
    var subjects = initial.subjects.filter { ![Int64(3), 4].contains($0.id) }
    let first = try #require(subjects.firstIndex { $0.id == 1 })
    subjects[first].japanese = "更新"
    var added = CatalogSubject(id: 6, kind: .radical)
    added.level = 1
    added.japanese = "六"
    added.meanings = [.init("Six", role: .primary)]
    subjects.append(added)
    var changed = try #require(source.assignments.first { $0.subjectID == 2 })
    changed.srsStage = 6
    var addedAssignment = CatalogAssignment(id: 106, subjectID: 6, kind: .radical)
    addedAssignment.level = 1
    addedAssignment.srsStage = 2
    addedAssignment.startedAt = 1
    addedAssignment.availableAt = 1
    let download = StudyDownload(
      accountID: rollbackAccount, profile: profile, subjects: subjects,
      assignments: [source.assignments[0], changed, item, addedAssignment],
      materials: [
        .init(id: 201, value: .init(subjectID: 1, meaningNote: "Changed server material")),
        .init(id: 206, value: .init(subjectID: 6, meaningNote: "Inserted server material")),
      ],
      levels: [], statistics: [], voices: [], systems: initial.systems,
      cursors: ["synthetic-subject-cursor": SubjectCacheFixture.changedAt],
      fetchedAt: .now.addingTimeInterval(60))
    return (writer.modelContainer.schema, baseline, state, download)
  }
}

extension StudyStore {
  fileprivate func rejectReadOnlyRefresh(_ download: StudyDownload, baseline: RefreshBaseline)
    throws -> RejectedRefresh
  {
    let witness = RefreshSaveWitness()
    let center = NotificationCenter.default
    let willSave = center.addObserver(
      forName: ModelContext.willSave, object: modelContext, queue: nil
    ) { notification in
      guard let context = notification.object as? ModelContext else { return }
      let modified = context.changedModelsArray + context.insertedModelsArray
      let account = modified.compactMap { $0 as? AccountRecord }.first {
        $0.accountID == rollbackAccount
      }
      witness.record(
        .init(
          dirty: context.hasChanges,
          insertedCatalog: context.insertedModelsArray.compactMap {
            ($0 as? CatalogRecord)?.subjectID
          },
          deletedCatalog: context.deletedModelsArray.compactMap {
            ($0 as? CatalogRecord)?.subjectID
          },
          changedJapanese: modified.compactMap { $0 as? CatalogRecord }.first {
            $0.accountID == rollbackAccount && $0.subjectID == 1
          }?.subject.japanese,
          changedAssignmentStage: modified.compactMap { $0 as? AssignmentRecord }.first {
            $0.accountID == rollbackAccount && $0.subjectID == 2
          }?.assignment.srsStage,
          changedMaterialNote: modified.compactMap { $0 as? MaterialRecord }.first {
            $0.accountID == rollbackAccount && $0.subjectID == 1
          }?.material.meaningNote,
          newAccountLevel: account?.state.profile.level,
          newCursors: account?.state.cursors,
          newSnapshotLevel: modified.compactMap { $0 as? SnapshotRecord }.first {
            $0.credentialID == rollbackCredential
          }?.snapshot.currentLevel))
    }
    let didSave = center.addObserver(
      forName: ModelContext.didSave, object: modelContext, queue: nil
    ) { _ in witness.succeeded() }
    defer {
      center.removeObserver(willSave)
      center.removeObserver(didSave)
    }
    let failure: (any Error)?
    do {
      _ = try applyDownload(download, credentialID: rollbackCredential, baseline: baseline)
      failure = nil
    } catch { failure = error }
    return .init(
      error: failure, attempts: witness.attempts, successfulSaves: witness.successes,
      dirtyAfterRollback: modelContext.hasChanges, restored: try refreshRollbackState())
  }

  /// Canonical domain values include every field refreshed or protected by the native transaction.
  fileprivate func refreshRollbackState() throws -> [String: Data] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    var state: [String: Data] = [:]
    for accountID in [rollbackAccount, rollbackOtherAccount] {
      state["catalog/\(accountID)"] = try encoder.encode(catalog(accountID: accountID))
      state["assignments/\(accountID)"] = try encoder.encode(assignments(accountID: accountID))
      state["account/\(accountID)"] = try encoder.encode(accountState(accountID: accountID))
      state["reviews/\(accountID)"] = try encoder.encode(pendingReviews(accountID: accountID))
    }
    for row in try modelContext.fetch(FetchDescriptor<SnapshotRecord>()) {
      state["snapshot/\(row.credentialID)"] = try encoder.encode(row.snapshot)
    }
    for row in try modelContext.fetch(FetchDescriptor<SessionRecord>()) {
      state["session/\(row.accountID)"] = try encoder.encode(row.session)
      state["sessionRevision/\(row.accountID)"] = try encoder.encode(row.revision)
    }
    for row in try modelContext.fetch(FetchDescriptor<MaterialRecord>()) {
      let key = "material/\(row.accountID)/\(row.subjectID)"
      state[key] = try encoder.encode(row.material)
      state[key + "/revision"] = try encoder.encode(row.revision)
      state[key + "/pending"] = try encoder.encode(row.pending)
      state[key + "/serverID"] = try encoder.encode(row.serverID)
      state[key + "/attemptedRevision"] = try encoder.encode(row.attemptedRevision)
      state[key + "/attemptedMaterial"] = try encoder.encode(row.attemptedMaterial)
      state[key + "/issue"] = try encoder.encode(row.issue)
      state[key + "/recoveryBaseline"] = try encoder.encode(row.recoveryBaseline)
    }
    return state
  }
}
