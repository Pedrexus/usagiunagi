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
  @ObservationIgnored private var accountTask: Task<Void, Never>?
  @ObservationIgnored private var networkTask: Task<Void, Never>?
  @ObservationIgnored private var changesTask: Task<Void, Never>?
  @ObservationIgnored private var pass: Task<Void, Never>?
  @ObservationIgnored private var retryTask: Task<Void, Never>?
  private var accountID: String?
  private var online = false
  private var suspended = false
  private var requested = false
  private var retryDelay: TimeInterval = 15

  public init(model: StudyAppModel, paths: AsyncStream<Bool>? = nil) {
    self.model = model
    self.paths = paths ?? Self.networkPaths()
  }
  deinit {
    accountTask?.cancel()
    networkTask?.cancel()
    changesTask?.cancel()
    pass?.cancel()
    retryTask?.cancel()
  }
  public func start() {
    guard accountTask == nil else { return }
    let model = model
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
        self.wake()
      }
    }
  }
  /// Foreground and connection restoration retry saved work without changing the study session.
  public func wake() {
    suspended = false
    retryTask?.cancel()
    retryTask = nil
    request()
  }
  private func selectAccount(_ account: String?) {
    guard accountID != account else { return }
    changesTask?.cancel()
    retryTask?.cancel()
    retryTask = nil
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
    while requested, !Task.isCancelled {
      requested = false
      guard let account = accountID, model.snapshot?.accountID == account,
        model.snapshot?.isSample == false, let store = model.savedWorkStore
      else { return }
      do {
        await model.reloadSavedSnapshot()
        switch try await store.automaticWorkState(accountID: account) {
        case .none:
          notice = nil
          return
        case .requiresAttention:
          notice = "Some saved work needs attention. Open Saved work to check it."
          return
        case .ready: break
        }
        guard online else {
          notice = "Offline. Completed work is saved and will sync when the connection returns."
          return
        }
        guard !suspended else { return }
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
          return
        }
      } catch is CancellationError { return } catch {
        guard accountID == account, model.snapshot?.accountID == account else { return }
        requested = false
        await model.reloadSavedSnapshot()
        let work = try? await store.automaticWorkState(accountID: account)
        guard accountID == account, model.snapshot?.accountID == account else { return }
        if work == .requiresAttention {
          notice = "Some saved work needs attention. Open Saved work to check it."
          return
        }
        if case WaniKaniClient.APIError.rateLimited(let date) = error {
          notice = "WaniKani is limiting requests. Saved work will sync when requests can resume."
          retry(after: max(1, date.timeIntervalSinceNow))
        } else if case StudyUploadError.alreadyRunning = error {
          retry(after: 1)
        } else if isTransient(error) {
          notice = "Couldn't sync yet. Completed work is saved on this device."
          retry(after: retryDelay)
          retryDelay = min(300, retryDelay * 2)
        } else {
          suspended = true
          notice = error.localizedDescription
        }
        return
      }
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
