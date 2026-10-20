import Foundation
import StudyCore

/// The app explicitly supplies Apple's default store; tests supply a protocol fake instead.
@MainActor public final class AppleStudyMistakeCloudStore: StudyMistakeCloudStore {
  private let store: NSUbiquitousKeyValueStore
  private let notifications: NotificationCenter
  private let hasAccount: @MainActor () -> Bool
  public var available: Bool { hasAccount() }
  public init(
    store: NSUbiquitousKeyValueStore, notifications: NotificationCenter = .default,
    hasAccount: @escaping @MainActor () -> Bool = {
      FileManager.default.ubiquityIdentityToken != nil
    }
  ) {
    self.store = store
    self.notifications = notifications
    self.hasAccount = hasAccount
  }
  public func changes() -> AsyncStream<StudyMistakeCloudEvent> {
    let (stream, continuation) = AsyncStream<StudyMistakeCloudEvent>.makeStream()
    let token = notifications.addObserver(of: store, for: CloudMessage.self) { message in
      continuation.yield(message.event)
    }
    let center = notifications
    continuation.onTermination = { _ in center.removeObserver(token) }
    return stream
  }
  public func synchronize() -> Bool { available && store.synchronize() }
  public func data(forKey key: String) throws -> Data? {
    guard available else { throw StudyMistakeError.unavailable }
    guard key.utf16.count <= 128 else { throw StudyMistakeError.invalidKey }
    guard let value = store.object(forKey: key) else { return nil }
    guard let data = value as? Data else { throw StudyMistakeError.invalidArchive }
    return data
  }
  public func set(_ data: Data, forKey key: String) throws {
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
    store.set(data, forKey: key)
  }
}

private nonisolated struct CloudMessage: NotificationCenter.AsyncMessage {
  typealias Subject = NSUbiquitousKeyValueStore
  static var name: Notification.Name { NSUbiquitousKeyValueStore.didChangeExternallyNotification }
  let event: StudyMistakeCloudEvent
  static func makeMessage(_ notification: Notification) -> Self? {
    .init(event: StudyMistakeCloudEvent(notification: notification))
  }
}

extension StudyMistakeCloudEvent {
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
