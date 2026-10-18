import Foundation
import Testing
import UIKit
import UserNotifications

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

  private func withPreferences(_ body: @MainActor () async throws -> Void) async rethrows {
    var saved: [String: Any] = [:]
    for option in NotificationPreference.allCases {
      saved[option.setting.key] = UserDefaults.standard.object(forKey: option.setting.key)
      var setting = option.setting
      setting.wrappedValue = false
    }
    defer {
      for option in NotificationPreference.allCases {
        if let value = saved[option.setting.key] {
          UserDefaults.standard.set(value, forKey: option.setting.key)
        } else {
          UserDefaults.standard.removeObject(forKey: option.setting.key)
        }
      }
    }
    try await body()
  }

  @Test(arguments: [UNAuthorizationStatus.authorized, .provisional, .ephemeral])
  func existingPermissionDoesNotPromptAgain(_ status: UNAuthorizationStatus) async {
    await withPreferences {
      let probe = NotificationProbe(status: status)
      let model = NotificationPermissionModel(client: probe.client)
      await model.change(.sound, enabled: true)
      #expect(model.enabled(.sound) && !model.enabled(.reviews) && !model.enabled(.badge))
      #expect(probe.requests == 0 && !model.busy && model.notice == nil)
      #expect(
        UserDefaults.standard.object(forKey: NotificationPreference.sound.setting.key) is Data)
    }
  }

  @Test(arguments: [true, false])
  func newPermissionStoresTheActualDecision(_ granted: Bool) async {
    await withPreferences {
      let probe = NotificationProbe(status: .notDetermined)
      probe.granted = granted
      let model = NotificationPermissionModel(client: probe.client)
      await model.change(.reviews, enabled: true)
      #expect(model.enabled(.reviews) == granted)
      #expect(probe.requests == 1 && !model.busy)
    }
  }

  @Test func deniedPermissionResumesOnlyTheRequestedSetting() async {
    await withPreferences {
      let probe = NotificationProbe(status: .denied)
      let model = NotificationPermissionModel(client: probe.client)
      await model.change(.badge, enabled: true)
      #expect(!model.enabled(.badge) && probe.requests == 0 && !model.busy)
      if case .systemSettings? = model.notice {
      } else {
        Issue.record("Missing system-settings guidance")
      }
      probe.status = .provisional
      await model.resumed()
      #expect(model.enabled(.badge) && !model.enabled(.reviews) && !model.enabled(.sound))
      #expect(model.notice == nil)
      probe.status = .denied
      await model.change(.sound, enabled: true)
      model.cancelSystemSettings()
      probe.status = .authorized
      await model.resumed()
      #expect(!model.enabled(.sound))
    }
  }

  @Test func failuresReleaseControlsAndOffSurvivesBadgeFailure() async {
    await withPreferences {
      let probe = NotificationProbe(status: .notDetermined)
      probe.fail = true
      let model = NotificationPermissionModel(client: probe.client)
      await model.change(.reviews, enabled: true)
      #expect(!model.busy && !model.enabled(.reviews))
      if case .error? = model.notice {} else { Issue.record("Missing permission failure") }
      probe.status = .authorized
      await model.change(.badge, enabled: true)
      #expect(model.enabled(.badge))
      await model.change(.badge, enabled: false)
      #expect(!model.enabled(.badge) && !model.busy && probe.badgeClears == 1)
    }
  }

  @Test func anOverlappingToggleCannotStartAnotherPrompt() async {
    await withPreferences {
      let probe = NotificationProbe(status: .notDetermined)
      probe.pause = true
      let model = NotificationPermissionModel(client: probe.client)
      let first = Task { await model.change(.reviews, enabled: true) }
      for _ in 0..<100 where probe.continuation == nil { await Task.yield() }
      guard probe.continuation != nil else {
        Issue.record("Permission request did not start")
        first.cancel()
        await first.value
        return
      }
      #expect(model.busy)
      await model.change(.badge, enabled: true)
      #expect(probe.requests == 1 && !model.enabled(.badge))
      probe.finish(true)
      await first.value
      #expect(!model.busy && model.enabled(.reviews))
    }
  }
}

@MainActor private final class NotificationProbe {
  enum Failure: Error { case expected }
  var status: UNAuthorizationStatus
  var granted = true
  var fail = false
  var pause = false
  var requests = 0
  var badgeClears = 0
  var continuation: CheckedContinuation<Bool, Never>?
  init(status: UNAuthorizationStatus) { self.status = status }
  var client: NotificationAuthorization {
    .init(
      status: { self.status },
      request: {
        self.requests += 1
        if self.fail { throw Failure.expected }
        if self.pause { return await withCheckedContinuation { self.continuation = $0 } }
        return self.granted
      },
      clearBadge: {
        self.badgeClears += 1
        if self.fail { throw Failure.expected }
      })
  }
  func finish(_ granted: Bool) {
    continuation?.resume(returning: granted)
    continuation = nil
  }
}
