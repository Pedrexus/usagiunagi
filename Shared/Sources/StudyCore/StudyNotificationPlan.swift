import Foundation

public enum NotificationPreference: String, Codable, CaseIterable, Identifiable, Sendable {
  case reviews, badge, sound
  public var id: Self { self }
  public var title: String {
    switch self {
    case .reviews: "Notify for all available reviews"
    case .badge: "Badge the app icon"
    case .sound: "Play sound with notifications"
    }
  }
  public var key: String {
    switch self {
    case .reviews: "notificationsAllReviews"
    case .badge: "notificationsBadging"
    case .sound: "notificationSounds"
    }
  }
  public var defaultValue: Bool { self == .badge }
}

@MainActor public protocol StudyNotificationPreferences: AnyObject {
  func value(for option: NotificationPreference) -> Bool
  func set(_ value: Bool, for option: NotificationPreference)
}

@MainActor public final class DefaultsStudyNotificationPreferences: StudyNotificationPreferences {
  private let defaults: UserDefaults
  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  public func value(for option: NotificationPreference) -> Bool {
    defaults.object(forKey: "native.\(option.key)") == nil
      ? option.defaultValue : defaults.bool(forKey: "native.\(option.key)")
  }
  public func set(_ value: Bool, for option: NotificationPreference) {
    defaults.set(value, forKey: "native.\(option.key)")
  }
}

/// Cohorts fire on a calendar-hour boundary at or after availability, never before it.
public struct StudyNotificationPlan: Sendable {
  public static let pendingRequestLimit = 64
  public struct Entry: Equatable, Sendable {
    public let date: Date
    public let count: Int
    public let newReviews: Int
    public var identifier: String { "usagi.reviews.\(Int64(date.timeIntervalSince1970))" }
  }
  public let badge: Int
  public let entries: [Entry]
  public init(
    reviewDates: [Date], onVacation: Bool, features: Set<NotificationPreference>,
    now: Date = .now, calendar: Calendar = .current
  ) {
    let current = onVacation ? 0 : reviewDates.filter { $0 <= now }.count
    badge = features.contains(.badge) ? current : 0
    guard !onVacation, features.contains(.reviews) || features.contains(.badge) else {
      entries = []
      return
    }
    var cohorts: [Date: Int] = [:]
    for date in reviewDates where date > now {
      guard let hour = calendar.dateInterval(of: .hour, for: date) else { continue }
      cohorts[date == hour.start ? date : hour.end, default: 0] += 1
    }
    var count = current
    entries = cohorts.keys.sorted().prefix(Self.pendingRequestLimit).map { date in
      let added = cohorts[date]!
      count += added
      return Entry(date: date, count: count, newReviews: added)
    }
  }
  public static func owns(_ identifier: String) -> Bool {
    identifier.hasPrefix("usagi.reviews.")
      || (identifier.hasPrefix("badge-") && Int(identifier.dropFirst(6)) != nil)
  }
}

/// Ephemeral permission intent; later changes to the same option invalidate this request.
public struct NotificationPermissionRequest: Identifiable, Sendable {
  public let id = UUID()
  public let option: NotificationPreference
  public init(for option: NotificationPreference) { self.option = option }
}
