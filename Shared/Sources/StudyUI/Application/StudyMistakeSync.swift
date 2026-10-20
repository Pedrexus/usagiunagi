import Foundation
import Observation
import StudyCore
import StudyPersistence

nonisolated public struct StudyMistakeCloudEvent: Sendable {
  public enum Reason: Equatable, Sendable { case server, initial, quota, account, unknown }
  public let reason: Reason
  public let keys: Set<String>?
  public init(reason: Reason, keys: Set<String>? = nil) {
    self.reason = reason
    self.keys = keys
  }
}

@MainActor public protocol StudyMistakeCloudStore: AnyObject {
  /// Cache access permission, not Apple-account identity or confirmed remote delivery.
  var available: Bool { get }
  /// Changes synchronously in the notification callback, before its async event is consumed.
  var observedEpoch: UUID { get }
  func changes() -> AsyncStream<StudyMistakeCloudEvent>
  func synchronize() -> Bool
  func data(forKey key: String) throws -> Data?
  func set(_ data: Data, forKey key: String, observedEpoch: UUID) throws
}

/// One app owner; windows share this worker. Cloud values are practice hints, never an outbox.
@MainActor @Observable public final class StudyMistakeSync {
  public private(set) var notice: String?
  private let model: StudyAppModel
  private let cloud: any StudyMistakeCloudStore
  private let now: @MainActor @Sendable () -> Date
  @ObservationIgnored private var accountTask: Task<Void, Never>?
  @ObservationIgnored private var cloudTask: Task<Void, Never>?
  @ObservationIgnored private var changesTask: Task<Void, Never>?
  @ObservationIgnored private var pass: Task<Void, Never>?
  @ObservationIgnored private var retryTask: Task<Void, Never>?
  private var generation = UUID()
  private var selection: Selection?
  private var requested = false
  private var cacheAllowed = false
  private var cloudEpoch: UUID?
  private var quotaBlocked = false
  private var retryAvailable = true
  private nonisolated struct Selection: Equatable, Sendable {
    let accountID: String
    let username: String
  }
  public init(
    model: StudyAppModel, cloud: any StudyMistakeCloudStore,
    now: @escaping @MainActor @Sendable () -> Date = { .now }
  ) {
    self.model = model
    self.cloud = cloud
    self.now = now
  }
  deinit {
    accountTask?.cancel()
    cloudTask?.cancel()
    changesTask?.cancel()
    pass?.cancel()
    retryTask?.cancel()
  }
  public func start() {
    guard accountTask == nil else { return }
    // changes() registers synchronously, before synchronize or the first catch-up read.
    let events = cloud.changes()
    cloudEpoch = cloud.observedEpoch
    cloudTask = Task { [weak self] in
      for await event in events {
        guard let self, !Task.isCancelled else { return }
        self.received(event)
      }
    }
    select(currentSelection)
    let model = model
    let accounts = Observations { Self.selection(in: model) }
    accountTask = Task { [weak self] in
      for await account in accounts {
        guard let self, !Task.isCancelled else { return }
        self.select(account)
      }
    }
    quotaBlocked = false
    retryAvailable = true
    synchronizeCache()
  }
  public func stop() {
    generation = UUID()
    accountTask?.cancel()
    accountTask = nil
    cloudTask?.cancel()
    cloudTask = nil
    changesTask?.cancel()
    changesTask = nil
    pass?.cancel()
    pass = nil
    retryTask?.cancel()
    retryTask = nil
    selection = nil
    requested = false
    cacheAllowed = false
    cloudEpoch = nil
    quotaBlocked = false
    retryAvailable = false
    notice = nil
  }
  /// Foreground catch-up requests delivery, without claiming that another device received it.
  public func wake() async {
    let starting = accountTask == nil
    start()
    if !starting {
      retryTask?.cancel()
      retryTask = nil
      retryAvailable = true
      quotaBlocked = false
      synchronizeCache()
    }
    while let pass { await pass.value }
  }
  private func synchronizeCache() {
    let accepted = cloud.synchronize()
    cacheAllowed = accepted && cloud.available
    if cacheAllowed {
      request()
    } else {
      notice = StudyMistakeError.unavailable.localizedDescription
      retry()
    }
  }
  /// One delayed attempt per wake/identity lifecycle; further failures wait for a foreground wake.
  private func retry() {
    guard retryAvailable, retryTask == nil, !quotaBlocked, accountTask != nil else { return }
    retryAvailable = false
    let epoch = generation
    retryTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      guard let self, self.generation == epoch, !Task.isCancelled else { return }
      self.retryTask = nil
      self.synchronizeCache()
    }
  }
  private var currentSelection: Selection? { Self.selection(in: model) }
  private static func selection(in model: StudyAppModel) -> Selection? {
    guard model.serviceSourceReady, let snapshot = model.snapshot, !snapshot.isSample,
      let accountID = snapshot.accountID
    else { return nil }
    return .init(accountID: accountID, username: model.profile?.username ?? snapshot.username)
  }
  private func select(_ account: Selection?) {
    guard selection != account else { return }
    generation = UUID()
    pass?.cancel()
    pass = nil
    retryTask?.cancel()
    retryTask = nil
    retryAvailable = true
    changesTask?.cancel()
    changesTask = nil
    requested = false
    selection = account
    notice = nil
    guard let account, let store = model.savedWorkStore else { return }
    let epoch = generation
    changesTask = Task { [weak self] in
      let changes = await store.changes()
      guard self?.current(account, epoch: epoch) == true, !Task.isCancelled else { return }
      for await _ in changes {
        guard let self, self.current(account, epoch: epoch), !Task.isCancelled else { return }
        self.request()
      }
    }
    request()
  }
  private func current(_ account: Selection, epoch: UUID) -> Bool {
    generation == epoch && selection == account && currentSelection == account
  }
  private func currentPass(_ account: Selection, epoch: UUID, observedEpoch: UUID) -> Bool {
    current(account, epoch: epoch) && cloud.observedEpoch == observedEpoch
      && cacheAllowed && cloud.available && !quotaBlocked && !Task.isCancelled
  }
  private func received(_ event: StudyMistakeCloudEvent) {
    if event.reason != .server { cloudEpoch = cloud.observedEpoch }
    switch event.reason {
    case .account:
      cacheAllowed = false
      // Rebind local observation without moving or clearing this WaniKani account's history.
      let account = selection
      selection = nil
      select(account)
      notice = "The Apple account changed. Local recent mistakes have been kept."
      retry()
    case .quota:
      quotaBlocked = true
      pass?.cancel()
      retryTask?.cancel()
      retryTask = nil
      requested = false
      notice = StudyMistakeError.quotaExceeded.localizedDescription
    case .initial, .unknown:
      cacheAllowed = false
      pass?.cancel()
      requested = false
      notice =
        event.reason == .initial
        ? "iCloud mistake history is loading. Local history is available."
        : "An iCloud mistake update could not be identified. Local history has been kept."
      retry()
    case .server:
      if retryTask == nil, !quotaBlocked { cacheAllowed = cloud.available }
      request()
    }
  }
  private func request() {
    requested = true
    guard pass == nil, selection != nil, cacheAllowed, !quotaBlocked,
      let observedEpoch = cloudEpoch
    else { return }
    let epoch = generation
    pass = Task { [weak self] in
      await self?.drain(epoch: epoch, observedEpoch: observedEpoch)
    }
  }
  private func readCloud(accountID: String, binding: StudyLegacyMistakeBinding?) throws
    -> (StudyMistakeArchive?, StudyLegacyMistakes?)
  {
    let native = try cloud.data(forKey: StudyMistakeArchive.key(accountID: accountID)).map {
      try StudyMistakeArchive(data: $0, accountID: accountID)
    }
    guard let binding else { return (native, nil) }
    let legacy =
      try cloud.data(forKey: binding.key).map {
        try StudyLegacyMistakes(data: $0, context: binding.context)
      } ?? StudyLegacyMistakes(originals: [:], context: binding.context)
    return (native, legacy)
  }
  private func drain(epoch: UUID, observedEpoch: UUID) async {
    defer {
      if generation == epoch {
        pass = nil
        if requested { request() }
      }
    }
    while requested, generation == epoch {
      requested = false
      guard let account = selection,
        currentPass(account, epoch: epoch, observedEpoch: observedEpoch)
      else { return }
      do {
        guard let store = model.savedWorkStore else { return }
        let state = try await store.mistakeState(accountID: account.accountID)
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch),
          state.username == account.username
        else { return }
        let key = try StudyMistakeArchive.key(accountID: account.accountID)
        let (remote, legacy) = try readCloud(
          accountID: account.accountID, binding: state.legacyBinding)
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch) else { return }
        let incoming = StudyMistakeArchive.merge(remote?.values ?? [:], legacy?.values ?? [:])
        _ = try await store.mergeMistakes(incoming, accountID: account.accountID)
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch) else { return }
        let latest = try await store.mistakeState(accountID: account.accountID)
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch),
          latest.username == account.username
        else { return }
        // Reread after suspension; whole-key KVS writes still cannot provide an atomic merge.
        let (currentRemote, currentLegacy) = try readCloud(
          accountID: account.accountID, binding: latest.legacyBinding)
        let currentIncoming = StudyMistakeArchive.merge(
          currentRemote?.values ?? [:], currentLegacy?.values ?? [:])
        if currentIncoming != incoming { requested = true }
        let date = now()
        let merged = try StudyMistakeArchive(
          accountID: account.accountID,
          values: StudyMistakeArchive.recentValues(
            StudyMistakeArchive.merge(
              StudyMistakeArchive.merge(incoming, currentIncoming), latest.values), now: date))
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch) else { return }
        if currentRemote != merged, currentRemote != nil || !merged.values.isEmpty {
          let data = try merged.encoded()
          guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch) else { return }
          try cloud.set(data, forKey: key, observedEpoch: observedEpoch)
        }
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch) else { return }
        if let binding = latest.legacyBinding, let currentLegacy,
          let updated = try currentLegacy.updatedData(merging: merged.values, now: date)
        {
          guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch) else { return }
          try cloud.set(updated, forKey: binding.key, observedEpoch: observedEpoch)
        }
        notice =
          latest.needsLegacyImport
          ? "Older username-based mistake history needs a verified import before it can sync."
          : currentLegacy?.unresolvedKeys.isEmpty == false
            ? "Some older mistake timestamps could not be interpreted and have been kept unchanged."
            : nil
      } catch is CancellationError { return } catch {
        guard generation == epoch else { return }
        notice = error.localizedDescription
        requested = false
        return
      }
    }
  }
}
