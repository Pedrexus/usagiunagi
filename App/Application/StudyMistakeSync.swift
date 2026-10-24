import Foundation
import Observation
import StudyCore
import StudyPersistence

nonisolated public struct StudyMistakeICloudEvent: Sendable {
  public enum Reason: Equatable, Sendable { case server, initial, quota, account, unknown }
  public let reason: Reason
  public let keys: Set<String>?
  public init(reason: Reason, keys: Set<String>? = nil) {
    self.reason = reason
    self.keys = keys
  }
}

@MainActor public protocol StudyMistakeICloudStore: AnyObject {
  /// Cache access permission, not Apple-account identity or confirmed remote delivery.
  var available: Bool { get }
  /// Changes synchronously in the notification callback, before its async event is consumed.
  var observedEpoch: UUID { get }
  func changes() -> AsyncStream<StudyMistakeICloudEvent>
  func synchronize() -> Bool
  func data(forKey key: String) throws -> Data?
  func set(_ data: Data, forKey key: String, observedEpoch: UUID) throws
}

/// One app owner; windows share this worker. Cloud values are practice hints, never an outbox.
@MainActor @Observable public final class StudyMistakeSync {
  public private(set) var notice: String?
  private let model: StudyAppModel
  private let iCloud: any StudyMistakeICloudStore
  private let now: @MainActor @Sendable () -> Date
  @ObservationIgnored private var accountTask: Task<Void, Never>?
  @ObservationIgnored private var iCloudTask: Task<Void, Never>?
  @ObservationIgnored private var changesTask: Task<Void, Never>?
  @ObservationIgnored private var pass: Task<Void, Never>?
  @ObservationIgnored private var retryTask: Task<Void, Never>?
  private var generation = UUID()
  private var selection: Selection?
  private var requested = false
  private var cacheAllowed = false
  private var iCloudEpoch: UUID?
  private var quotaBlocked = false
  private var retryAvailable = true
  private nonisolated struct Selection: Equatable, Sendable {
    let accountID: String
    let username: String
  }
  public init(
    model: StudyAppModel, iCloud: any StudyMistakeICloudStore,
    now: @escaping @MainActor @Sendable () -> Date = { .now }
  ) {
    self.model = model
    self.iCloud = iCloud
    self.now = now
  }
  deinit {
    accountTask?.cancel()
    iCloudTask?.cancel()
    changesTask?.cancel()
    pass?.cancel()
    retryTask?.cancel()
  }
  public func start() {
    guard accountTask == nil else { return }
    // changes() registers synchronously, before synchronize or the first catch-up read.
    let events = iCloud.changes()
    iCloudEpoch = iCloud.observedEpoch
    iCloudTask = Task { [weak self] in
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
    iCloudTask?.cancel()
    iCloudTask = nil
    changesTask?.cancel()
    changesTask = nil
    pass?.cancel()
    pass = nil
    retryTask?.cancel()
    retryTask = nil
    selection = nil
    requested = false
    cacheAllowed = false
    iCloudEpoch = nil
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
    let accepted = iCloud.synchronize()
    cacheAllowed = accepted && iCloud.available
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
    current(account, epoch: epoch) && iCloud.observedEpoch == observedEpoch
      && cacheAllowed && iCloud.available && !quotaBlocked && !Task.isCancelled
  }
  private func received(_ event: StudyMistakeICloudEvent) {
    if event.reason != .server { iCloudEpoch = iCloud.observedEpoch }
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
      if retryTask == nil, !quotaBlocked { cacheAllowed = iCloud.available }
      request()
    }
  }
  private func request() {
    requested = true
    guard pass == nil, selection != nil, cacheAllowed, !quotaBlocked,
      let observedEpoch = iCloudEpoch
    else { return }
    let epoch = generation
    pass = Task { [weak self] in
      await self?.drain(epoch: epoch, observedEpoch: observedEpoch)
    }
  }
  private func readICloud(accountID: String) throws -> StudyMistakeArchive? {
    try iCloud.data(forKey: StudyMistakeArchive.key(accountID: accountID)).map {
      try StudyMistakeArchive(data: $0, accountID: accountID)
    }
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
        let remote = try readICloud(accountID: account.accountID)
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch) else { return }
        let incoming = remote?.values ?? [:]
        _ = try await store.mergeMistakes(incoming, accountID: account.accountID)
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch) else { return }
        let latest = try await store.mistakeState(accountID: account.accountID)
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch),
          latest.username == account.username
        else { return }
        // Reread after suspension; whole-key KVS writes still cannot provide an atomic merge.
        let currentRemote = try readICloud(accountID: account.accountID)
        let currentIncoming = currentRemote?.values ?? [:]
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
          try iCloud.set(data, forKey: key, observedEpoch: observedEpoch)
        }
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch) else { return }
        notice = nil
      } catch is CancellationError { return } catch {
        guard currentPass(account, epoch: epoch, observedEpoch: observedEpoch) else { return }
        notice = error.localizedDescription
        requested = false
        return
      }
    }
  }
}
