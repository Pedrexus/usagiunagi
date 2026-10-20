import Foundation
import Observation
import StudyCore
import StudyPersistence

@MainActor @Observable
public final class StudyAppModel {
  public struct ReauthenticationContext: Equatable, Sendable {
    public let accountID: String
    public let username: String
    fileprivate let credentialID: String?
    fileprivate let generation: UUID
  }
  public struct AccountIssue: Equatable, Sendable {
    public enum Reason: Equatable, Sendable { case unauthorized, hibernating }
    public let reason: Reason
    public let context: ReauthenticationContext
    public fileprivate(set) var acknowledged = false
  }
  public private(set) var dataRevision = UUID()
  public private(set) var snapshot: StudySnapshot? { didSet { dataRevision = UUID() } }
  public private(set) var profile: StudyAccountProfile?
  public private(set) var savedWorkStore: StudyStore?
  public private(set) var syncSummary: String?
  public private(set) var accountIssue: AccountIssue?
  public var reauthenticationContext: ReauthenticationContext? { accountIssue?.context }
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
  private var restored = false
  public var restorationComplete: Bool { restored }
  @ObservationIgnored private var restoration: Task<Void, Never>?
  @ObservationIgnored private let credentials: any StudyCredentialStore
  @ObservationIgnored private let openStore: @Sendable () async throws -> StudyStore
  @ObservationIgnored private let legacySnapshotURL: URL?
  @ObservationIgnored private var persistence: Task<StudyStore, any Error>?
  @ObservationIgnored private var reader: any WaniKaniService

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
  public func acknowledgeAccountIssue(_ context: ReauthenticationContext) {
    guard accountIssue?.context == context else { return }
    accountIssue?.acknowledged = true
  }
  private func reportAccountIssue(
    _ error: any Error, accountID: String?, credentialID: String?, epoch: UUID
  ) {
    guard generation == epoch, accountIssue == nil, let saved = snapshot, !saved.isSample,
      let accountID, saved.accountID == accountID
    else { return }
    let cause = (error as? StudySynchronizationFailure)?.cause ?? error
    let reason: AccountIssue.Reason
    switch cause {
    case WaniKaniClient.APIError.unauthorized: reason = .unauthorized
    case StudySignInError.hibernating: reason = .hibernating
    default: return
    }
    accountIssue = AccountIssue(
      reason: reason,
      context: ReauthenticationContext(
        accountID: accountID, username: saved.username, credentialID: credentialID,
        generation: epoch))
  }
  private func checkReauthentication(_ context: ReauthenticationContext) throws {
    try Task.checkCancellation()
    guard generation == context.generation, snapshot?.isSample == false,
      snapshot?.accountID == context.accountID,
      try credentials.load().map(Self.credentialID) == context.credentialID
    else { throw StudySignInError.accountChanged }
  }
  public func restore() async {
    if let restoration {
      await restoration.value
      return
    }
    guard !restored, !isSyncing else { return }
    let task = Task {
      defer { restoration = nil }
      await restoreAccount()
    }
    restoration = task
    await task.value
  }
  private func restoreAccount() async {
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
      try checkRequest(epoch)
      restored = true
    } catch {
      if generation == epoch {
        restored = false
        self.error = "Couldn't read saved statistics: \(error.localizedDescription)"
      }
    }
  }
  var serviceSourceReady: Bool { restored && !isDisconnecting && snapshot?.isSample != true }
  func serviceSnapshot(lessonPreferences: StudyLessonPreferences) async throws
    -> StudyServiceSnapshot
  {
    guard serviceSourceReady else { throw CancellationError() }
    guard let snapshot else { return .init() }
    guard let accountID = snapshot.accountID, let store = savedWorkStore else {
      throw StudyStoreError.invalidIdentity
    }
    let revision = dataRevision
    let value = try await store.availability(
      accountID: accountID, lessonPreferences: lessonPreferences)
    try Task.checkCancellation()
    guard serviceSourceReady, dataRevision == revision, self.snapshot?.accountID == accountID else {
      throw CancellationError()
    }
    return value.serviceSnapshot
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
      accountIssue = nil
    } catch { self.error = error.localizedDescription }
  }
  public func connect(_ token: String) async throws {
    try await connect(token, reauthenticating: nil)
  }
  public func reauthenticate(_ token: String, context: ReauthenticationContext) async throws {
    try checkReauthentication(context)
    try await connect(token, reauthenticating: context)
  }
  private func connect(_ token: String, reauthenticating context: ReauthenticationContext?)
    async throws
  {
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
      if let context { try checkReauthentication(context) }
      let operation: StudySynchronization =
        context.map { .reauthenticate(accountID: $0.accountID) } ?? .refresh
      let result = try await cache.synchronize(
        operation, credentialID: credential, token: token, client: reader)
      try checkRequest(epoch)
      if let context { try checkReauthentication(context) }
      try credentials.save(token)
      restored = true
      error = nil
      profile = result.profile
      snapshot = result.snapshot
      accountIssue = nil
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
    let epoch = generation
    do {
      _ = try await performSynchronization(.refresh, accountID: snapshot?.accountID)
    } catch {
      if generation == epoch, !(error is CancellationError) {
        self.error = error.localizedDescription
      }
    }
  }
  public func setAPIEndpoint(_ url: URL) throws {
    guard !isSyncing else { throw StudyUploadError.alreadyRunning }
    guard
      let normalized = DeveloperEndpoint.normalized(
        url.absoluteString, defaultURL: WaniKaniClient.defaultBaseURL.absoluteString),
      let endpoint = URL(string: normalized)
    else { throw WaniKaniServiceConfigurationError.invalidEndpoint }
    reader = try reader.reconfigured(baseURL: endpoint)
  }
  /// Read through the same fenced lane without rewriting credentials or sending pending work.
  public func refresh(accountID: String) async throws {
    _ = try await performSynchronization(.refresh, accountID: accountID)
  }
  /// Manual Saved work includes a full download; automatic sending uses upload-only passes.
  public func syncSavedWork(accountID: String) async throws {
    _ = try await performSynchronization(.sendSavedWork(accountID: accountID), accountID: accountID)
  }
  @discardableResult public func uploadSavedWork(accountID: String) async throws
    -> StudyUploadReport?
  {
    try await performSynchronization(.uploadSavedWork(accountID: accountID), accountID: accountID)
  }
  private func performSynchronization(_ operation: StudySynchronization, accountID: String?)
    async throws
    -> StudyUploadReport?
  {
    guard snapshot?.isSample != true,
      accountID == nil ? operation == .refresh : snapshot?.accountID == accountID
    else { throw StudyStoreError.invalidIdentity }
    let epoch = generation
    guard let token = try credentials.load() else {
      reportAccountIssue(
        WaniKaniClient.APIError.unauthorized, accountID: accountID, credentialID: nil, epoch: epoch)
      throw StudySignInError.message("Connect a WaniKani account first.")
    }
    let credential = Self.credentialID(token)
    try beginRequest(credential: credential)
    defer { finishRequest(epoch) }
    error = nil
    syncSummary = nil
    let cache = try await repository()
    try checkRequest(epoch)
    // The app owns publication; closing a waiting scene only cancels that waiter.
    let request = Task {
      do {
        let result = try await cache.synchronize(
          operation, credentialID: credential, token: token, client: reader
        )
        try checkRequest(epoch)
        snapshot = result.snapshot
        profile = result.profile
        restored = true
        accountIssue = nil
        if let report = result.upload { syncSummary = summary(report) }
        return result.upload
      } catch {
        try checkRequest(epoch)
        if let failure = error as? StudySynchronizationFailure {
          syncSummary = summary(failure.upload)
        }
        reportAccountIssue(error, accountID: accountID, credentialID: credential, epoch: epoch)
        throw error
      }
    }
    let result = await request.result
    try Task.checkCancellation()
    return try result.get()
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
    do {
      let comparison = try await cache.compareSavedWork(
        request, credentialID: credential, token: token, client: reader)
      try checkRequest(epoch)
      return comparison
    } catch {
      try checkRequest(epoch)
      reportAccountIssue(
        error, accountID: request.accountID, credentialID: credential, epoch: epoch)
      throw error
    }
  }

  nonisolated public static func credentialID(_ token: String) -> String {
    StudyCredentialID.forToken(token)
  }
  public func disconnect() async {
    guard !isDisconnecting else { return }
    restoration?.cancel()
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
      restored = true
      snapshot = nil
      profile = nil
      error = nil
      syncSummary = nil
      accountIssue = nil
      for credential in Set([connectingCredential, savedCredential].compactMap({ $0 })) {
        try await cache.removeSnapshot(credentialID: credential)
      }
      if let legacySnapshotURL, FileManager.default.fileExists(atPath: legacySnapshotURL.path) {
        try FileManager.default.removeItem(at: legacySnapshotURL)
      }
    } catch { self.error = error.localizedDescription }
  }
}
