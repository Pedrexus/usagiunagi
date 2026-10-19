import Foundation
import StudyCore
import Testing

struct StudyNotificationPlanTests {
  private let hour = Date(timeIntervalSince1970: 1_800_000_000)
  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
  }
  @Test func futureReviewsNeverUseTheEarlierRelativeBucketBoundary() throws {
    let due = hour.addingTimeInterval(85 * 60)
    let plan = StudyNotificationPlan(
      reviewDates: [due], onVacation: false, features: [.reviews],
      now: hour.addingTimeInterval(37 * 60), calendar: calendar)
    let entry = try #require(plan.entries.first)
    #expect(entry.date == hour.addingTimeInterval(120 * 60) && entry.date >= due)
    #expect(entry.count == 1 && entry.newReviews == 1 && plan.badge == 0)
  }
  @Test func cohortsUseCumulativeCountsAndKeepAnExactHourAtThatHour() {
    let dates = [20, 50, 85, 120].map { hour.addingTimeInterval(Double($0 * 60)) }
    let plan = StudyNotificationPlan(
      reviewDates: dates, onVacation: false, features: [.badge],
      now: hour.addingTimeInterval(37 * 60), calendar: calendar)
    #expect(plan.badge == 1)
    #expect(
      plan.entries.map(\.date) == [hour.addingTimeInterval(3600), hour.addingTimeInterval(7200)])
    #expect(plan.entries.map(\.count) == [2, 4] && plan.entries.map(\.newReviews) == [1, 2])
    #expect(Set(plan.entries.map(\.identifier)).count == 2)
  }
  @Test(arguments: [true, false])
  func vacationAndDisabledDeliveryDoNotCreateFutureWork(vacation: Bool) {
    let features: Set<NotificationPreference> = vacation ? [.badge, .reviews, .sound] : [.sound]
    let plan = StudyNotificationPlan(
      reviewDates: [hour, hour.addingTimeInterval(7200)],
      onVacation: vacation, features: features, now: hour, calendar: calendar)
    #expect(plan.badge == 0 && plan.entries.isEmpty)
  }
  @Test func onlyTheFirst64FutureCohortsAreScheduled() {
    let dates = (1...100).map { hour.addingTimeInterval(Double($0 * 3600)) }
    let plan = StudyNotificationPlan(
      reviewDates: dates + [dates[0]], onVacation: false,
      features: [.reviews], now: hour, calendar: calendar)
    #expect(plan.entries.count == 64)
    #expect(plan.entries.first?.count == 2 && plan.entries.last?.count == 65)
    #expect(plan.entries.last?.date == dates[63])
  }
  @Test(arguments: ["America/New_York", "Australia/Lord_Howe", "Asia/Kathmandu"])
  func timezoneAndClockChangesNeverScheduleAheadOfAvailability(zone: String) throws {
    var calendar = calendar
    calendar.timeZone = try #require(TimeZone(identifier: zone))
    let formatter = ISO8601DateFormatter()
    for start in ["2026-11-01T04:37:00Z", "2026-04-04T14:37:00Z", "2026-03-08T06:37:00Z"] {
      let now = try #require(formatter.date(from: start))
      let dates = [0, 900, 3600, 5400, 7200].map { now.addingTimeInterval(Double($0)) }
      let plan = StudyNotificationPlan(
        reviewDates: dates, onVacation: false, features: [.reviews],
        now: now.addingTimeInterval(-1), calendar: calendar)
      #expect(plan.entries.last?.count == dates.count)
      for entry in plan.entries {
        #expect(entry.date > now.addingTimeInterval(-1))
        #expect(entry.count == dates.filter { $0 <= entry.date }.count)
      }
    }
  }
  @Test func requestOwnershipNeverIncludesOtherReminders() {
    for id in ["badge-0", "badge-200", "usagi.reviews.1800000000"] {
      #expect(StudyNotificationPlan.owns(id))
    }
    for id in ["badge", "badge-other", "other-reminder", "usagi.other.1800000000"] {
      #expect(!StudyNotificationPlan.owns(id))
    }
  }
  @Test @MainActor func nativePreferencesUseBooleansWithoutChangingArchivedKeys() throws {
    let suite = "notifications.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data([1, 2, 3]), forKey: NotificationPreference.badge.key)
    defaults.set("preserved", forKey: "unrelated")
    let preferences = DefaultsStudyNotificationPreferences(defaults: defaults)
    #expect(preferences.value(for: .badge) && !preferences.value(for: .reviews))
    preferences.set(false, for: .badge)
    preferences.set(true, for: .sound)
    let reopened = DefaultsStudyNotificationPreferences(defaults: defaults)
    #expect(!reopened.value(for: .badge) && reopened.value(for: .sound))
    #expect(defaults.object(forKey: "native.notificationSounds") as? Bool == true)
    #expect(defaults.data(forKey: NotificationPreference.badge.key) == Data([1, 2, 3]))
    #expect(defaults.string(forKey: "unrelated") == "preserved")
  }
}
