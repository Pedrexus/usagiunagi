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
  public private(set) var snapshot: StudySnapshot? {
    didSet {
      dataRevision = UUID()
      if oldValue?.accountID != snapshot?.accountID || oldValue?.isSample != snapshot?.isSample {
        clearWaniKaniPreferences()
      }
    }
  }
  public private(set) var waniKaniPreferences: WaniKaniPreferences?
  public private(set) var waniKaniPreferencesSavedAt: Date?
  public private(set) var waniKaniPreferencesNotice: String?
  public private(set) var isLoadingWaniKaniPreferences = false
  public private(set) var preferenceSourceRevision = UUID()
  public private(set) var pendingWaniKaniPreferences = WaniKaniPreferenceChanges()
  public private(set) var waniKaniPreferencesNeedConfirmation = false
  public var effectiveWaniKaniPreferences: WaniKaniPreferences? {
    waniKaniPreferences?.applying(pendingWaniKaniPreferences)
  }
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
  @ObservationIgnored private let preferenceCacheDirectory: URL?
  @ObservationIgnored private var preferencePersistence: Task<WaniKaniSettingsCache, any Error>?
  @ObservationIgnored private var preferenceWrite: Task<Void, Never>?
  @ObservationIgnored private var preferenceDebounce: Task<Void, any Error>?
  private var preferenceEditRevision = UUID()

  public init(
    credentials: any StudyCredentialStore, client: any WaniKaniService = WaniKaniClient(),
    legacySnapshotURL: URL? = nil,
    preferenceCacheDirectory: URL? = nil,
    openStore: @escaping @Sendable () async throws -> StudyStore
  ) {
    self.credentials = credentials
    reader = client
    self.legacySnapshotURL = legacySnapshotURL
    self.preferenceCacheDirectory = preferenceCacheDirectory
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
    clearWaniKaniPreferences()
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
    let account = snapshot?.accountID
    generation = UUID()
    activeRequests = 0
    activeCredential = nil
    isLoadingWaniKaniPreferences = false
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
      if let account {
        do { try await preferenceRepository()?.remove(accountID: account) } catch {
          self.error =
            "Disconnected, but saved WaniKani settings could not be removed: \(error.localizedDescription)"
        }
      }
      for credential in Set([connectingCredential, savedCredential].compactMap({ $0 })) {
        try await cache.removeSnapshot(credentialID: credential)
      }
      if let legacySnapshotURL, FileManager.default.fileExists(atPath: legacySnapshotURL.path) {
        try FileManager.default.removeItem(at: legacySnapshotURL)
      }
    } catch { self.error = error.localizedDescription }
  }

  private func clearWaniKaniPreferences() {
    preferenceWrite?.cancel()
    preferenceDebounce?.cancel()
    preferenceDebounce = nil
    preferenceWrite = nil
    pendingWaniKaniPreferences = .init()
    waniKaniPreferencesNeedConfirmation = false
    isLoadingWaniKaniPreferences = false
    waniKaniPreferences = nil
    waniKaniPreferencesSavedAt = nil
    waniKaniPreferencesNotice = nil
    preferenceSourceRevision = UUID()
  }

  private func preferenceRepository() async throws -> WaniKaniSettingsCache? {
    guard let preferenceCacheDirectory else { return nil }
    let task =
      preferencePersistence
      ?? Task { try await WaniKaniSettingsCache.open(in: preferenceCacheDirectory) }
    preferencePersistence = task
    do { return try await task.value } catch {
      preferencePersistence = nil
      throw error
    }
  }

  private func checkPreferencesRequest(_ epoch: UUID, account: String, credential: String) throws {
    try checkRequest(epoch)
    guard snapshot?.isSample == false, snapshot?.accountID == account,
      try credentials.load().map(Self.credentialID) == credential
    else { throw StudySignInError.accountChanged }
  }

  /// Reads never manufacture edits. A persisted, unattempted user edit may resume afterward.
  @discardableResult public func refreshWaniKaniPreferences(force: Bool = false) async -> Bool {
    guard preferenceWrite == nil, !isLoadingWaniKaniPreferences, !isDisconnecting,
      snapshot?.isSample == false,
      let account = snapshot?.accountID
    else { return false }
    let epoch = generation
    let source = preferenceSourceRevision
    isLoadingWaniKaniPreferences = true
    defer {
      if generation == epoch, preferenceSourceRevision == source {
        isLoadingWaniKaniPreferences = false
        if !pendingWaniKaniPreferences.isEmpty && !waniKaniPreferencesNeedConfirmation {
          scheduleWaniKaniPreferencesSave()
        }
      }
    }
    do {
      guard let token = try credentials.load() else { throw WaniKaniClient.APIError.unauthorized }
      let credential = Self.credentialID(token)
      try beginRequest(credential: credential)
      defer { finishRequest(epoch) }
      let client = reader
      var cache: WaniKaniSettingsCache?
      if let service = client.cacheNamespace {
        do {
          cache = try await preferenceRepository()
          if waniKaniPreferences == nil,
            let saved = try await cache?.value(accountID: account, service: service)
          {
            try checkPreferencesRequest(epoch, account: account, credential: credential)
            waniKaniPreferences = saved.preferences
            waniKaniPreferencesSavedAt = saved.savedAt
            pendingWaniKaniPreferences = saved.pending
            waniKaniPreferencesNeedConfirmation = saved.needsConfirmation
          }
        } catch {
          try checkPreferencesRequest(epoch, account: account, credential: credential)
          waniKaniPreferencesNotice =
            "Saved WaniKani settings could not be read. Your study data has been kept."
        }
      }
      try checkPreferencesRequest(epoch, account: account, credential: credential)
      if !force, pendingWaniKaniPreferences.isEmpty, let saved = waniKaniPreferencesSavedAt,
        (0..<1800).contains(Date.now.timeIntervalSince(saved))
      {
        return true
      }
      let value = try await client.userPreferences(accountID: account, token: token)
      try checkPreferencesRequest(epoch, account: account, credential: credential)
      guard value.lessonsBatchSize > 0 else { throw WaniKaniPreferenceError.invalidBatchSize }
      pendingWaniKaniPreferences = .init(
        from: value, to: value.applying(pendingWaniKaniPreferences))
      if pendingWaniKaniPreferences.isEmpty { waniKaniPreferencesNeedConfirmation = false }
      waniKaniPreferences = value
      waniKaniPreferencesSavedAt = .now
      waniKaniPreferencesNotice =
        waniKaniPreferencesNeedConfirmation
        ? "Saved edits still differ from WaniKani. Retry sync to apply them."
        : cache == nil && preferenceCacheDirectory != nil && client.cacheNamespace != nil
          ? "WaniKani settings could not be cached on this device." : nil
      do {
        try await persistWaniKaniPreferences(
          cache: cache, account: account, service: client.cacheNamespace)
      } catch {
        try checkPreferencesRequest(epoch, account: account, credential: credential)
        waniKaniPreferencesNotice =
          "WaniKani settings were read, but could not be saved on this device."
      }
      return true
    } catch {
      guard generation == epoch, snapshot?.accountID == account, !(error is CancellationError)
      else { return false }
      waniKaniPreferencesNotice =
        "Could not refresh WaniKani settings. \(waniKaniPreferences == nil ? "Local app choices remain available." : "Showing saved values.") \(error.localizedDescription)"
      return false
    }
  }

  public func editWaniKaniPreferences(_ value: WaniKaniPreferences) {
    guard !isLoadingWaniKaniPreferences, !isDisconnecting, snapshot?.isSample == false,
      let baseline = waniKaniPreferences, let current = effectiveWaniKaniPreferences,
      value.lessonsBatchSize > 0, current != value
    else { return }
    pendingWaniKaniPreferences.merge(.init(from: current, to: value))
    if !waniKaniPreferencesNeedConfirmation {
      pendingWaniKaniPreferences = .init(
        from: baseline, to: baseline.applying(pendingWaniKaniPreferences))
    }
    preferenceEditRevision = UUID()
    preferenceDebounce?.cancel()
    scheduleWaniKaniPreferencesSave()
  }

  public func retryWaniKaniPreferencesSave() {
    guard !isLoadingWaniKaniPreferences, !pendingWaniKaniPreferences.isEmpty else { return }
    waniKaniPreferencesNeedConfirmation = false
    scheduleWaniKaniPreferencesSave()
  }

  private func persistWaniKaniPreferences(
    cache: WaniKaniSettingsCache?, account: String, service: String?
  ) async throws {
    guard let cache, let service, let value = waniKaniPreferences,
      let savedAt = waniKaniPreferencesSavedAt
    else { return }
    try await cache.save(
      value, accountID: account, service: service, now: savedAt,
      pending: pendingWaniKaniPreferences, needsConfirmation: waniKaniPreferencesNeedConfirmation)
  }

  /// One app-owned task persists before debouncing. Dismissing a view does not cancel it.
  private func scheduleWaniKaniPreferencesSave() {
    guard preferenceWrite == nil, !isLoadingWaniKaniPreferences, !isDisconnecting,
      snapshot?.isSample == false, let account = snapshot?.accountID
    else { return }
    let epoch = generation
    let source = preferenceSourceRevision
    preferenceWrite = Task {
      defer { if source == preferenceSourceRevision { preferenceWrite = nil } }
      do {
        let client = reader
        let cache = try await preferenceRepository()
        while true {
          try checkRequest(epoch)
          guard source == preferenceSourceRevision, snapshot?.accountID == account else {
            throw CancellationError()
          }
          let revision = preferenceEditRevision
          try await persistWaniKaniPreferences(
            cache: cache, account: account, service: client.cacheNamespace)
          try checkRequest(epoch)
          guard source == preferenceSourceRevision, snapshot?.accountID == account else {
            throw CancellationError()
          }
          if revision != preferenceEditRevision { continue }
          guard !pendingWaniKaniPreferences.isEmpty else {
            waniKaniPreferencesNotice = nil
            return
          }
          guard !waniKaniPreferencesNeedConfirmation else { return }
          // Only the delay is canceled by another edit. Never cancel an in-flight PUT.
          let delay = Task { try await Task.sleep(for: .milliseconds(600)) }
          preferenceDebounce = delay
          _ = await delay.result
          try Task.checkCancellation()
          preferenceDebounce = nil
          if revision != preferenceEditRevision { continue }
          guard let token = try credentials.load() else {
            throw WaniKaniClient.APIError.unauthorized
          }
          let credential = Self.credentialID(token)
          try await syncWaniKaniPreferences(
            client: client, cache: cache, account: account, token: token, credential: credential,
            epoch: epoch)
          return
        }
      } catch {
        guard source == preferenceSourceRevision, generation == epoch, !(error is CancellationError)
        else { return }
        waniKaniPreferencesNotice =
          "WaniKani settings have not synced. Your edits are kept here. \(error.localizedDescription)"
      }
    }
  }

  private func syncWaniKaniPreferences(
    client: any WaniKaniService, cache: WaniKaniSettingsCache?, account: String,
    token: String, credential: String, epoch: UUID
  ) async throws {
    try checkPreferencesRequest(epoch, account: account, credential: credential)
    try beginRequest(credential: credential)
    isLoadingWaniKaniPreferences = true
    defer {
      finishRequest(epoch)
      if generation == epoch { isLoadingWaniKaniPreferences = false }
    }
    // Persist the attempt before transport: a restart must not blindly repeat an uncertain PUT.
    waniKaniPreferencesNeedConfirmation = true
    try await persistWaniKaniPreferences(
      cache: cache, account: account, service: client.cacheNamespace)
    try checkPreferencesRequest(epoch, account: account, credential: credential)
    let value = try await client.updateUserPreferences(
      pendingWaniKaniPreferences, accountID: account, token: token)
    try checkPreferencesRequest(epoch, account: account, credential: credential)
    waniKaniPreferences = value
    waniKaniPreferencesSavedAt = .now
    pendingWaniKaniPreferences = .init()
    waniKaniPreferencesNeedConfirmation = false
    waniKaniPreferencesNotice = nil
    do {
      try await persistWaniKaniPreferences(
        cache: cache, account: account, service: client.cacheNamespace)
    } catch {
      try checkPreferencesRequest(epoch, account: account, credential: credential)
      waniKaniPreferencesNotice =
        "WaniKani saved these settings, but this device could not cache the confirmation."
    }
  }
}
