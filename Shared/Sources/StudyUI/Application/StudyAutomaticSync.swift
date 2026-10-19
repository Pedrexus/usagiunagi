import Foundation
import Network
import Observation
import StudyCore
import StudyPersistence

/// One app-owned worker, shared by its windows. Only the durable outbox authorizes writes.
@MainActor @Observable public final class StudyAutomaticSync {
  public private(set) var notice: String?
  private let model: StudyAppModel
  private let paths: AsyncStream<Bool>
  private let now: @MainActor @Sendable () -> Date
  @ObservationIgnored private var accountTask: Task<Void, Never>?
  @ObservationIgnored private var networkTask: Task<Void, Never>?
  @ObservationIgnored private var changesTask: Task<Void, Never>?
  @ObservationIgnored private var pass: Task<Void, Never>?
  @ObservationIgnored private var retryTask: Task<Void, Never>?
  @ObservationIgnored private var readTask: Task<Void, Never>?
  private var scenes: [UUID: Bool] = [:]
  private var lastRead: Date?
  private var needsStudyRead = false
  private var accountID: String?
  private var online = false
  private var suspended = false
  private var requested = false
  private var retryDelay: TimeInterval = 15

  public init(
    model: StudyAppModel, paths: AsyncStream<Bool>? = nil,
    now: @escaping @MainActor @Sendable () -> Date = { .now }
  ) {
    self.model = model
    self.now = now
    self.paths = paths ?? Self.networkPaths()
  }
  deinit {
    accountTask?.cancel()
    networkTask?.cancel()
    changesTask?.cancel()
    readTask?.cancel()
    pass?.cancel()
    retryTask?.cancel()
  }
  public func start() {
    guard accountTask == nil else { return }
    let model = model
    selectAccount(model.snapshot?.isSample == false ? model.snapshot?.accountID : nil)
    let accounts = Observations {
      model.snapshot?.isSample == false ? model.snapshot?.accountID : nil
    }
    accountTask = Task { [weak self] in
      for await account in accounts {
        guard let self, !Task.isCancelled else { return }
        self.selectAccount(account)
      }
    }
    let paths = paths
    networkTask = Task { [weak self] in
      for await available in paths {
        guard let self, !Task.isCancelled else { return }
        self.online = available
        self.signal()
      }
    }
  }
  /// Await the current app-owned work without cancelling it when a waiting scene closes.
  public func wake() async {
    signal()
    while let pass { await pass.value }
  }
  private func signal() {
    suspended = false
    retryTask?.cancel()
    retryTask = nil
    request()
  }
  /// A hidden/background window cannot request catalog reads; any active study defers them.
  public func updateScene(_ id: UUID, active: Bool, studying: Bool) {
    scenes[id] = active ? studying : nil
    request()
  }
  public func removeScene(_ id: UUID) {
    scenes[id] = nil
    request()
  }
  private var canRead: Bool { !scenes.isEmpty && !scenes.values.contains(true) }
  private var nextRead: Date? {
    guard canRead, online, !suspended, model.snapshot?.isSample == false,
      model.snapshot?.accountID == accountID, let saved = model.snapshot?.savedAt
    else { return nil }
    let current = now()
    // Clock rollback and providers returning an older fetchedAt must not postpone reads forever
    // or spin immediately after a successful pass.
    let previous = max(
      saved <= current ? saved : .distantPast,
      lastRead.flatMap { $0 <= current ? $0 : nil } ?? .distantPast)
    return previous.addingTimeInterval(needsStudyRead ? 60 : 1800)
  }
  private func scheduleRead() {
    readTask?.cancel()
    readTask = nil
    guard let deadline = nextRead else { return }
    let delay = max(1, deadline.timeIntervalSince(now()))
    readTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      guard let self else { return }
      self.readTask = nil
      self.request()
    }
  }
  private func selectAccount(_ account: String?) {
    guard accountID != account else { return }
    changesTask?.cancel()
    retryTask?.cancel()
    retryTask = nil
    readTask?.cancel()
    readTask = nil
    lastRead = nil
    needsStudyRead = false
    accountID = account
    notice = nil
    suspended = false
    retryDelay = 15
    guard let account, let store = model.savedWorkStore else { return }
    changesTask = Task { [weak self] in
      for await _ in await store.changes() {
        guard let self, !Task.isCancelled, self.accountID == account else { return }
        self.request()
      }
    }
  }
  private func request() {
    requested = true
    guard pass == nil, retryTask == nil else { return }
    pass = Task { [weak self] in await self?.drain() }
  }
  private func drain() async {
    defer {
      pass = nil
      if requested { request() }
    }
    requested = false
    guard !Task.isCancelled, let account = accountID, model.snapshot?.accountID == account,
      model.snapshot?.isSample == false, let store = model.savedWorkStore
    else { return }
    var reading = false
    do {
      await model.reloadSavedSnapshot()
      let work = try await store.automaticWorkState(accountID: account)
      guard accountID == account, model.snapshot?.accountID == account else { return }
      notice =
        work == .requiresAttention
        ? "Some saved work needs attention. Open Saved work to check it." : nil
      guard online else {
        if work == .ready {
          notice = "Offline. Completed work is saved and will sync when the connection returns."
        }
        scheduleRead()
        return
      }
      guard !suspended else { return }
      if work == .ready {
        let report = try await model.uploadSavedWork(accountID: account)
        guard accountID == account, model.snapshot?.accountID == account else { return }
        retryDelay = 15
        notice =
          (report?.reviewsNeedingAttention ?? 0) + (report?.materialsNeedingAttention ?? 0) > 0
          ? "Some saved work needs attention. Open Saved work to check it." : nil
        if report?.onVacation == true {
          notice = "Vacation mode pauses saved reviews and lessons."
          requested = false
          retry(after: 300)
        }
      }
      needsStudyRead =
        try await store.accountState(accountID: account)?.catalogRefreshID != nil
        || model.snapshot?.requiresAssignmentRefresh == true
      if let deadline = nextRead, deadline <= now() {
        reading = true
        try await model.refresh(accountID: account)
        guard accountID == account, model.snapshot?.accountID == account else { return }
        lastRead = now()
        needsStudyRead =
          try await store.accountState(accountID: account)?.catalogRefreshID != nil
          || model.snapshot?.requiresAssignmentRefresh == true
        retryDelay = 15
      }
      scheduleRead()
    } catch is CancellationError { return } catch {
      guard accountID == account, model.snapshot?.accountID == account else { return }
      requested = false
      await model.reloadSavedSnapshot()
      let work = try? await store.automaticWorkState(accountID: account)
      guard accountID == account, model.snapshot?.accountID == account else { return }
      needsStudyRead =
        (try? await store.accountState(accountID: account)?.catalogRefreshID) != nil
        || model.snapshot?.requiresAssignmentRefresh == true
      if !reading, work == .requiresAttention {
        notice = "Some saved work needs attention. Open Saved work to check it."
        scheduleRead()
        return
      }
      if case WaniKaniClient.APIError.rateLimited(let date) = error {
        notice = "WaniKani is limiting requests. Saved data is kept while requests pause."
        retry(after: max(1, date.timeIntervalSinceNow))
      } else if case StudyUploadError.alreadyRunning = error {
        retry(after: 1)
      } else if isTransient(error) {
        notice =
          reading
          ? "Couldn't refresh yet. Your saved data is available on this device."
          : "Couldn't sync yet. Completed work is saved on this device."
        retry(after: retryDelay)
        retryDelay = min(300, retryDelay * 2)
      } else {
        suspended = true
        notice = error.localizedDescription
      }
      // Retry owns the next attempt; do not create an independent stale-read loop.
      readTask?.cancel()
      readTask = nil
    }
  }
  private func isTransient(_ error: any Error) -> Bool {
    if error is URLError { return true }
    if case WaniKaniClient.APIError.request(let code) = error { return code >= 500 || code == 408 }
    return false
  }
  private func retry(after seconds: TimeInterval) {
    retryTask?.cancel()
    retryTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      guard let self else { return }
      self.retryTask = nil
      self.request()
    }
  }
  private static func networkPaths() -> AsyncStream<Bool> {
    let (stream, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let task = Task {
      let monitor = NWPathMonitor()
      defer { monitor.cancel() }
      for await path in monitor {
        guard !Task.isCancelled else { break }
        continuation.yield(path.status == .satisfied)
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }
}
