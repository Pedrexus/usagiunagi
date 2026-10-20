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
  var available: Bool { get }
  func changes() -> AsyncStream<StudyMistakeCloudEvent>
  func synchronize() -> Bool
  func data(forKey key: String) throws -> Data?
  func set(_ data: Data, forKey key: String) throws
}

/// One app owner; windows share this worker. Cloud values are practice hints, never an outbox.
@MainActor @Observable public final class StudyMistakeSync {
  public private(set) var notice: String?
  private let model: StudyAppModel
  private let cloud: any StudyMistakeCloudStore
  private let legacyBinding: @MainActor (String) -> StudyLegacyMistakeBinding?
  @ObservationIgnored private var accountTask: Task<Void, Never>?
  @ObservationIgnored private var cloudTask: Task<Void, Never>?
  @ObservationIgnored private var changesTask: Task<Void, Never>?
  @ObservationIgnored private var pass: Task<Void, Never>?
  private var generation = UUID()
  private var selection: Selection?
  private var requested = false
  private var cloudReady = false
  private var awaitingCloudAccount = false
  private var quotaBlocked = false
  private nonisolated struct Selection: Equatable, Sendable {
    let accountID: String
    let username: String
  }
  public init(
    model: StudyAppModel, cloud: any StudyMistakeCloudStore,
    legacyBinding: @escaping @MainActor (String) -> StudyLegacyMistakeBinding? = { _ in nil }
  ) {
    self.model = model
    self.cloud = cloud
    self.legacyBinding = legacyBinding
  }
  deinit {
    accountTask?.cancel()
    cloudTask?.cancel()
    changesTask?.cancel()
    pass?.cancel()
  }
  public func start() {
    guard accountTask == nil else { return }
    // changes() registers synchronously, before synchronize or the first catch-up read.
    let events = cloud.changes()
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
    cloudReady = cloud.available && cloud.synchronize()
    if !cloudReady { notice = StudyMistakeError.unavailable.localizedDescription }
    request()
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
    selection = nil
    requested = false
    cloudReady = false
    notice = nil
  }
  /// Foreground catch-up requests delivery, without claiming that another device received it.
  public func wake() async {
    let starting = accountTask == nil
    start()
    quotaBlocked = false
    if !starting { cloudReady = cloud.available && cloud.synchronize() }
    guard cloudReady else {
      notice = StudyMistakeError.unavailable.localizedDescription
      return
    }
    request()
    while let pass { await pass.value }
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
  private func received(_ event: StudyMistakeCloudEvent) {
    switch event.reason {
    case .account:
      generation = UUID()
      pass?.cancel()
      pass = nil
      requested = false
      cloudReady = false
      awaitingCloudAccount = true
      // Rebind the local observer to the new generation without changing local study history.
      let account = selection
      selection = nil
      select(account)
      awaitingCloudAccount = true
      notice = "The Apple account changed. Local recent mistakes have been kept."
    case .quota:
      quotaBlocked = true
      pass?.cancel()
      requested = false
      notice = StudyMistakeError.quotaExceeded.localizedDescription
    case .unknown:
      cloudReady = false
      pass?.cancel()
      requested = false
      notice = "An iCloud mistake update could not be identified. Local history has been kept."
    case .initial, .server:
      if event.reason == .initial {
        awaitingCloudAccount = false
        cloudReady = cloud.available
      }
      if event.reason == .server, let keys = event.keys, let account = selection,
        let key = try? StudyMistakeArchive.key(accountID: account.accountID),
        !keys.contains(key), !keys.contains(legacyBinding(account.accountID)?.key ?? "")
      {
        return
      }
      request()
    }
  }
  private func request() {
    requested = true
    guard pass == nil, selection != nil else { return }
    let epoch = generation
    pass = Task { [weak self] in await self?.drain(epoch: epoch) }
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
  private func drain(epoch: UUID) async {
    defer {
      if generation == epoch {
        pass = nil
        if requested { request() }
      }
    }
    while requested, generation == epoch {
      requested = false
      guard let account = selection, current(account, epoch: epoch), !Task.isCancelled,
        cloudReady, !awaitingCloudAccount, !quotaBlocked
      else { return }
      do {
        guard cloud.available else { throw StudyMistakeError.unavailable }
        guard let store = model.savedWorkStore else { return }
        let binding = legacyBinding(account.accountID)
        let state = try await store.mistakeState(
          accountID: account.accountID, legacyBinding: binding)
        guard current(account, epoch: epoch), !Task.isCancelled else { return }
        let key = try StudyMistakeArchive.key(accountID: account.accountID)
        let (remote, legacy) = try readCloud(
          accountID: account.accountID, binding: state.legacyBinding)
        guard current(account, epoch: epoch), !Task.isCancelled, cloud.available else { return }
        let incoming = StudyMistakeArchive.merge(remote?.values ?? [:], legacy?.values ?? [:])
        _ = try await store.mergeMistakes(incoming, accountID: account.accountID)
        guard current(account, epoch: epoch), !Task.isCancelled else { return }
        let latest = try await store.mistakeState(
          accountID: account.accountID, legacyBinding: binding)
        guard current(account, epoch: epoch), !Task.isCancelled, cloud.available else { return }
        // A cloud update may have arrived during the actor reads. Merge it before publishing.
        let (currentRemote, currentLegacy) = try readCloud(
          accountID: account.accountID, binding: latest.legacyBinding)
        let currentIncoming = StudyMistakeArchive.merge(
          currentRemote?.values ?? [:], currentLegacy?.values ?? [:])
        if currentIncoming != incoming { requested = true }
        let merged = try StudyMistakeArchive(
          accountID: account.accountID,
          values: StudyMistakeArchive.merge(
            StudyMistakeArchive.merge(incoming, currentIncoming), latest.values))
        guard current(account, epoch: epoch), !Task.isCancelled, cloud.available else { return }
        if currentRemote != merged, !merged.values.isEmpty {
          try cloud.set(merged.encoded(), forKey: key)
        }
        guard current(account, epoch: epoch), !Task.isCancelled, cloud.available else { return }
        if let binding = latest.legacyBinding, let currentLegacy,
          let updated = try currentLegacy.updatedData(merging: merged.values)
        {
          try cloud.set(updated, forKey: binding.key)
        }
        notice =
          latest.legacyBinding == nil
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
