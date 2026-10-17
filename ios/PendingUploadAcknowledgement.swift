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

/// A response acknowledges the submitted version, never a newer edit with the same subject ID.
/// Keep these conditional deletes inside the caller's database transaction.
enum PendingUploadAcknowledgement {
  static func progress(_ progress: TKMProgress, in db: FMDatabase) {
    db.mustExecuteUpdate("DELETE FROM pending_progress WHERE id = ? AND pb = ?",
                         args: [progress.assignment.subjectID, try! progress.serializedData()])
  }

  static func studyMaterial(_ material: TKMStudyMaterials, in db: FMDatabase) {
    db.mustExecuteUpdate("""
    DELETE FROM pending_study_materials WHERE id = ? AND EXISTS (
      SELECT 1 FROM study_materials WHERE id = pending_study_materials.id AND pb = ?
    )
    """, args: [material.subjectID, try! material.serializedData()])
  }
}
