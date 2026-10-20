import Foundation
import StudyCore
import SwiftData

/// First native format. Keep these top-level identities and declarations unchanged for old stores.
/// Its Codable nominal types/decoders remain part of V1's compatibility contract; a future version
/// must preserve historical decoders before changing those types, not merely reuse this models list.
enum StudySchemaV1: VersionedSchema {
  static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
  static var models: [any PersistentModel.Type] {
    [
      SnapshotRecord.self, SessionRecord.self, ReviewRecord.self, MaterialRecord.self,
      ImportReceipt.self, CatalogRecord.self, AssignmentRecord.self, AccountRecord.self,
      UploadPauseRecord.self, ArchivedReviewRecord.self,
    ]
  }
  static var unversioned: Schema { Schema(models) }
  static var schema: Schema { Schema(versionedSchema: Self.self) }
}

enum StudySchemaMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] { [StudySchemaV1.self] }
  static var stages: [MigrationStage] { [] }
}

@Model final class SnapshotRecord {
  @Attribute(.unique) var credentialID: String
  @Attribute(.codable) var snapshot: StudySnapshot
  init(_ snapshot: StudySnapshot, credentialID: String) {
    self.snapshot = snapshot
    self.credentialID = credentialID
  }
}

@Model final class SessionRecord {
  @Attribute(.unique) var accountID: String
  var revision: UUID
  @Attribute(.codable) var session: StudySession
  init(accountID: String, session: StudySession, revision: UUID) {
    self.accountID = accountID
    self.session = session
    self.revision = revision
  }
}

@Model final class ReviewRecord {
  #Unique<ReviewRecord>([\.accountID, \.subjectID])
  var accountID: String
  var subjectID: Int64
  var revision: UUID
  var attempted: Bool
  @Attribute(.codable) var submission: StudyReviewSubmission
  @Attribute(.codable) var originalItem: StudySessionItem
  @Attribute(.codable) var originalAssignment: CatalogAssignment? = nil
  @Attribute(.codable) var issue: StudyUploadIssue? = nil
  init(accountID: String, submission: StudyReviewSubmission, originalItem: StudySessionItem) {
    self.accountID = accountID
    self.subjectID = submission.subjectID
    self.submission = submission
    self.originalItem = originalItem
    self.revision = UUID()
    attempted = false
  }
  var saved: SavedReview {
    .init(
      accountID: accountID, subjectID: subjectID, revision: revision, submission: submission,
      originalItem: originalItem, originalAssignment: originalAssignment, attempted: attempted,
      issue: issue)
  }
}

@Model final class ImportReceipt {
  @Attribute(.unique) var sourceID: String
  var digest: String
  @Attribute(.codable) var handoff: StudyLegacyHandoff? = nil
  init(sourceID: String, digest: String) {
    self.sourceID = sourceID
    self.digest = digest
  }
}

@Model final class CatalogRecord {
  #Unique<CatalogRecord>([\.accountID, \.subjectID])
  var accountID: String
  var subjectID: Int64
  var level: Int
  var japanese: String
  @Attribute(.codable) var subject: CatalogSubject
  init(accountID: String, subject: CatalogSubject) {
    self.accountID = accountID
    subjectID = subject.id
    level = subject.level
    japanese = subject.japanese
    self.subject = subject
  }
}

@Model final class AssignmentRecord {
  var revision: UUID = UUID()
  #Unique<AssignmentRecord>([\.accountID, \.subjectID])
  var accountID: String
  var subjectID: Int64
  @Attribute(.codable) var assignment: CatalogAssignment
  init(accountID: String, assignment: CatalogAssignment) {
    self.accountID = accountID
    subjectID = assignment.subjectID
    self.assignment = assignment
  }
}

@Model final class AccountRecord {
  @Attribute(.unique) var accountID: String
  @Attribute(.codable) var state: StudyAccountState
  init(accountID: String, state: StudyAccountState) {
    self.accountID = accountID
    self.state = state
  }
}

@Model final class MaterialRecord {
  #Unique<MaterialRecord>([\.accountID, \.subjectID])
  var accountID: String
  var subjectID: Int64
  var revision: UUID
  var pending: Bool
  var serverID: Int64? = nil
  @Attribute(.codable) var issue: StudyUploadIssue? = nil
  var attemptedRevision: UUID? = nil
  @Attribute(.codable) var attemptedMaterial: StudyMaterial? = nil
  @Attribute(.codable) var recoveryBaseline: StudyMaterialBaseline? = nil
  @Attribute(.codable) var material: StudyMaterial
  init(accountID: String, material: StudyMaterial, pending: Bool) {
    self.accountID = accountID
    self.subjectID = material.subjectID
    self.material = material
    self.pending = pending
    revision = UUID()
  }
  var saved: SavedStudyMaterial {
    SavedStudyMaterial(
      accountID: accountID, revision: revision, pending: pending, serverID: serverID,
      issue: issue, attemptedRevision: attemptedRevision, attemptedMaterial: attemptedMaterial,
      material: material)
  }
}

@Model final class UploadPauseRecord {
  @Attribute(.unique) var accountID: String
  var retryAt: Date
  init(accountID: String, retryAt: Date) {
    self.accountID = accountID
    self.retryAt = retryAt
  }
}

@Model final class ArchivedReviewRecord {
  @Attribute(.unique) var id: UUID
  var accountID: String
  @Attribute(.codable) var answer: ArchivedStudyReview
  init(_ answer: ArchivedStudyReview) {
    id = answer.id
    accountID = answer.saved.accountID
    self.answer = answer
  }
}
