import Foundation
import StudyCore
import Synchronization

/// The app explicitly supplies Apple's default store; tests supply a protocol fake instead.
@MainActor public final class AppleStudyMistakeICloudStore: StudyMistakeICloudStore {
  private let store: NSUbiquitousKeyValueStore
  private let notifications: NotificationCenter
  private let idleEpoch = UUID()
  private var observer: StudyMistakeICloudObserver?
  /// The last local synchronization request succeeded; this does not establish account or delivery.
  public private(set) var available = false
  public var observedEpoch: UUID { observer?.epoch ?? idleEpoch }
  public init(
    store: NSUbiquitousKeyValueStore, notifications: NotificationCenter = .default
  ) {
    self.store = store
    self.notifications = notifications
  }
  public func changes() -> AsyncStream<StudyMistakeICloudEvent> {
    let (stream, continuation) = AsyncStream<StudyMistakeICloudEvent>.makeStream()
    let observer = StudyMistakeICloudObserver(
      notifications: notifications, object: store, continuation: continuation)
    self.observer = observer
    let center = notifications
    continuation.onTermination = { _ in
      Task { @MainActor in observer.cancel(in: center) }
    }
    return stream
  }
  public func synchronize() -> Bool {
    available = store.synchronize()
    return available
  }
  public func data(forKey key: String) throws -> Data? {
    guard available else { throw StudyMistakeError.unavailable }
    guard key.utf16.count <= 128 else { throw StudyMistakeError.invalidKey }
    guard let value = store.object(forKey: key) else { return nil }
    guard let data = value as? Data else { throw StudyMistakeError.invalidArchive }
    return data
  }
  public func set(_ data: Data, forKey key: String, observedEpoch: UUID) throws {
    guard available else { throw StudyMistakeError.unavailable }
    guard !key.isEmpty, key.utf16.count <= 128 else { throw StudyMistakeError.invalidKey }
    var projected = store.dictionaryRepresentation
    projected[key] = data
    // A conservative preflight; the system remains the authority for the shared account quota.
    guard data.count <= StudyMistakeArchive.maximumBytes, projected.count <= 1024,
      try PropertyListSerialization.data(fromPropertyList: projected, format: .binary, options: 0)
        .count
        <= StudyMistakeArchive.maximumBytes
    else { throw StudyMistakeError.quotaExceeded }
    guard self.observedEpoch == observedEpoch else { throw CancellationError() }
    store.set(data, forKey: key)
  }
}

/// A nil delivery queue observes the event on its posting thread, before the async consumer resumes.
@MainActor final class StudyMistakeICloudObserver {
  private nonisolated let observed = Mutex(UUID())
  private var token: (any NSObjectProtocol)?
  nonisolated var epoch: UUID { observed.withLock { $0 } }
  init(
    notifications: NotificationCenter, object: AnyObject,
    continuation: AsyncStream<StudyMistakeICloudEvent>.Continuation
  ) {
    token = notifications.addObserver(
      forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: object, queue: nil
    ) { [self] notification in
      let event = StudyMistakeICloudEvent(notification: notification)
      if event.reason != .server { observed.withLock { $0 = UUID() } }
      continuation.yield(event)
    }
  }
  func cancel(in notifications: NotificationCenter) {
    if let token { notifications.removeObserver(token) }
    token = nil
  }
}

extension StudyMistakeICloudEvent {
  nonisolated init(notification: Notification) {
    let reason: Reason
    switch notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int {
    case NSUbiquitousKeyValueStoreServerChange: reason = .server
    case NSUbiquitousKeyValueStoreInitialSyncChange: reason = .initial
    case NSUbiquitousKeyValueStoreQuotaViolationChange: reason = .quota
    case NSUbiquitousKeyValueStoreAccountChange: reason = .account
    default: reason = .unknown
    }
    let keys = (notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]).map(
      Set.init)
    self.init(reason: reason, keys: keys)
  }
}
