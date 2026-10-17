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
import WaniKaniAPI
import XCTest

final class PendingUploadAcknowledgementTest: XCTestCase {
  private func database(at path: String = ":memory:") -> FMDatabase {
    let db = FMDatabase(path: path)
    XCTAssertTrue(db.open())
    db.mustExecuteStatements("""
    CREATE TABLE IF NOT EXISTS pending_progress (id INTEGER PRIMARY KEY, pb BLOB);
    CREATE TABLE IF NOT EXISTS study_materials (id INTEGER PRIMARY KEY, pb BLOB);
    CREATE TABLE IF NOT EXISTS pending_study_materials (id INTEGER PRIMARY KEY);
    """)
    return db
  }

  private func progress(subject: Int64 = 42, date: Int32 = 1) -> TKMProgress {
    var value = TKMProgress()
    value.assignment.subjectID = subject
    value.assignment.id = 100
    value.createdAt = date
    value.meaningWrong = false
    value.readingWrong = false
    return value
  }

  private func store(_ progress: TKMProgress, in db: FMDatabase) throws {
    try db.mustExecuteUpdate("REPLACE INTO pending_progress (id, pb) VALUES (?, ?)",
                             args: [progress.assignment.subjectID, progress.serializedData()])
  }

  private func store(_ material: TKMStudyMaterials, in db: FMDatabase) throws {
    try db.mustExecuteUpdate("REPLACE INTO study_materials (id, pb) VALUES (?, ?)",
                             args: [material.subjectID, material.serializedData()])
    db.mustExecuteUpdate("REPLACE INTO pending_study_materials (id) VALUES (?)",
                         args: [material.subjectID])
  }

  private func count(_ table: String, in db: FMDatabase) -> Int {
    let result = db.query("SELECT COUNT(*) FROM \(table)")
    defer { result.close() }
    XCTAssertTrue(result.next())
    return Int(result.int(forColumnIndex: 0))
  }

  func testMatchingAndRepeatedProgressAcknowledgements() throws {
    let db = database()
    defer { db.close() }
    let sent = progress()
    try store(sent, in: db)
    try store(progress(subject: 43), in: db)
    try PendingUploadStore.acknowledge(.init(kind: .progress, subjectID: sent.assignment.subjectID),
                                       payload: sent.serializedData(), in: db)
    XCTAssertEqual(count("pending_progress", in: db), 1)
    try PendingUploadStore.acknowledge(.init(kind: .progress, subjectID: sent.assignment.subjectID),
                                       payload: sent.serializedData(), in: db)
    XCTAssertEqual(count("pending_progress", in: db), 1)
  }

  func testOldProgressAcknowledgementPreservesNewerPayloadAfterRestart() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let old = progress()
    let newer = progress(date: 2)
    let db = database(at: url.path)
    try store(old, in: db)
    try store(newer, in: db)
    XCTAssertTrue(db.close())

    let reopened = database(at: url.path)
    defer { reopened.close() }
    try PendingUploadStore.acknowledge(.init(kind: .progress, subjectID: old.assignment.subjectID),
                                       payload: old.serializedData(), in: reopened)
    XCTAssertEqual(count("pending_progress", in: reopened), 1)
    let row = reopened.query("SELECT pb FROM pending_progress WHERE id = ?", args: [42])
    XCTAssertTrue(row.next())
    XCTAssertEqual(row.data(forColumnIndex: 0), try newer.serializedData())
    row.close()
    try PendingUploadStore
      .acknowledge(.init(kind: .progress, subjectID: newer.assignment.subjectID),
                   payload: newer.serializedData(), in: reopened)
    XCTAssertEqual(count("pending_progress", in: reopened), 0)
  }

  func testOldMaterialAcknowledgementPreservesNewSynonymAndNotes() throws {
    let db = database()
    defer { db.close() }
    var old = TKMStudyMaterials()
    old.subjectID = 42
    old.meaningSynonyms = ["One"]
    var newer = old
    newer.meaningSynonyms = ["One", "Unity"]
    newer.meaningNote = "A new note"
    try store(old, in: db)
    try store(newer, in: db)
    try PendingUploadStore.acknowledge(.init(kind: .studyMaterial, subjectID: old.subjectID),
                                       payload: old.serializedData(), in: db)
    XCTAssertEqual(count("pending_study_materials", in: db), 1)
    try PendingUploadStore.acknowledge(.init(kind: .studyMaterial, subjectID: newer.subjectID),
                                       payload: newer.serializedData(), in: db)
    XCTAssertEqual(count("pending_study_materials", in: db), 0)
    XCTAssertEqual(count("study_materials", in: db),
                   1) // Acknowledgement never deletes local notes.
    try PendingUploadStore.acknowledge(.init(kind: .studyMaterial, subjectID: newer.subjectID),
                                       payload: newer.serializedData(), in: db)
    XCTAssertEqual(count("pending_study_materials", in: db), 0)
  }

  @MainActor
  func testSerializedUploadsReloadSQLiteAndPreserveInFlightEdits() async throws {
    let db = database()
    defer { db.close() }
    let key = PendingUploadKey(kind: .studyMaterial, subjectID: 42)
    var old = TKMStudyMaterials()
    old.subjectID = 42
    old.meaningNote = "Original note"
    var newer = old
    newer.meaningNote = "Edited during upload"
    newer.meaningSynonyms = ["Unity"]
    try store(old, in: db)
    let started = expectation(description: "First upload is in flight")
    var release: CheckedContinuation<Void, Never>?
    var sent: [TKMStudyMaterials] = []
    let repository = UploadRepository(lifetime: UploadLifetime(), load: { @MainActor key in
      PendingUploadStore.payload(for: key, in: db)
    }, send: { @MainActor _, payload in
      try sent.append(TKMStudyMaterials(serializedData: payload))
      if sent.count == 1 {
        await withCheckedContinuation { continuation in
          release = continuation
          started.fulfill()
        }
      }
    }, acknowledge: { @MainActor key, payload in
      PendingUploadStore.acknowledge(key, payload: payload, in: db)
    })
    let queue = UploadCoordinator()
    let first = await queue.enqueue([key], repository: repository)
    await fulfillment(of: [started], timeout: 5)
    try store(newer, in: db)
    let second = await queue.enqueue([key], repository: repository)
    let duplicate = await queue.enqueue([key], repository: repository)
    release?.resume()
    try await first.value
    try await second.value
    try await duplicate.value
    XCTAssertEqual(sent, [old, newer])
    XCTAssertEqual(count("pending_study_materials", in: db), 0)
    XCTAssertNil(PendingUploadStore.payload(for: key, in: db))
    XCTAssertEqual(count("study_materials", in: db), 1)
    let row = db.query("SELECT pb FROM study_materials WHERE id = ?", args: [42])
    defer { row.close() }
    XCTAssertTrue(row.next())
    XCTAssertEqual(row.data(forColumnIndex: 0), try newer.serializedData())
  }
}
