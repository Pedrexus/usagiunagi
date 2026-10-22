import Foundation
import StudyCore
import SwiftData

@testable import StudyPersistence

/// Native committed states for repository tests; no retired on-device database importer is used.
struct NativeStoreFixture: Sendable {
  struct Material: Sendable {
    let serverID: Int64
    let value: StudyMaterial
    let pending: Bool
  }
  struct Review: Sendable {
    let assignment: CatalogAssignment
    let submission: StudyReviewSubmission
  }
  var profile: StudyAccountProfile
  var subjects: [CatalogSubject] = []
  var assignments: [CatalogAssignment] = []
  var supersededAssignments: [CatalogAssignment] = []
  var pendingReviews: [Review] = []
  var materials: [Material] = []
  var progress: [SubjectProgress] = []
  var levels: [CatalogLevelProgression] = []
  var statistics: [CatalogReviewStatistic] = []
  var voices: [StudyVoiceActor] = []
  var audio: [StudyAudioReference] = []
  var cursors: [String: String] = [:]
}

extension StudyStore {
  func seedFixture(_ source: NativeStoreFixture, accountID: String, credentialID: String) throws {
    let pendingIDs = Set(source.pendingReviews.map { $0.assignment.subjectID })
    let download = StudyDownload(
      accountID: accountID, profile: source.profile, subjects: source.subjects,
      assignments: source.assignments.filter { !pendingIDs.contains($0.subjectID) },
      levels: source.levels, statistics: source.statistics, voices: source.voices,
      cursors: source.cursors)
    var state = StudyAccountState(download: download, progress: source.progress)
    state.audio = source.audio
    state.supersededAssignments = source.supersededAssignments
    try transaction {
      for subject in source.subjects {
        modelContext.insert(CatalogRecord(accountID: accountID, subject: subject))
      }
      for assignment in download.assignments {
        modelContext.insert(AssignmentRecord(accountID: accountID, assignment: assignment))
      }
      for entry in source.pendingReviews {
        let row = ReviewRecord(
          accountID: accountID, submission: entry.submission,
          originalItem: entry.assignment.sessionItem(
            id: entry.submission.itemID, isLesson: entry.submission.isLesson))
        row.originalAssignment = entry.assignment
        row.attempted = true
        modelContext.insert(row)
      }
      for entry in source.materials {
        let row = MaterialRecord(
          accountID: accountID, material: entry.value, pending: entry.pending)
        row.serverID = entry.serverID > 0 ? entry.serverID : nil
        if entry.pending {
          row.issue = .init(
            reason: .uncertain, httpStatus: nil, serverAssignment: nil, detectedAt: .now)
        }
        modelContext.insert(row)
      }
      modelContext.insert(AccountRecord(accountID: accountID, state: state))
      let snapshot = StudySnapshot(
        accountID: accountID, username: source.profile.username,
        currentLevel: source.profile.level, onVacation: source.profile.vacationStartedAt != nil,
        assignments: download.assignments.map(\.summary),
        statistics: source.statistics.map(\.answers),
        levels: source.levels.map(\.summary), subjects: source.subjects.map(\.summary),
        pendingReviews: source.pendingReviews.count)
      modelContext.insert(SnapshotRecord(snapshot, credentialID: credentialID))
    }
  }
}
