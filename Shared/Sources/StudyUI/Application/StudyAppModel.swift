import Foundation
import Observation
import StudyCore
import StudyPersistence

@MainActor @Observable
public final class StudyAppModel {
  public private(set) var dataRevision = UUID()
  public private(set) var snapshot: StudySnapshot? { didSet { dataRevision = UUID() } }
  public private(set) var profile: StudyAccountProfile?
  public private(set) var savedWorkStore: StudyStore?
  public private(set) var syncSummary: String?
  public var maximumContentLevel: Int {
    snapshot?.isSample == true ? 60 : profile?.maxLevelGranted ?? 3
  }
  public var contentAccessVerified: Bool { snapshot?.isSample == true || profile != nil }
  public var error: String?
  public private(set) var isDisconnecting = false
  public var isSyncing: Bool { activeRequests > 0 || isDisconnecting }
  private var activeRequests = 0
  @ObservationIgnored private var activeCredential: String?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var restored = false
  @ObservationIgnored private let credentials: any StudyCredentialStore
  @ObservationIgnored private let openStore: @Sendable () async throws -> StudyStore
  @ObservationIgnored private let legacySnapshotURL: URL?
  @ObservationIgnored private var persistence: Task<StudyStore, any Error>?
  @ObservationIgnored private let reader: any WaniKaniService

  public init(
    credentials: any StudyCredentialStore, client: any WaniKaniService = WaniKaniClient(),
    legacySnapshotURL: URL? = nil,
    openStore: @escaping @Sendable () async throws -> StudyStore
  ) {
    self.credentials = credentials
    reader = client
    self.legacySnapshotURL = legacySnapshotURL
    self.openStore = openStore
  }

  private func repository() async throws -> StudyStore {
    let task =
      persistence
      ?? Task {
        do { return try await openStore() } catch {
          // The failed open clears its own slot before waking any waiting scenes.
          persistence = nil
          throw error
        }
      }
    persistence = task
    let store = try await task.value
    savedWorkStore = store
    return store
  }
  private func beginRequest(credential: String?) throws {
    guard !isDisconnecting, activeRequests == 0 || activeCredential == credential else {
      throw StudyUploadError.alreadyRunning
    }
    activeCredential = credential
    activeRequests += 1
  }
  private func finishRequest(_ epoch: UUID) {
    guard generation == epoch else { return }
    activeRequests -= 1
    if activeRequests == 0 { activeCredential = nil }
  }
  private func checkRequest(_ epoch: UUID) throws {
    try Task.checkCancellation()
    guard generation == epoch else { throw CancellationError() }
  }
  public func restore() async {
    guard !restored, !isSyncing else { return }
    restored = true
    let epoch = generation
    do {
      try beginRequest(credential: nil)
      defer { finishRequest(epoch) }
      error = nil
      if let token = try credentials.load() {
        let cache = try await repository()
        let credential = Self.credentialID(token)
        try checkRequest(epoch)
        let cached = try await cache.snapshot(credentialID: credential)
        try checkRequest(epoch)
        if cached == nil, let legacySnapshotURL {
          try await cache.importLegacySnapshot(at: legacySnapshotURL, credentialID: credential)
        }
        let restoredSnapshot = try await cache.snapshot(credentialID: credential)
        let restoredProfile: StudyAccountProfile?
        if let accountID = restoredSnapshot?.accountID {
          restoredProfile = try await cache.accountState(accountID: accountID)?.profile
        } else {
          restoredProfile = nil
        }
        try checkRequest(epoch)
        snapshot = restoredSnapshot
        profile = restoredProfile
      }
    } catch {
      if generation == epoch {
        restored = false
        self.error = "Couldn't read saved statistics: \(error.localizedDescription)"
      }
    }
  }
  public func reloadSavedSnapshot() async {
    guard !isSyncing, let accountID = snapshot?.accountID, let cache = savedWorkStore else {
      return
    }
    let epoch = generation
    do {
      let credential = try credentials.load().map(Self.credentialID)
      guard let credential else { return }
      let saved = try await cache.snapshot(credentialID: credential)
      let savedProfile = try await cache.accountState(accountID: accountID)?.profile
      try checkRequest(epoch)
      guard saved?.accountID == accountID, snapshot?.accountID == accountID else { return }
      snapshot = saved
      profile = savedProfile
    } catch { if generation == epoch { self.error = error.localizedDescription } }
  }
  public func loadPreview() {
    guard !isSyncing else { return }
    do {
      snapshot = try StudySnapshot.freeLevelsPreview()
      profile = nil
      error = nil
      syncSummary = nil
    } catch { self.error = error.localizedDescription }
  }
  public func connect(_ token: String) async throws {
    let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      error = "Enter your WaniKani API token."
      throw StudySignInError.message("Enter your WaniKani API token.")
    }
    let epoch = generation
    let credential = Self.credentialID(token)
    do {
      try beginRequest(credential: credential)
      defer { finishRequest(epoch) }
      error = nil
      syncSummary = nil
      let previous = try credentials.load().map(Self.credentialID)
      let cache = try await repository()
      try checkRequest(epoch)
      let result = try await cache.synchronize(
        credentialID: credential, token: token, client: reader)
      try checkRequest(epoch)
      try credentials.save(token)
      restored = true
      error = nil
      profile = result.profile
      snapshot = result.snapshot
      if let previous, previous != credential {
        try await cache.removeSnapshot(credentialID: previous)
      }
      try checkRequest(epoch)
    } catch {
      if generation == epoch, !(error is CancellationError) {
        self.error = error.localizedDescription
      }
      throw error
    }
  }
  public func refresh() async {
    do {
      guard let token = try credentials.load() else {
        error = "Connect a WaniKani account first."
        return
      }
      try await connect(token)
    } catch { self.error = error.localizedDescription }
  }
  /// A manual Saved work pass includes a full download; automatic passes only upload.
  public func syncSavedWork(accountID: String) async throws {
    _ = try await sendSavedWork(.sendSavedWork(accountID: accountID), accountID: accountID)
  }
  @discardableResult public func uploadSavedWork(accountID: String) async throws
    -> StudyUploadReport?
  {
    try await sendSavedWork(.uploadSavedWork(accountID: accountID), accountID: accountID)
  }
  private func sendSavedWork(_ operation: StudySynchronization, accountID: String) async throws
    -> StudyUploadReport?
  {
    guard snapshot?.accountID == accountID, snapshot?.isSample == false,
      let token = try credentials.load()
    else { throw StudyStoreError.invalidIdentity }
    let epoch = generation
    let credential = Self.credentialID(token)
    try beginRequest(credential: credential)
    defer { finishRequest(epoch) }
    error = nil
    syncSummary = nil
    let cache = try await repository()
    try checkRequest(epoch)
    do {
      let result = try await cache.synchronize(
        operation, credentialID: credential, token: token, client: reader
      )
      try checkRequest(epoch)
      snapshot = result.snapshot
      profile = result.profile
      if let report = result.upload { syncSummary = summary(report) }
      return result.upload
    } catch let failure as StudySynchronizationFailure {
      try checkRequest(epoch)
      syncSummary = summary(failure.upload)
      throw failure
    }
  }
  private func summary(_ report: StudyUploadReport) -> String {
    "Sent \(report.uploadedReviews) reviews, \(report.uploadedLessons) lessons and \(report.uploadedMaterials) note edits. \(report.reviewsNeedingAttention + report.materialsNeedingAttention) items need attention."
      + (report.onVacation ? " Reviews and lessons are paused during vacation." : "")
  }
  public func compareSavedWork(_ request: StudyRecoveryRequest) async throws
    -> StudyRecoveryComparison
  {

    guard snapshot?.isSample == false,
      snapshot?.accountID == request.accountID,
      let token = try credentials.load()
    else { throw StudyStoreError.invalidIdentity }
    let epoch = generation
    let credential = Self.credentialID(token)
    try beginRequest(credential: credential)
    defer { finishRequest(epoch) }
    let cache = try await repository()
    try checkRequest(epoch)
    let comparison = try await cache.compareSavedWork(
      request, credentialID: credential, token: token, client: reader)
    try checkRequest(epoch)
    return comparison
  }

  nonisolated public static func credentialID(_ token: String) -> String {
    StudyCredentialID.forToken(token)
  }
  public func disconnect() async {
    guard !isDisconnecting else { return }
    let connectingCredential = activeCredential
    generation = UUID()
    activeRequests = 0
    activeCredential = nil
    isDisconnecting = true
    defer { isDisconnecting = false }
    do {
      let cache = try await repository()
      await cache.cancelSynchronization()
      let savedCredential = try credentials.load().map(Self.credentialID)
      try credentials.remove()
      snapshot = nil
      profile = nil
      error = nil
      syncSummary = nil
      for credential in Set([connectingCredential, savedCredential].compactMap({ $0 })) {
        try await cache.removeSnapshot(credentialID: credential)
      }
      if let legacySnapshotURL, FileManager.default.fileExists(atPath: legacySnapshotURL.path) {
        try FileManager.default.removeItem(at: legacySnapshotURL)
      }
    } catch { self.error = error.localizedDescription }
  }
}
