import Foundation
import StudyCore
import Testing
import UIKit

@testable import Tsurukame

@Suite(.serialized) @MainActor
struct NotificationPreferencesTests {
  @Test func disconnectedSettingsHostIgnoresLateAccountNotifications() async {
    let controller = StoryboardScene.Settings.initialScene.instantiate()
    controller.loadViewIfNeeded()
    controller.rootView?.navigation.username = "Waiting for an account update"
    NotificationCenter.default.post(name: .lccPendingItemsChanged, object: nil)
    for _ in 0..<100 where controller.rootView?.navigation.username != "" { await Task.yield() }
    #expect(controller.rootView?.navigation.username == "")
    #expect(controller.rootView?.navigation.level == 0)
    #expect(controller.rootView?.navigation.pendingReviews == 0)
  }

  @Test func commonNotificationChoicesPreserveTheOriginalArchivedSettings() {
    let options = NotificationPreference.allCases
    let defaults = UserDefaults.standard
    let saved = Dictionary(
      uniqueKeysWithValues: options.map { ($0.key, defaults.object(forKey: $0.key)) })
    defer {
      for option in options {
        if let value = saved[option.key] ?? nil {
          defaults.set(value, forKey: option.key)
        } else {
          defaults.removeObject(forKey: option.key)
        }
      }
    }
    let preferences = LegacyNotificationPreferences()
    for option in options {
      preferences.set(true, for: option)
      #expect(preferences.value(for: option))
      #expect(defaults.object(forKey: option.key) is Data)
      preferences.set(false, for: option)
      #expect(!preferences.value(for: option))
    }
    #expect(
      !Settings.notificationsAllReviews && !Settings.notificationsBadging
        && !Settings.notificationSounds)
  }
  @Test func theFirstWatchPacketParticipatesInTheThirtySecondDuplicateWindow() {
    let helper = WatchHelper(session: nil)
    let packet: [String: Any] = ["reviewCount": 2, "reviewHourly": [3, 4]]
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(helper.shouldSendPacket(packet: packet, now: now))
    #expect(!helper.shouldSendPacket(packet: packet, now: now.addingTimeInterval(1)))
    #expect(!helper.shouldSendPacket(packet: packet, now: now.addingTimeInterval(29.99)))
    #expect(helper.shouldSendPacket(packet: packet, now: now.addingTimeInterval(30)))
  }
  @Test func changedWatchDataAndClockRollbackAreNeverSuppressed() {
    let helper = WatchHelper(session: nil)
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(helper.shouldSendPacket(packet: ["reviewCount": 2], now: now))
    #expect(helper.shouldSendPacket(packet: ["reviewCount": 3], now: now.addingTimeInterval(1)))
    #expect(!helper.shouldSendPacket(packet: ["reviewCount": 3], now: now.addingTimeInterval(2)))
    #expect(helper.shouldSendPacket(packet: ["reviewCount": 3], now: now.addingTimeInterval(-3600)))
  }
  @Test func logoutQueuesAnEmptyWatchPacketWithoutActivatingARealSession() throws {
    let helper = WatchHelper(session: nil)
    helper.updatedData(client: nil)
    let packet = try #require(helper.pendingPacket)
    #expect(packet["reviewCount"] as? Int == 0 && packet["reviewHrCount"] as? Int == 0)
    #expect(packet["reviewHourly"] as? [Int] == [] && packet["nextReview"] as? Int64 == 0)
    #expect(packet["levelTotal"] as? Int == 0 && packet["levelLearn"] as? Int == 0)
    #expect(helper.lastPacketSignature == nil && helper.lastPacketSentAt == nil)
  }
}
