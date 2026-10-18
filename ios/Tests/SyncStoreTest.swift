// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import FMDB
import Foundation
import StudyCore
import Testing
import WaniKaniAPI
import XCTest

private func database(path: String = ":memory:") -> FMDatabase {
  let db = FMDatabase(path: path)
  XCTAssertTrue(db.open())
  db.mustExecuteStatements(
    """
    CREATE TABLE IF NOT EXISTS sync (assignments_updated_after TEXT, subjects_updated_after TEXT,
      voice_actors_updated_after TEXT, study_materials_updated_after TEXT, review_stats_updated_after TEXT);
    CREATE TABLE IF NOT EXISTS assignments (id INTEGER PRIMARY KEY, subject_id INTEGER, pb BLOB);
    CREATE TABLE IF NOT EXISTS subject_progress (id INTEGER PRIMARY KEY, level INTEGER,
      srs_stage INTEGER, subject_type INTEGER, last_mistake_time TEXT, local_revision INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS pending_progress (id INTEGER PRIMARY KEY, pb BLOB);
    CREATE TABLE IF NOT EXISTS study_materials (id INTEGER PRIMARY KEY, pb BLOB, local_revision INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS pending_study_materials (id INTEGER PRIMARY KEY);
    CREATE TABLE IF NOT EXISTS subjects (id INTEGER PRIMARY KEY, pb BLOB);
    CREATE TABLE IF NOT EXISTS user (id INTEGER PRIMARY KEY, pb BLOB);
    CREATE TABLE IF NOT EXISTS audio_urls (subject_id INTEGER, url TEXT);
    CREATE TABLE IF NOT EXISTS voice_actors (id INTEGER PRIMARY KEY, pb BLOB);
    CREATE TABLE IF NOT EXISTS review_stats (id INTEGER PRIMARY KEY, pb BLOB);
    """)
  return db
}

final class SyncStoreTest: XCTestCase {
  private func scalar(_ sql: String, db: FMDatabase) -> String? {
    let row = db.query(sql)
    defer { row.close() }
    return row.next() ? row.string(forColumnIndex: 0) : nil
  }

  private func assignment(id: Int64, subjectID: Int64, stage: Int32) -> TKMAssignment {
    var value = TKMAssignment()
    value.id = id
    value.subjectID = subjectID
    value.srsStageNumber = stage
    value.subjectType = .kanji
    value.level = 1
    return value
  }

  func testRequestingFullRefreshRetainsOfflineSnapshotsAndPendingEdits() {
    let db = database()
    defer { db.close() }
    db.mustExecuteStatements(
      """
      INSERT INTO sync VALUES ('a','s','v','m','r');
      INSERT INTO assignments VALUES (1,42,X'01');
      INSERT INTO subject_progress (id,level,srs_stage,subject_type,last_mistake_time) VALUES (42,1,5,2,'yesterday');
      INSERT INTO subjects VALUES (42,X'02');
      INSERT INTO study_materials (id, pb) VALUES (42,X'03');
      INSERT INTO pending_study_materials VALUES (42);
      INSERT INTO pending_progress VALUES (43,X'04');
      """)
    SyncStore.requestFullRefresh(in: db)
    for column in ["assignments", "subjects", "voice_actors", "study_materials", "review_stats"] {
      XCTAssertEqual(scalar("SELECT \(column)_updated_after FROM sync", db: db), "")
    }
    for table in [
      "assignments",
      "subject_progress",
      "subjects",
      "study_materials",
      "pending_progress",
    ] {
      XCTAssertEqual(scalar("SELECT count(*) FROM \(table)", db: db), "1")
    }
    XCTAssertEqual(
      PendingUploadStore
        .payload(for: .init(kind: .studyMaterial, subjectID: 42), in: db),
      Data([3]))
  }

  func testMaterialSnapshotAndStaleDownloadPreservePendingBytesAcrossRestart() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let db = database(path: url.path)
    db.mustExecuteStatements(
      """
      INSERT INTO study_materials (id, pb) VALUES (42,X'0102'),(43,X'03');
      INSERT INTO pending_study_materials VALUES (42);
      """)
    XCTAssertTrue(db.beginTransaction())
    SyncStore.mergeMaterials(
      [42: Data([9]), 44: Data([4])],
      baseline: SyncStore.materialVersions(in: db), replacingAll: true,
      in: db)
    XCTAssertTrue(db.commit())
    XCTAssertEqual(scalar("SELECT count(*) FROM study_materials", db: db), "2")
    XCTAssertTrue(db.close())
    let reopened = database(path: url.path)
    defer { reopened.close() }
    let key = PendingUploadKey(kind: .studyMaterial, subjectID: 42)
    XCTAssertEqual(PendingUploadStore.payload(for: key, in: reopened), Data([1, 2]))
    PendingUploadStore.acknowledge(key, payload: Data([1, 2]), in: reopened)
    SyncStore.mergeMaterials(
      [42: Data([5])], baseline: SyncStore.materialVersions(in: reopened),
      replacingAll: false, in: reopened)
    XCTAssertEqual(scalar("SELECT hex(pb) FROM study_materials WHERE id = 42", db: reopened), "05")
  }

  func testAssignmentSnapshotKeepsPendingProgressAndMistakeDatesWithoutDuplicateReviews() {
    let db = database()
    defer { db.close() }
    db.mustExecuteStatements(
      """
      INSERT INTO subject_progress (id,level,srs_stage,subject_type,last_mistake_time) VALUES (42,1,5,2,'local mistake'),(43,1,2,2,'keep me'),(44,1,3,2,'obsolete');
      INSERT INTO assignments VALUES (100,42,X'01'),(101,43,X'02'),(102,44,X'03');
      INSERT INTO pending_progress VALUES (42,X'04');
      """)
    SyncStore.mergeAssignments(
      [
        assignment(id: 200, subjectID: 42, stage: 2),
        assignment(
          id: 201,
          subjectID: 43,
          stage: 4),
      ],
      baseline: SyncStore.assignmentVersions(in: db), replacingAll: true,
      in: db)
    XCTAssertEqual(scalar("SELECT count(*) FROM assignments", db: db), "1")
    XCTAssertEqual(scalar("SELECT id FROM assignments WHERE subject_id = 43", db: db), "201")
    XCTAssertEqual(scalar("SELECT srs_stage FROM subject_progress WHERE id = 42", db: db), "5")
    XCTAssertEqual(
      scalar("SELECT last_mistake_time FROM subject_progress WHERE id = 43", db: db),
      "keep me")
    XCTAssertEqual(scalar("SELECT srs_stage FROM subject_progress WHERE id = 43", db: db), "4")
    XCTAssertEqual(scalar("SELECT count(*) FROM subject_progress", db: db), "2")
    XCTAssertEqual(scalar("SELECT count(*) FROM pending_progress", db: db), "1")
  }

  func testIncrementalAssignmentRemovesReplacedIDsButDoesNotResurrectPendingSubjects() {
    let db = database()
    defer { db.close() }
    SyncStore.mergeAssignments(
      [assignment(id: 100, subjectID: 42, stage: 3)],
      baseline: SyncStore.assignmentVersions(in: db), replacingAll: false,
      in: db)
    SyncStore.mergeAssignments(
      [assignment(id: 200, subjectID: 42, stage: 4)],
      baseline: SyncStore.assignmentVersions(in: db), replacingAll: false,
      in: db)
    XCTAssertEqual(scalar("SELECT count(*) FROM assignments", db: db), "1")
    db.mustExecuteStatements("INSERT INTO pending_progress VALUES (42,X'01');")
    SyncStore.mergeAssignments(
      [assignment(id: 300, subjectID: 42, stage: 1)],
      baseline: SyncStore.assignmentVersions(in: db), replacingAll: false,
      in: db)
    XCTAssertEqual(scalar("SELECT count(*) FROM assignments", db: db), "0")
    XCTAssertEqual(scalar("SELECT srs_stage FROM subject_progress WHERE id = 42", db: db), "4")
  }

  func testSnapshotTransactionRollbackRetainsCacheAndCursor() {
    let db = database()
    defer { db.close() }
    db
      .mustExecuteStatements(
        "INSERT INTO sync VALUES ('a','s','v','m','r'); INSERT INTO study_materials (id, pb) VALUES (42,X'01');"
      )
    XCTAssertTrue(db.beginTransaction())
    SyncStore.mergeMaterials(
      [43: Data([2])], baseline: SyncStore.materialVersions(in: db),
      replacingAll: true, in: db)
    db.mustExecuteUpdate("UPDATE sync SET study_materials_updated_after = 'new'")
    XCTAssertTrue(db.rollback())
    XCTAssertEqual(scalar("SELECT id FROM study_materials", db: db), "42")
    XCTAssertEqual(scalar("SELECT study_materials_updated_after FROM sync", db: db), "m")
  }

  func testFullCatalogReplacementRemovesObsoleteMetadata() {
    let db = database()
    defer { db.close() }
    db.mustExecuteStatements(
      """
      INSERT INTO subjects VALUES (42,X'01'); INSERT INTO audio_urls VALUES (42,'old');
      INSERT INTO voice_actors VALUES (1,X'02'); INSERT INTO review_stats VALUES (2,X'03');
      """)
    SyncStore.replaceSnapshot(.subjects, in: db)
    SyncStore.replaceSnapshot(.voiceActors, in: db)
    SyncStore.replaceSnapshot(.statistics, in: db)
    for table in ["subjects", "audio_urls", "voice_actors", "review_stats"] {
      XCTAssertEqual(scalar("SELECT count(*) FROM \(table)", db: db), "0")
    }
  }

  func testInvalidatedDownloadCannotTouchClosedDatabase() {
    let db = database()
    let lifetime = UploadLifetime()
    lifetime.invalidate()
    XCTAssertTrue(db.close())
    XCTAssertThrowsError(
      try lifetime.withActive {
        SyncStore.mergeMaterials([42: Data([1])], baseline: [:], replacingAll: false, in: db)
      }
    ) { XCTAssertTrue($0 is CancellationError) }
  }

  func testAcknowledgedEditStillWinsOverEarlierDownloadIncludingFullSnapshotPruning() {
    for full in [false, true] {
      let db = database()
      defer { db.close() }
      db.mustExecuteStatements("INSERT INTO study_materials (id, pb) VALUES (42,X'01'),(43,X'02');")
      let baseline = SyncStore.materialVersions(in: db)
      for id: Int64 in [42, 43, 44] {
        SyncStore.saveLocalMaterial(subjectID: id, payload: Data([9]), in: db)
        PendingUploadStore.acknowledge(
          .init(kind: .studyMaterial, subjectID: id),
          payload: Data([9]), in: db)
      }
      SyncStore.mergeMaterials([42: Data([5])], baseline: baseline, replacingAll: full, in: db)
      for id in [42, 43, 44] {
        XCTAssertEqual(scalar("SELECT hex(pb) FROM study_materials WHERE id = \(id)", db: db), "09")
      }
    }
  }

  func testChangingAnEditBackToOriginalBytesStillProtectsItFromAnEarlierResponse() {
    let db = database()
    defer { db.close() }
    db.mustExecuteStatements("INSERT INTO study_materials (id, pb) VALUES (42,X'01');")
    let baseline = SyncStore.materialVersions(in: db)
    SyncStore.saveLocalMaterial(subjectID: 42, payload: Data([2]), in: db)
    SyncStore.saveLocalMaterial(subjectID: 42, payload: Data([1]), in: db)
    PendingUploadStore.acknowledge(
      .init(kind: .studyMaterial, subjectID: 42), payload: Data([1]),
      in: db)
    SyncStore.mergeMaterials([42: Data([3])], baseline: baseline, replacingAll: false, in: db)
    XCTAssertEqual(scalar("SELECT hex(pb) FROM study_materials WHERE id = 42", db: db), "01")
    XCTAssertEqual(SyncStore.materialVersions(in: db)[42], 2)
  }

  func testLocalRevisionMigrationPreservesExistingBytesAndRollsBackAtomically() {
    let db = FMDatabase(path: ":memory:")
    XCTAssertTrue(db.open())
    defer { db.close() }
    db
      .mustExecuteStatements(
        "CREATE TABLE study_materials(id INTEGER PRIMARY KEY, pb BLOB); INSERT INTO study_materials VALUES (42,X'0102'); PRAGMA user_version = 13;"
      )
    XCTAssertTrue(db.beginTransaction())
    db.mustExecuteStatements(SyncStore.localRevisionMigration)
    db.mustExecuteStatements("PRAGMA user_version = 14;")
    XCTAssertTrue(db.rollback())
    XCTAssertEqual(db.userVersion, 13)
    XCTAssertFalse(db.columnExists("local_revision", inTableWithName: "study_materials"))
    XCTAssertTrue(db.beginTransaction())
    db.mustExecuteStatements(SyncStore.localRevisionMigration)
    db.mustExecuteStatements("PRAGMA user_version = 14;")
    XCTAssertTrue(db.commit())
    XCTAssertEqual(db.userVersion, 14)
    XCTAssertEqual(SyncStore.materialVersions(in: db)[42], 0)
    XCTAssertEqual(scalar("SELECT hex(pb) FROM study_materials WHERE id = 42", db: db), "0102")
  }

  func testAcknowledgedReviewCannotBeResurrectedByAnOlderAssignmentSnapshot() throws {
    for full in [false, true] {
      let db = database()
      defer { db.close() }
      let old = assignment(id: 100, subjectID: 42, stage: 3)
      SyncStore.mergeAssignments([old], baseline: [:], replacingAll: false, in: db)
      let baseline = SyncStore.assignmentVersions(in: db)
      var progress = TKMProgress()
      progress.assignment = old
      progress.createdAt = 123
      SyncStore.saveLocalProgress(progress, srsStage: 4, mistakeTime: "", in: db)
      try PendingUploadStore.acknowledge(
        .init(kind: .progress, subjectID: 42),
        payload: progress.serializedData(), in: db)
      SyncStore.mergeAssignments([old], baseline: baseline, replacingAll: full, in: db)
      XCTAssertEqual(scalar("SELECT count(*) FROM assignments", db: db), "0")
      XCTAssertEqual(scalar("SELECT srs_stage FROM subject_progress WHERE id = 42", db: db), "4")
      // Even an empty full response that started before the review cannot erase its local progress.
      SyncStore.mergeAssignments([], baseline: baseline, replacingAll: true, in: db)
      XCTAssertEqual(scalar("SELECT count(*) FROM subject_progress", db: db), "1")
      // A request started after the review can apply the authoritative server assignment.
      SyncStore.mergeAssignments(
        [assignment(id: 100, subjectID: 42, stage: 4)],
        baseline: SyncStore.assignmentVersions(in: db),
        replacingAll: false, in: db)
      XCTAssertEqual(scalar("SELECT count(*) FROM assignments", db: db), "1")
    }
  }

  func testProgressRevisionMigrationPreservesExistingState() {
    let db = FMDatabase(path: ":memory:")
    XCTAssertTrue(db.open())
    defer { db.close() }
    db
      .mustExecuteStatements(
        "CREATE TABLE subject_progress (id INTEGER PRIMARY KEY, srs_stage INTEGER, last_mistake_time TEXT); INSERT INTO subject_progress VALUES (42,5,'yesterday'); PRAGMA user_version = 14;"
      )
    XCTAssertTrue(db.beginTransaction())
    db.mustExecuteStatements(SyncStore.progressRevisionMigration)
    db.mustExecuteStatements("PRAGMA user_version = 15;")
    XCTAssertTrue(db.rollback())
    XCTAssertEqual(db.userVersion, 14)
    XCTAssertFalse(db.columnExists("local_revision", inTableWithName: "subject_progress"))
    db.mustExecuteStatements(SyncStore.progressRevisionMigration)
    XCTAssertEqual(SyncStore.assignmentVersions(in: db)[42], 0)
    XCTAssertEqual(scalar("SELECT srs_stage FROM subject_progress WHERE id = 42", db: db), "5")
    XCTAssertEqual(
      scalar("SELECT last_mistake_time FROM subject_progress WHERE id = 42", db: db),
      "yesterday")
  }
}

@Suite struct MaterialEditorStoreTests {
  private func setUser(_ name: String, in db: FMDatabase) throws {
    var user = TKMUser()
    user.username = name
    db.mustExecuteUpdate(
      "INSERT OR REPLACE INTO user (id, pb) VALUES (0, ?)", args: [try user.serializedData()])
  }

  @Test func editsPreserveServerIdentityAndDoNotQueueUnchangedNotes() throws {
    let db = database()
    defer { db.close() }
    try setUser("Fred", in: db)
    let empty = StudyMaterial(subjectID: 42)
    #expect(
      SyncStore.saveEditedMaterial(empty, expectedRevision: nil, account: "Fred", in: db)
        == .unchanged)
    #expect(
      PendingUploadStore.payload(for: .init(kind: .studyMaterial, subjectID: 42), in: db) == nil)
    var saved = TKMStudyMaterials()
    saved.id = 99
    saved.subjectID = 42
    saved.meaningNote = "old"
    saved.readingNote = "exact\nreading"
    saved.meaningSynonyms = ["Existing"]
    db.mustExecuteUpdate(
      "INSERT INTO study_materials (id,pb,local_revision) VALUES (42,?,7)",
      args: [try saved.serializedData()])
    let draft = StudyMaterial(
      subjectID: 42, meaningNote: "  私\n#tsurukameExclude", readingNote: saved.readingNote,
      meaningSynonyms: ["  Exact  ", "別"])
    var expected = saved
    expected.meaningNote = draft.meaningNote
    expected.meaningSynonyms = draft.meaningSynonyms
    #expect(
      SyncStore.saveEditedMaterial(draft, expectedRevision: 7, account: "Fred", in: db)
        == .changed(expected))
    #expect(SyncStore.materialVersions(in: db)[42] == 8)
    #expect(
      PendingUploadStore.payload(for: .init(kind: .studyMaterial, subjectID: 42), in: db)
        == (try expected.serializedData()))
    #expect(
      SyncStore.saveEditedMaterial(draft, expectedRevision: 8, account: "Fred", in: db)
        == .unchanged)
    #expect(SyncStore.materialVersions(in: db)[42] == 8)
  }

  @Test func changedAccountAndStaleEditorLeaveTheNewerPendingPayloadIntact() throws {
    let db = database()
    defer { db.close() }
    try setUser("Fred", in: db)
    var saved = TKMStudyMaterials()
    saved.subjectID = 42
    saved.meaningNote = "first"
    SyncStore.saveLocalMaterial(subjectID: 42, payload: try saved.serializedData(), in: db)
    saved.meaningNote = "newer"
    saved.readingNote = "hidden newer reading"
    let bytes = try saved.serializedData()
    SyncStore.saveLocalMaterial(subjectID: 42, payload: bytes, in: db)
    let stale = StudyMaterial(subjectID: 42, meaningNote: "old editor")
    #expect(
      SyncStore.saveEditedMaterial(stale, expectedRevision: 1, account: "Fred", in: db) == .stale)
    try setUser("Different account", in: db)
    #expect(
      SyncStore.saveEditedMaterial(stale, expectedRevision: 2, account: "Fred", in: db)
        == .accountChanged)
    #expect(SyncStore.materialVersions(in: db)[42] == 2)
    #expect(
      PendingUploadStore.payload(for: .init(kind: .studyMaterial, subjectID: 42), in: db) == bytes)
  }

  @Test func anObservedMissingOrDeletedMaterialCannotReplaceAnotherVersion() throws {
    let db = database()
    defer { db.close() }
    try setUser("Fred", in: db)
    let draft = StudyMaterial(subjectID: 42, meaningNote: "draft")
    guard
      case .changed = SyncStore.saveEditedMaterial(
        draft, expectedRevision: nil, account: "Fred", in: db)
    else {
      Issue.record("A fresh edit was not saved")
      return
    }
    #expect(
      SyncStore.saveEditedMaterial(draft, expectedRevision: nil, account: "Fred", in: db) == .stale)
    db.mustExecuteStatements("DELETE FROM pending_study_materials; DELETE FROM study_materials;")
    #expect(
      SyncStore.saveEditedMaterial(draft, expectedRevision: 1, account: "Fred", in: db) == .stale)
    #expect(SyncStore.materialVersions(in: db).isEmpty)
  }
}
