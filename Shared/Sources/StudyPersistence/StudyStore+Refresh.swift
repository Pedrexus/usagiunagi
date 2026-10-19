import Foundation
import StudyCore
import SwiftData

struct RefreshBaseline {
  let assignments: [Int64: UUID]
  let materials: [Int64: UUID]
}

extension StudyStore {
  /// One complete read per store. Local edits and uploads may continue while downloading;
  /// revisions prevent the response from replacing work completed during that interval.
  public func refresh(
    credentialID: String, token: String, client: any WaniKaniService = WaniKaniClient()
  )
    async throws -> StudySnapshot
  {
    guard synchronizationCancellations == 0, refreshRun == nil, recoveryRun == nil else {
      throw StudyUploadError.alreadyRunning
    }
    guard !credentialID.isEmpty else { throw StudyStoreError.invalidIdentity }
    let id = UUID()
    let generation = uploadGeneration
    let task = Task {
      try await self.performRefresh(
        credentialID: credentialID, token: token, client: client, generation: generation)
    }
    refreshRun = (id, task)
    defer { if refreshRun?.id == id { refreshRun = nil } }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private func checkRefresh(_ generation: UUID) throws {
    try Task.checkCancellation()
    guard uploadGeneration == generation else { throw CancellationError() }
  }

  private func assignmentRecords(accountID: String) throws -> [AssignmentRecord] {
    try modelContext.fetch(
      FetchDescriptor<AssignmentRecord>(predicate: #Predicate { $0.accountID == accountID }))
  }
  func refreshBaseline(accountID: String) throws -> RefreshBaseline {
    try RefreshBaseline(
      assignments: Dictionary(
        uniqueKeysWithValues: assignmentRecords(accountID: accountID).map {
          ($0.subjectID, $0.revision)
        }),
      materials: Dictionary(
        uniqueKeysWithValues: materialRecords(accountID: accountID).map {
          ($0.subjectID, $0.revision)
        }))
  }

  private func performRefresh(
    credentialID: String, token: String, client: any WaniKaniService, generation: UUID
  ) async throws -> StudySnapshot {
    try checkRefresh(generation)
    let cachedAccount = try snapshot(credentialID: credentialID)?.accountID
    if let cachedAccount, let retryAt = try uploadRetryDate(accountID: cachedAccount),
      retryAt > Date()
    {
      throw WaniKaniClient.APIError.rateLimited(retryAt: retryAt)
    }
    let identity: WaniKaniAccount
    do { identity = try await client.account(token: token) } catch {
      try checkRefresh(generation)
      if let cachedAccount { try recordRateLimit(error, accountID: cachedAccount) }
      throw error
    }
    try checkRefresh(generation)
    if let previous = try snapshot(credentialID: credentialID)?.accountID, previous != identity.id {
      throw StudyUploadError.accountMismatch
    }
    if let retryAt = try uploadRetryDate(accountID: identity.id), retryAt > Date() {
      throw WaniKaniClient.APIError.rateLimited(retryAt: retryAt)
    }
    let baseline = try refreshBaseline(accountID: identity.id)
    let download: StudyDownload
    do { download = try await client.download(token: token) } catch {
      try checkRefresh(generation)
      try recordRateLimit(error, accountID: identity.id)
      throw error
    }
    try checkRefresh(generation)
    guard download.accountID == identity.id else { throw StudyUploadError.accountMismatch }
    return try applyDownload(download, credentialID: credentialID, baseline: baseline)
  }

  /// Commit all server categories and the visible snapshot together. Never erase pending work
  /// or interpret an absent/changed assignment as a receipt for an earlier upload.
  func applyDownload(_ download: StudyDownload, credentialID: String, baseline: RefreshBaseline)
    throws -> StudySnapshot
  {
    let accountID = download.accountID
    guard !accountID.isEmpty, !credentialID.isEmpty, !download.profile.username.isEmpty else {
      throw StudyStoreError.invalidIdentity
    }
    // Validate before constructing unique-key dictionaries, including manually supplied values.
    for ids in [
      download.subjects.map(\.id), download.assignments.map(\.subjectID),
      download.assignments.map(\.id),
      download.materials.map { $0.value.subjectID },
    ] {
      guard ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else {
        throw WaniKaniClient.APIError.invalidResponse
      }
    }
    var visible = download.snapshot
    try transaction {
      let snapshots = try modelContext.fetch(FetchDescriptor<SnapshotRecord>())
      let cached = snapshots.first { $0.credentialID == credentialID }
      if let previous = cached?.snapshot.accountID, previous != accountID {
        throw StudyUploadError.accountMismatch
      }
      let pending = try pendingReviews(accountID: accountID)
      let pendingIDs = Set(pending.map(\.subjectID))
      let pendingNotes = Set(
        try materials(accountID: accountID).filter(\.pending).map { $0.material.subjectID })
      let sessionIDs = Set(
        try session(accountID: accountID)?.session.items.values.map(\.subjectID) ?? [])
      let retainedIDs = pendingIDs.union(pendingNotes).union(sessionIDs)
      let catalogRows = try modelContext.fetch(
        FetchDescriptor<CatalogRecord>(predicate: #Predicate { $0.accountID == accountID }))
      let currentCatalog = Dictionary(uniqueKeysWithValues: catalogRows.map { ($0.subjectID, $0) })
      let incomingIDs = Set(download.subjects.map(\.id))
      for row in catalogRows where !incomingIDs.contains(row.subjectID) {
        if retainedIDs.contains(row.subjectID) {
          // Keep recovery/session content, while excluding removed subjects from normal browsing.
          row.subject.hiddenAt =
            row.subject.hiddenAt ?? Int64(download.fetchedAt.timeIntervalSince1970)
        } else {
          modelContext.delete(row)
        }
      }
      for subject in download.subjects {
        if let row = currentCatalog[subject.id] {
          row.subject = subject
          row.level = subject.level
          row.japanese = subject.japanese
        } else {
          modelContext.insert(CatalogRecord(accountID: accountID, subject: subject))
        }
      }
      let rows = try assignmentRecords(accountID: accountID)
      let current = Dictionary(uniqueKeysWithValues: rows.map { ($0.subjectID, $0) })
      let incomingAssignments = Set(download.assignments.map(\.subjectID))
      for row in rows
      where !incomingAssignments.contains(row.subjectID) && !pendingIDs.contains(row.subjectID)
        && baseline.assignments[row.subjectID] == row.revision
      {
        modelContext.delete(row)
      }
      for assignment in download.assignments where !pendingIDs.contains(assignment.subjectID) {
        if let row = current[assignment.subjectID] {
          guard baseline.assignments[row.subjectID] == row.revision else { continue }
          row.assignment = assignment
          row.revision = UUID()
        } else if baseline.assignments[assignment.subjectID] == nil {
          modelContext.insert(AssignmentRecord(accountID: accountID, assignment: assignment))
        }
      }
      try applyMaterials(
        download.materials.map(\.value), accountID: accountID, baseline: baseline.materials,
        replacingAll: true,
        serverIDs: Dictionary(
          uniqueKeysWithValues: download.materials.map { ($0.value.subjectID, $0.id) }))
      let mergedAssignments = try assignmentRecords(accountID: accountID).map(\.assignment)
      let stateRow = try modelContext.fetch(
        FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.accountID == accountID })
      ).first
      let previousProgress = Dictionary(
        uniqueKeysWithValues: (stateRow?.state.progress ?? []).map { ($0.subjectID, $0) })
      var progress = mergedAssignments.map { assignment in
        if pendingIDs.contains(assignment.subjectID),
          let previous = previousProgress[assignment.subjectID]
        {
          return previous
        }
        return SubjectProgress(
          subjectID: assignment.subjectID, level: assignment.level, srsStage: assignment.srsStage,
          kind: assignment.kind,
          lastMistakeLocalTime: previousProgress[assignment.subjectID]?.lastMistakeLocalTime,
          legacyRevision: previousProgress[assignment.subjectID]?.legacyRevision ?? 0,
          lastMistakeAt: previousProgress[assignment.subjectID]?.lastMistakeAt)
      }
      // Imported pending subjects need not have an available assignment row.
      let progressIDs = Set(progress.map(\.subjectID))
      progress += previousProgress.values.filter {
        pendingIDs.contains($0.subjectID) && !progressIDs.contains($0.subjectID)
      }
      var state = StudyAccountState(download: download, progress: progress)
      state.supersededAssignments = stateRow?.state.supersededAssignments ?? []
      if let stateRow {
        stateRow.state = state
      } else {
        modelContext.insert(AccountRecord(accountID: accountID, state: state))
      }
      let hiddenIDs = Set(download.subjects.filter { $0.hiddenAt != nil }.map(\.id))
      visible = StudySnapshot(
        accountID: accountID, username: download.profile.username,
        currentLevel: download.profile.level,
        onVacation: download.profile.vacationStartedAt != nil,
        assignments: mergedAssignments.filter {
          incomingIDs.contains($0.subjectID) && !pendingIDs.contains($0.subjectID)
            && !hiddenIDs.contains($0.subjectID) && $0.hidden != true
        }.map(\.summary),
        statistics: download.statistics.map(\.answers), levels: download.levels.map(\.summary),
        subjects: download.subjects.filter { $0.hiddenAt == nil }.map(\.summary),
        savedAt: download.fetchedAt, pendingReviews: pending.count)
      for row in snapshots
      where row.snapshot.accountID == accountID || row.credentialID == credentialID {
        row.snapshot = visible
      }
      if cached == nil { modelContext.insert(SnapshotRecord(visible, credentialID: credentialID)) }
    }
    return visible
  }
}
