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
import WaniKaniAPI

/// Merge downloaded snapshots without treating unacknowledged local work as disposable cache.
/// Run replacement, inserts and cursor advancement in one database transaction.
enum SyncStore {
  enum Resource { case subjects, voiceActors, statistics }

  static func requestFullRefresh(in db: FMDatabase) {
    db.mustExecuteStatements("""
    UPDATE sync SET assignments_updated_after = '', subjects_updated_after = '',
      voice_actors_updated_after = '', study_materials_updated_after = '',
      review_stats_updated_after = '';
    """)
  }

  static func replaceSnapshot(_ resource: Resource, in db: FMDatabase) {
    switch resource {
    case .subjects:
      db.mustExecuteStatements("DELETE FROM subjects; DELETE FROM audio_urls;")
    case .voiceActors:
      db.mustExecuteStatements("DELETE FROM voice_actors;")
    case .statistics:
      db.mustExecuteStatements("DELETE FROM review_stats;")
    }
  }

  static let localRevisionMigration =
    "ALTER TABLE study_materials ADD COLUMN local_revision INTEGER NOT NULL DEFAULT 0;"

  static func materialVersions(in db: FMDatabase) -> [Int64: Int64] {
    var versions: [Int64: Int64] = [:]
    for row in db.query("SELECT id, local_revision FROM study_materials") {
      versions[row.longLongInt(forColumnIndex: 0)] = row.longLongInt(forColumnIndex: 1)
    }
    return versions
  }

  static func saveLocalMaterial(subjectID: Int64, payload: Data, in db: FMDatabase) {
    db.mustExecuteUpdate("""
    INSERT INTO study_materials (id, pb, local_revision) VALUES (?, ?, 1)
    ON CONFLICT (id) DO UPDATE SET pb = excluded.pb, local_revision = local_revision + 1
    """, args: [subjectID, payload])
    db.mustExecuteUpdate("INSERT OR IGNORE INTO pending_study_materials (id) VALUES (?)",
                         args: [subjectID])
  }

  /// A revision captured before the request protects edits even if they upload before its response.
  static func mergeMaterials(_ materials: [Int64: Data], baseline: [Int64: Int64],
                             replacingAll: Bool, in db: FMDatabase) {
    if replacingAll {
      for (id, revision) in baseline where materials[id] == nil {
        db.mustExecuteUpdate("""
        DELETE FROM study_materials WHERE id = ? AND local_revision = ? AND NOT EXISTS (
          SELECT 1 FROM pending_study_materials WHERE id = ?
        )
        """, args: [id, revision, id])
      }
    }
    for (id, payload) in materials {
      let row = db.query("SELECT local_revision FROM study_materials WHERE id = ?", args: [id])
      let current = row.next() ? row.longLongInt(forColumnIndex: 0) : nil
      row.close()
      if let current, baseline[id] != current { continue }
      db.mustExecuteUpdate("""
      INSERT INTO study_materials (id, pb)
      SELECT ?, ? WHERE NOT EXISTS (SELECT 1 FROM pending_study_materials WHERE id = ?)
      ON CONFLICT (id) DO UPDATE SET pb = excluded.pb
      """, args: [id, payload, id])
    }
  }

  static let progressRevisionMigration =
    "ALTER TABLE subject_progress ADD COLUMN local_revision INTEGER NOT NULL DEFAULT 0;"

  static func assignmentVersions(in db: FMDatabase) -> [Int64: Int64] {
    var versions: [Int64: Int64] = [:]
    for row in db.query("SELECT id, local_revision FROM subject_progress") {
      versions[row.longLongInt(forColumnIndex: 0)] = row.longLongInt(forColumnIndex: 1)
    }
    return versions
  }

  static func saveLocalProgress(_ progress: TKMProgress, srsStage: Int, mistakeTime: String,
                                in db: FMDatabase) {
    let assignment = progress.assignment
    db.mustExecuteUpdate("DELETE FROM assignments WHERE subject_id = ?",
                         args: [assignment.subjectID])
    db.mustExecuteUpdate("REPLACE INTO pending_progress (id, pb) VALUES (?, ?)",
                         args: [assignment.subjectID, try! progress.serializedData()])
    db.mustExecuteUpdate("""
    INSERT INTO subject_progress (id, level, srs_stage, subject_type, last_mistake_time, local_revision)
    VALUES (?, ?, ?, ?, ?, 1) ON CONFLICT (id) DO UPDATE SET level = excluded.level,
      srs_stage = excluded.srs_stage, subject_type = excluded.subject_type,
      last_mistake_time = excluded.last_mistake_time, local_revision = local_revision + 1
    """, args: [assignment.subjectID, assignment.level, srsStage,
                assignment.subjectType.rawValue, mistakeTime])
  }

  static func mergeAssignments(_ assignments: [TKMAssignment], baseline: [Int64: Int64],
                               replacingAll: Bool, in db: FMDatabase) {
    let current = assignmentVersions(in: db)
    let changed = Set(current.keys).union(baseline.keys).filter { current[$0] != baseline[$0] }
    if replacingAll {
      let incoming = Set(assignments.map(\.subjectID))
      var obsolete: [Int64] = []
      for row in db.query("SELECT subject_id FROM assignments") {
        let id = row.longLongInt(forColumnIndex: 0)
        if !incoming.contains(id), !changed.contains(id) { obsolete.append(id) }
      }
      for id in obsolete {
        db.mustExecuteUpdate("DELETE FROM assignments WHERE subject_id = ?", args: [id])
      }
      for id in baseline.keys where !incoming.contains(id) && !changed.contains(id) {
        db.mustExecuteUpdate("""
        DELETE FROM subject_progress WHERE id = ? AND NOT EXISTS (SELECT 1 FROM pending_progress WHERE id = ?)
        """, args: [id, id])
      }
    }
    for assignment in assignments where !changed.contains(assignment.subjectID) {
      mergeAssignment(assignment, in: db)
    }
  }

  private static func mergeAssignment(_ assignment: TKMAssignment, in db: FMDatabase) {
    // A changed server assignment ID must not make a completed-but-pending subject reviewable.
    db.mustExecuteUpdate("DELETE FROM assignments WHERE subject_id = ?",
                         args: [assignment.subjectID])
    let pending = db.query("SELECT 1 FROM pending_progress WHERE id = ?",
                           args: [assignment.subjectID])
    let isPending = pending.next()
    pending.close()
    guard !isPending else { return }
    db.mustExecuteUpdate("INSERT INTO assignments (id, pb, subject_id) VALUES (?, ?, ?)",
                         args: [
                           assignment.id,
                           try! assignment.serializedData(),
                           assignment.subjectID,
                         ])
    db.mustExecuteUpdate("""
    INSERT INTO subject_progress (id, level, srs_stage, subject_type, last_mistake_time)
    VALUES (?, ?, ?, ?, '') ON CONFLICT (id) DO UPDATE SET level = excluded.level,
      srs_stage = excluded.srs_stage, subject_type = excluded.subject_type
    """, args: [assignment.subjectID, assignment.level, assignment.srsStageNumber,
                assignment.subjectType.rawValue])
  }
}
