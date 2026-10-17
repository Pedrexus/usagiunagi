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

/// A response acknowledges the submitted version, never a newer edit with the same subject ID.
/// Keep these conditional deletes inside the caller's database transaction.
enum PendingUploadStore {
  static func payload(for key: PendingUploadKey, in db: FMDatabase) -> Data? {
    let query: String
    switch key.kind {
    case .progress: query = "SELECT pb FROM pending_progress WHERE id = ?"
    case .studyMaterial:
      query =
        "SELECT s.pb FROM study_materials s JOIN pending_study_materials p ON s.id = p.id WHERE s.id = ?"
    }
    let row = db.query(query, args: [key.subjectID])
    defer { row.close() }
    return row.next() ? row.data(forColumnIndex: 0) : nil
  }

  static func acknowledge(_ key: PendingUploadKey, payload: Data, in db: FMDatabase) {
    switch key.kind {
    case .progress:
      db.mustExecuteUpdate("DELETE FROM pending_progress WHERE id = ? AND pb = ?",
                           args: [key.subjectID, payload])
    case .studyMaterial:
      db.mustExecuteUpdate("""
      DELETE FROM pending_study_materials WHERE id = ? AND EXISTS (
        SELECT 1 FROM study_materials WHERE id = pending_study_materials.id AND pb = ?
      )
      """, args: [key.subjectID, payload])
    }
  }
}
