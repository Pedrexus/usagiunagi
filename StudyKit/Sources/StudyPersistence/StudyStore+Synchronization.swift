import Foundation
import StudyCore

public enum StudySynchronization: Equatable, Sendable {
  case refresh
  case sendSavedWork(accountID: String)
}

public struct StudySynchronizationResult: Sendable {
  public let snapshot: StudySnapshot
  public let profile: StudyAccountProfile?
  public let upload: StudyUploadReport?
}

/// A completed upload is not rolled back when the following download fails.
public struct StudySynchronizationFailure: Error, LocalizedError {
  public let upload: StudyUploadReport
  public let cause: any Error
  public var errorDescription: String? {
    "The saved-work pass finished, but refreshing the account failed: \(cause.localizedDescription)"
  }
}

struct SynchronizationRun {
  let id: UUID
  let credentialID: String
  let token: String
  let operation: StudySynchronization
  let task: Task<StudySynchronizationResult, any Error>
}

extension StudyStore {
  /// App-owned pass: closing/cancelling one waiting scene does not cancel other scenes' work.
  /// Account transitions explicitly call cancelSynchronization and await its drain.
  public func synchronize(
    _ operation: StudySynchronization = .refresh, credentialID: String,
    token: String, client: WaniKaniClient = .init()
  ) async throws -> StudySynchronizationResult {
    try Task.checkCancellation()
    guard synchronizationCancellations == 0 else { throw StudyUploadError.alreadyRunning }
    guard !credentialID.isEmpty, !token.isEmpty else { throw StudyStoreError.invalidIdentity }
    let generation = uploadGeneration
    let task = try synchronizationTask(
      operation, credentialID: credentialID, token: token, client: client)
    let result = try await task.value
    try Task.checkCancellation()
    guard generation == uploadGeneration else { throw CancellationError() }
    return result
  }

  // Choosing/creating the shared task is synchronous on the model actor, including a send
  // queued behind a read. This makes concurrent scene requests one ordered operation.
  func synchronizationTask(
    _ operation: StudySynchronization, credentialID: String,
    token: String, client: WaniKaniClient
  ) throws -> Task<StudySynchronizationResult, any Error> {
    guard synchronizationCancellations == 0 else { throw StudyUploadError.alreadyRunning }
    if case .sendSavedWork(let accountID) = operation {
      guard try snapshot(credentialID: credentialID)?.accountID == accountID else {
        throw StudyUploadError.accountMismatch
      }
    }
    let previous = synchronizationRun
    if let previous {
      guard previous.credentialID == credentialID, previous.token == token else {
        throw StudyUploadError.alreadyRunning
      }
      if operation == .refresh || operation == previous.operation { return previous.task }
    } else {
      guard refreshRun == nil, uploadRun == nil, recoveryRun == nil else { throw StudyUploadError.alreadyRunning }
    }
    let id = UUID()
    let generation = uploadGeneration
    let task = Task {
      defer { if synchronizationRun?.id == id { synchronizationRun = nil } }
      // Only an explicit send request creates this second pass.
      _ = try await previous?.task.value
      try Task.checkCancellation()
      guard generation == uploadGeneration else { throw CancellationError() }
      var upload: StudyUploadReport?
      if case .sendSavedWork(let accountID) = operation {
        upload = try await uploadPending(accountID: accountID, token: token, client: client)
      }
      try Task.checkCancellation()
      let snapshot: StudySnapshot
      do {
        snapshot = try await refresh(credentialID: credentialID, token: token, client: client)
      } catch {
        if let upload, !(error is CancellationError) {
          throw StudySynchronizationFailure(upload: upload, cause: error)
        }
        throw error
      }
      let profile = try snapshot.accountID.flatMap { try accountState(accountID: $0)?.profile }
      return StudySynchronizationResult(snapshot: snapshot, profile: profile, upload: upload)
    }
    synchronizationRun = .init(
      id: id, credentialID: credentialID, token: token, operation: operation, task: task)
    return task
  }

  /// Fence new requests, cancel every active lane, and drain even transports which return late.
  /// Pending attempt markers remain durable; cancellation is not proof a write was rejected.
  public func cancelSynchronization() async {
    synchronizationCancellations += 1
    defer { synchronizationCancellations -= 1 }
    uploadGeneration = UUID()
    let synchronization = synchronizationRun
    let refresh = refreshRun
    let upload = uploadRun
    let recovery = recoveryRun
    synchronization?.task.cancel()
    refresh?.task.cancel()
    upload?.task.cancel()
    recovery?.task.cancel()
    _ = await synchronization?.task.result
    _ = await refresh?.task.result
    _ = await upload?.task.result
    _ = await recovery?.task.result
    if synchronizationRun?.id == synchronization?.id { synchronizationRun = nil }
    if refreshRun?.id == refresh?.id { refreshRun = nil }
    if uploadRun?.id == upload?.id { uploadRun = nil }
    if recoveryRun?.id == recovery?.id { recoveryRun = nil }
  }
}
