import Foundation
import Observation
import StudyCore
import StudyPersistence
import UserNotifications

public enum StudyNotificationAuthorization: Equatable, Sendable {
  case notDetermined, denied
  case authorized(Set<NotificationPreference>)
}

/// Narrow system boundary; tests supply every operation without accessing the notification center.
public struct StudyNotificationClient {
  public var status: @MainActor () async -> StudyNotificationAuthorization
  public var request: @MainActor () async throws -> Void
  public var pending: @MainActor () async -> [String]
  public var remove: @MainActor ([String]) -> Void
  public var badge: @MainActor (Int) async throws -> Void
  public var add: @MainActor (UNNotificationRequest) async throws -> Void
  public init(
    status: @escaping @MainActor () async -> StudyNotificationAuthorization,
    request: @escaping @MainActor () async throws -> Void,
    pending: @escaping @MainActor () async -> [String],
    remove: @escaping @MainActor ([String]) -> Void,
    badge: @escaping @MainActor (Int) async throws -> Void,
    add: @escaping @MainActor (UNNotificationRequest) async throws -> Void
  ) {
    self.status = status
    self.request = request
    self.pending = pending
    self.remove = remove
    self.badge = badge
    self.add = add
  }
  public static var system: Self {
    let center = UNUserNotificationCenter.current()
    return .init(
      status: {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { return .notDetermined }
        var allowed =
          settings.authorizationStatus == .authorized
          || settings.authorizationStatus == .provisional
        #if os(iOS)
          allowed = allowed || settings.authorizationStatus == .ephemeral
        #endif
        guard allowed else { return .denied }
        var features = Set<NotificationPreference>()
        if settings.alertSetting == .enabled { features.insert(.reviews) }
        if settings.badgeSetting == .enabled { features.insert(.badge) }
        if settings.soundSetting == .enabled { features.insert(.sound) }
        return .authorized(features)
      },
      request: { _ = try await center.requestAuthorization(options: [.badge, .alert, .sound]) },
      pending: { await center.pendingNotificationRequests().map(\.identifier) },
      remove: { center.removePendingNotificationRequests(withIdentifiers: $0) },
      badge: { try await center.setBadgeCount($0) },
      add: { try await center.add($0) })
  }
}

@MainActor @Observable public final class StudyNotifications {
  public enum Notice: Sendable {
    case systemSettings(NotificationPermissionRequest)
    case error(String)
    public var title: String {
      switch self {
      case .systemSettings: "Notifications are disabled"
      case .error: "Could not enable notifications"
      }
    }
    public var message: String {
      switch self {
      case .systemSettings: "Allow notifications in system Settings, then return to the app."
      case .error(let message): message
      }
    }
  }
  private let client: StudyNotificationClient
  public var didRead: @MainActor (StudyServiceSnapshot) -> Void = { _ in }
  private let preferences: any StudyNotificationPreferences
  private var preferenceRevision = 0
  private var intents: [NotificationPreference: UUID] = [:]
  private var source: (@MainActor () async throws -> StudyServiceSnapshot)?
  private var revision = 0
  private var binding = UUID()
  @ObservationIgnored private var modelRead: Task<Void, Never>?
  @ObservationIgnored private var storeRead: Task<Void, Never>?
  @ObservationIgnored private var delivery: Task<Void, Never>?
  @ObservationIgnored private var dataRead: Task<StudyServiceSnapshot, any Error>?
  public private(set) var authorization: StudyNotificationAuthorization?
  public private(set) var busy = false
  public private(set) var deliveryError: String?
  public init(
    preferences: any StudyNotificationPreferences = DefaultsStudyNotificationPreferences(),
    client: StudyNotificationClient = .system
  ) {
    self.preferences = preferences
    self.client = client
  }
  deinit {
    modelRead?.cancel()
    storeRead?.cancel()
  }
  /// App-owned source; windows do not replace it or hold up companion publication on OS I/O.
  public func observe(model: StudyAppModel, lessonSettings: StudyLessonSettings) {
    modelRead?.cancel()
    storeRead?.cancel()
    dataRead?.cancel()
    revision &+= 1
    source = {
      let preferences = lessonSettings.value
      let snapshot = try await model.serviceSnapshot(lessonPreferences: preferences)
      guard lessonSettings.value == preferences else { throw CancellationError() }
      return snapshot
    }
    let id = UUID()
    binding = id
    modelRead = Task { [weak self] in
      await model.restore()
      var account: String?
      let changes = Observations {
        (model.serviceSourceReady, model.dataRevision, lessonSettings.value)
      }
      for await _ in changes {
        guard let self, !Task.isCancelled, self.binding == id else { return }
        let currentAccount = model.serviceSourceReady ? model.snapshot?.accountID : nil
        if account != currentAccount {
          account = currentAccount
          self.storeRead?.cancel()
          if let account, let store = model.savedWorkStore {
            self.storeRead = Task { [weak self] in
              for await _ in await store.changes() {
                guard let self, !Task.isCancelled, self.binding == id else { return }
                guard model.snapshot?.accountID == account, model.serviceSourceReady else {
                  continue
                }
                self.requestRefresh()
              }
            }
          }
        }
        guard model.serviceSourceReady else { continue }
        self.requestRefresh()
      }
    }
  }
  public func enabled(_ option: NotificationPreference) -> Bool {
    _ = preferenceRevision
    return preferences.value(for: option)
  }
  private func save(_ value: Bool, for option: NotificationPreference) {
    preferences.set(value, for: option)
    preferenceRevision &+= 1
  }
  private func apply(
    _ authorization: StudyNotificationAuthorization, to request: NotificationPermissionRequest
  ) -> Notice? {
    if case .authorized(let features) = authorization, features.contains(request.option) {
      save(true, for: request.option)
      return nil
    }
    save(false, for: request.option)
    return .systemSettings(request)
  }
  @discardableResult public func change(_ option: NotificationPreference, enabled: Bool) async
    -> Notice?
  {
    guard !busy else { return nil }
    busy = true
    let request = NotificationPermissionRequest(for: option)
    intents[option] = request.id
    var result: Notice?
    if !enabled {
      save(false, for: option)
    } else {
      do {
        let authorization = await client.status()
        if authorization == .notDetermined {
          try await client.request()
          result = apply(await client.status(), to: request)
        } else {
          result = apply(authorization, to: request)
        }
      } catch {
        save(false, for: option)
        result = .error(error.localizedDescription)
      }
    }
    busy = false
    await refresh()
    return result
  }
  public func cancelSystemSettings(_ request: NotificationPermissionRequest) {
    if intents[request.option] == request.id { intents[request.option] = nil }
  }
  /// False asks the originating view to retry after another permission check finishes.
  @discardableResult public func resumed(_ request: NotificationPermissionRequest) async -> Bool {
    guard intents[request.option] == request.id else { return true }
    guard !busy else { return false }
    busy = true
    let authorization = await client.status()
    if intents[request.option] == request.id {
      if case .authorized(let features) = authorization {
        save(features.contains(request.option), for: request.option)
      }
      cancelSystemSettings(request)
    }
    busy = false
    await refresh()
    return true
  }
  /// Preserve the existing post-sign-in request; background updates never prompt.
  @discardableResult public func requestAuthorizationIfNeeded() async -> Notice? {
    guard !Task.isCancelled, !busy, NotificationPreference.allCases.contains(where: enabled) else {
      return nil
    }
    busy = true
    var result: Notice?
    if await client.status() == .notDetermined {
      do { try await client.request() } catch { result = .error(error.localizedDescription) }
    }
    busy = false
    await refresh()
    return result
  }
  public func update(source: @escaping @MainActor () async throws -> StudyServiceSnapshot)
    async
  {
    self.source = source
    await refresh()
  }
  public func refresh() async {
    requestRefresh()
    await delivery?.value
  }
  private func requestRefresh() {
    revision &+= 1
    let current = revision
    let load = source
    dataRead?.cancel()
    dataRead = Task {
      try Task.checkCancellation()
      guard let load else { return StudyServiceSnapshot() }
      let value = try await load()
      try Task.checkCancellation()
      guard current == revision else { throw CancellationError() }
      didRead(value)
      return value
    }
    if delivery == nil { delivery = Task { await deliver() } }
  }
  private func deliver() async {
    var completed: Int?
    while completed != revision {
      let current = revision
      completed = current
      deliveryError = nil
      let snapshot: StudyServiceSnapshot
      do {
        guard let dataRead else { throw CancellationError() }
        snapshot = try await dataRead.value
      } catch {
        snapshot = .init()
        deliveryError = error.localizedDescription
      }
      guard current == revision else { continue }
      let authorization = await client.status()
      guard current == revision else { continue }
      self.authorization = authorization
      let identifiers = await client.pending()
      guard current == revision else { continue }
      let owned = identifiers.filter(StudyNotificationPlan.owns)
      let slots = max(
        0, StudyNotificationPlan.pendingRequestLimit - identifiers.count + owned.count)
      client.remove(owned)
      let features: Set<NotificationPreference>
      if case .authorized(let allowed) = authorization {
        features = allowed.filter(enabled)
      } else {
        features = []
      }
      let plan = StudyNotificationPlan(
        reviewDates: snapshot.reviewDates, onVacation: snapshot.onVacation, features: features)
      do { try await client.badge(plan.badge) } catch { deliveryError = error.localizedDescription }
      guard current == revision else { continue }
      for entry in plan.entries.prefix(slots) {
        let content = UNMutableNotificationContent()
        if features.contains(.reviews) {
          content.body =
            "\(entry.count) review\(entry.count == 1 ? "" : "s") available (\(entry.newReviews) new)"
        }
        if features.contains(.sound) { content.sound = .default }
        if features.contains(.badge) { content.badge = NSNumber(value: entry.count) }
        let trigger = UNTimeIntervalNotificationTrigger(
          timeInterval: max(1, entry.date.timeIntervalSinceNow), repeats: false)
        do {
          try await client.add(
            .init(identifier: entry.identifier, content: content, trigger: trigger))
        } catch {
          deliveryError = error.localizedDescription
          break
        }
        if current != revision { break }
      }
    }
    delivery = nil
  }
}
