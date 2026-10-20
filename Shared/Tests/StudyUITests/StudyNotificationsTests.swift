import Foundation
import StudyCore
import StudyTestSupport
import StudyUI
import Testing
import UserNotifications

@MainActor private final class NotificationPreferences: StudyNotificationPreferences {
  var values: [NotificationPreference: Bool] = [:]
  func value(for option: NotificationPreference) -> Bool { values[option] ?? false }
  func set(_ value: Bool, for option: NotificationPreference) { values[option] = value }
}
@MainActor private final class NotificationProbe {
  enum Failure: Error { case expected }
  var authorization: StudyNotificationAuthorization = .authorized(
    Set(NotificationPreference.allCases))
  var granted = true
  var grantFeatures = Set(NotificationPreference.allCases)
  var failRequest = false
  var failBadge = false
  var failAdd = false
  var requests = 0
  var badges: [Int] = []
  var scheduled: [String: UNNotificationRequest] = [:]
  var statusGate: StudyTaskGate?
  var requestGate: StudyTaskGate?
  var addGate: StudyTaskGate?
  var client: StudyNotificationClient {
    .init(
      status: {
        let value = self.authorization
        if let gate = self.statusGate {
          self.statusGate = nil
          await gate.pause()
        }
        return value
      },
      request: {
        self.requests += 1
        if let gate = self.requestGate { await gate.pause() }
        if self.failRequest { throw Failure.expected }
        self.authorization = self.granted ? .authorized(self.grantFeatures) : .denied
      }, pending: { Array(self.scheduled.keys) },
      remove: { identifiers in
        for identifier in identifiers { self.scheduled.removeValue(forKey: identifier) }
      },
      badge: { value in
        if self.failBadge { throw Failure.expected }
        self.badges.append(value)
      },
      add: { request in
        if let gate = self.addGate {
          self.addGate = nil
          await gate.pause()
        }
        if self.failAdd { throw Failure.expected }
        self.scheduled[request.identifier] = request
      })
  }
  func reminder(_ id: String) {
    scheduled[id] = .init(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
  }
}

@MainActor struct StudyNotificationsTests {
  private func configured() -> (StudyNotifications, NotificationProbe, NotificationPreferences) {
    let preferences = NotificationPreferences()
    let probe = NotificationProbe()
    return (StudyNotifications(preferences: preferences, client: probe.client), probe, preferences)
  }
  private var snapshot: StudyServiceSnapshot {
    .init(
      reviewDates: [Date.now.addingTimeInterval(-60), Date.now.addingTimeInterval(1800)],
      onVacation: false)
  }
  @Test(arguments: NotificationPreference.allCases)
  func existingPermissionDoesNotPromptAgain(option: NotificationPreference) async {
    let (model, probe, preferences) = configured()
    let notice = await model.change(option, enabled: true)
    #expect(model.enabled(option) && preferences.values[option] == true)
    #expect(probe.requests == 0 && !model.busy && notice == nil)
    for other in NotificationPreference.allCases where other != option {
      #expect(!model.enabled(other))
    }
  }
  @Test(arguments: [true, false])
  func newPermissionStoresTheActualDecision(granted: Bool) async {
    let (model, probe, _) = configured()
    probe.authorization = .notDetermined
    probe.granted = granted
    await model.change(.reviews, enabled: true)
    #expect(model.enabled(.reviews) == granted && probe.requests == 1 && !model.busy)
  }
  @Test func partialPermissionAndSettingsResumeChangeOnlyTheRequestedChoice() async {
    let (model, probe, _) = configured()
    probe.authorization = .authorized([.badge])
    let notice = await model.change(.reviews, enabled: true)
    #expect(!model.enabled(.reviews) && probe.requests == 0)
    guard case .systemSettings(let request)? = notice else {
      Issue.record("Missing settings guidance")
      return
    }
    probe.authorization = .authorized(Set(NotificationPreference.allCases))
    #expect(await model.resumed(request))
    #expect(model.enabled(.reviews) && !model.enabled(.badge) && !model.enabled(.sound))
    probe.authorization = .denied
    guard case .systemSettings(let cancelled)? = await model.change(.sound, enabled: true) else {
      Issue.record("Missing second settings guidance")
      return
    }
    model.cancelSystemSettings(cancelled)
    probe.authorization = .authorized(Set(NotificationPreference.allCases))
    #expect(await model.resumed(cancelled))
    #expect(!model.enabled(.sound))
  }
  @Test func aGrantedRequestStillChecksIndividualSystemCapabilities() async {
    let (model, probe, _) = configured()
    probe.authorization = .notDetermined
    probe.grantFeatures = [.badge]
    let notice = await model.change(.reviews, enabled: true)
    #expect(!model.enabled(.reviews) && probe.requests == 1)
    if case .systemSettings? = notice {
    } else {
      Issue.record("Missing partial-permission guidance")
    }
  }
  @Test func failuresReleaseControlsAndOffSurvivesBadgeFailure() async {
    let (model, probe, preferences) = configured()
    probe.authorization = .notDetermined
    probe.failRequest = true
    let notice = await model.change(.reviews, enabled: true)
    #expect(!model.busy && !model.enabled(.reviews))
    if case .error? = notice {} else { Issue.record("Missing request failure") }
    probe.authorization = .authorized([.badge])
    preferences.set(true, for: .badge)
    probe.failBadge = true
    await model.change(.badge, enabled: false)
    #expect(!model.enabled(.badge) && !model.busy && model.deliveryError != nil)
  }
  @Test func anOverlappingToggleCannotStartAnotherPrompt() async {
    let (model, probe, _) = configured()
    let gate = StudyTaskGate()
    probe.authorization = .notDetermined
    probe.requestGate = gate
    let first = Task { await model.change(.reviews, enabled: true) }
    await gate.waitForEntry()
    await model.change(.badge, enabled: true)
    #expect(probe.requests == 1 && !model.enabled(.badge) && model.busy)
    await gate.resume()
    #expect(await first.value == nil)
    #expect(!model.busy && model.enabled(.reviews))
  }
  @Test func anAwaitedPermissionStatusCannotStartTwoDefaultRequests() async {
    let (model, probe, preferences) = configured()
    let gate = StudyTaskGate()
    preferences.set(true, for: .badge)
    probe.authorization = .notDetermined
    probe.statusGate = gate
    let first = Task { await model.requestAuthorizationIfNeeded() }
    await gate.waitForEntry()
    await model.requestAuthorizationIfNeeded()
    #expect(model.busy && probe.requests == 0)
    await gate.resume()
    #expect(await first.value == nil)
    #expect(!model.busy && probe.requests == 1)
  }
  @Test func backgroundUpdatesNeverRequestPermissionButExplicitSignInCan() async {
    let (model, probe, preferences) = configured()
    preferences.set(true, for: .badge)
    probe.authorization = .notDetermined
    await model.update { snapshot }
    #expect(probe.requests == 0 && probe.badges.last == 0 && probe.scheduled.isEmpty)
    await model.requestAuthorizationIfNeeded()
    await model.requestAuthorizationIfNeeded()
    #expect(probe.requests == 1 && probe.badges.last == 1)
  }
  @Test func nativeContentMatchesAllowedFeaturesAndPreservesOtherReminders() async throws {
    let (model, probe, preferences) = configured()
    for option in NotificationPreference.allCases { preferences.set(true, for: option) }
    for id in ["badge-0", "usagi.reviews.old", "other-reminder", "badge-other"] {
      probe.reminder(id)
    }
    await model.update { snapshot }
    let request = try #require(
      probe.scheduled.values.first { StudyNotificationPlan.owns($0.identifier) })
    #expect(probe.badges.last == 1 && request.content.badge == 2)
    #expect(request.content.body == "2 reviews available (1 new)" && request.content.sound != nil)
    let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
    #expect(trigger.timeInterval > 0 && !trigger.repeats)
    #expect(
      probe.scheduled.count == 3 && probe.scheduled["other-reminder"] != nil
        && probe.scheduled["badge-other"] != nil)
  }
  @Test func eachWindowKeepsItsOwnPermissionNoticeWhileDeliveryIsRunning() async {
    let (model, probe, _) = configured()
    let gate = StudyTaskGate()
    var reads = 0
    await model.update {
      reads += 1
      if reads == 2 { await gate.pause() }
      return .init()
    }
    probe.authorization = .denied
    var firstNotice: StudyNotifications.Notice?
    let first = Task {
      firstNotice = await model.change(.reviews, enabled: true)
    }
    await gate.waitForEntry()
    probe.authorization = .authorized(Set(NotificationPreference.allCases))
    let second = Task { await model.change(.badge, enabled: true) }
    for _ in 0..<1000 where !model.enabled(.badge) { await Task.yield() }
    #expect(model.enabled(.badge))
    await gate.resume()
    await first.value
    #expect(await second.value == nil)
    if case .systemSettings? = firstNotice {
    } else {
      Issue.record("Another window overwrote the first permission notice")
    }
  }
  @Test func separateWindowsResumeOnlyTheirOwnPermissionIntent() async {
    let (model, probe, _) = configured()
    probe.authorization = .denied
    guard case .systemSettings(let reviews)? = await model.change(.reviews, enabled: true),
      case .systemSettings(let sound)? = await model.change(.sound, enabled: true)
    else {
      Issue.record("Missing separate permission requests")
      return
    }
    probe.authorization = .authorized(Set(NotificationPreference.allCases))
    #expect(await model.resumed(reviews))
    #expect(model.enabled(.reviews) && !model.enabled(.sound))
    #expect(await model.resumed(sound))
    #expect(model.enabled(.sound))
  }
  @Test func anOldSettingsReturnCannotReenableALaterDisabledChoice() async {
    let (model, probe, _) = configured()
    probe.authorization = .denied
    guard case .systemSettings(let old)? = await model.change(.reviews, enabled: true) else {
      Issue.record("Missing permission request")
      return
    }
    await model.change(.reviews, enabled: false)
    probe.authorization = .authorized(Set(NotificationPreference.allCases))
    #expect(await model.resumed(old))
    #expect(!model.enabled(.reviews))
  }
  @Test func unrelatedRemindersKeepTheirShareOfThePendingRequestLimit() async {
    let (model, probe, preferences) = configured()
    preferences.set(true, for: .reviews)
    for id in ["reminder-one", "reminder-two", "reminder-three"] { probe.reminder(id) }
    await model.update {
      .init(
        reviewDates: (1...100).map { Date.now.addingTimeInterval(Double($0 * 3600)) },
        onVacation: false)
    }
    #expect(probe.scheduled.count == 64)
    #expect(probe.scheduled.keys.filter(StudyNotificationPlan.owns).count == 61)
    for id in ["reminder-one", "reminder-two", "reminder-three"] {
      #expect(probe.scheduled[id] != nil)
    }
  }
  @Test func badgeOnlyWorkHonorsSoundAndDisabledBadgingClearsTheCurrentBadge() async throws {
    let (model, probe, preferences) = configured()
    preferences.set(true, for: .badge)
    preferences.set(true, for: .sound)
    await model.update { snapshot }
    let badgeOnly = try #require(probe.scheduled.values.first)
    #expect(
      badgeOnly.content.body.isEmpty && badgeOnly.content.sound != nil
        && badgeOnly.content.badge == 2)
    await model.change(.sound, enabled: false)
    #expect(probe.scheduled.values.first?.content.sound == nil && probe.badges.last == 1)
    await model.change(.badge, enabled: false)
    #expect(probe.badges.last == 0 && probe.scheduled.isEmpty)
  }
  @Test func systemFeatureOverridesCannotProduceSoundOrBadgesTheUserDisabled() async throws {
    let (model, probe, preferences) = configured()
    for option in NotificationPreference.allCases { preferences.set(true, for: option) }
    probe.authorization = .authorized([.reviews])
    await model.update { snapshot }
    let request = try #require(probe.scheduled.values.first)
    #expect(
      !request.content.body.isEmpty && request.content.sound == nil && request.content.badge == nil)
    #expect(probe.badges.last == 0)
  }
  @Test(arguments: [true, false])
  func vacationOrDeniedPermissionRemovesOwnedRequests(vacation: Bool) async {
    let (model, probe, preferences) = configured()
    preferences.set(true, for: .badge)
    preferences.set(true, for: .reviews)
    await model.update { snapshot }
    probe.reminder("other-reminder")
    if !vacation { probe.authorization = .denied }
    await model.update { .init(reviewDates: snapshot.reviewDates, onVacation: vacation) }
    #expect(probe.badges.last == 0 && Array(probe.scheduled.keys) == ["other-reminder"])
  }
  @Test func aSourceFailureClearsOldAccountWorkAndAnExplicitRetryCanRecover() async {
    let (model, probe, preferences) = configured()
    preferences.set(true, for: .badge)
    probe.reminder("badge-0")
    await model.update { throw NotificationProbe.Failure.expected }
    #expect(probe.badges.last == 0 && probe.scheduled.isEmpty && model.deliveryError != nil)
    probe.failAdd = true
    await model.update { snapshot }
    #expect(model.deliveryError != nil && probe.scheduled.isEmpty)
    probe.failAdd = false
    await model.refresh()
    #expect(model.deliveryError == nil && probe.scheduled.count == 1)
  }
  @Test func aSlowOldAddCannotResurrectNotificationsAfterLogout() async {
    let (model, probe, preferences) = configured()
    preferences.set(true, for: .badge)
    let gate = StudyTaskGate()
    probe.addGate = gate
    let old = Task { await model.update { snapshot } }
    await gate.waitForEntry()
    var requested = false
    let clear = Task {
      requested = true
      await model.update { .init() }
    }
    for _ in 0..<1000 where !requested { await Task.yield() }
    #expect(requested)
    await gate.resume()
    await old.value
    await clear.value
    #expect(probe.badges.last == 0 && probe.scheduled.isEmpty)
  }
  @Test func aSlowOldReadIsFencedBeforeNewAccountDelivery() async {
    let (model, probe, preferences) = configured()
    preferences.set(true, for: .reviews)
    let gate = StudyTaskGate()
    let old = Task {
      await model.update {
        await gate.pause()
        return .init(
          reviewDates: Array(repeating: Date.now.addingTimeInterval(3600), count: 100),
          onVacation: false)
      }
    }
    await gate.waitForEntry()
    var requested = false
    let current = Task {
      requested = true
      await model.update {
        .init(reviewDates: [Date.now.addingTimeInterval(3600)], onVacation: false)
      }
    }
    for _ in 0..<1000 where !requested { await Task.yield() }
    #expect(requested)
    await gate.resume()
    await old.value
    await current.value
    #expect(probe.scheduled.count == 1)
    #expect(probe.scheduled.values.first?.content.body == "1 review available (1 new)")
  }
  @Test func companionClearingIsIndependentOfNotificationPermissionsAndBlockedDelivery() async {
    let (model, probe, _) = configured()
    probe.authorization = .denied
    let status = StudyTaskGate()
    let published = StudyTaskGate()
    probe.statusGate = status
    var seen: [StudyCompanionSnapshot] = []
    model.didRead = { value in
      seen.append(.init(value))
      if value.onVacation { Task { await published.pause() } }
    }
    let value = snapshot
    let first = Task { await model.update { value } }
    await status.waitForEntry()
    #expect(seen.count == 1 && seen[0].reviews == 1 && probe.requests == 0)
    let logout = Task { await model.update { .init() } }
    await published.waitForEntry()
    #expect(seen.count == 2 && seen.last?.reviews == 0 && seen.last?.level == 0)
    await published.resume()
    await status.resume()
    await first.value
    await logout.value
    #expect(probe.requests == 0 && probe.badges.last == 0 && probe.scheduled.isEmpty)
  }

  @Test func aLateAccountReadNeverPublishesAfterTheNewerLogoutRead() async {
    let (model, _, _) = configured()
    let oldRead = StudyTaskGate()
    let published = StudyTaskGate()
    let value = snapshot
    var seen: [StudyCompanionSnapshot] = []
    model.didRead = { value in
      seen.append(.init(value))
      Task { await published.pause() }
    }
    let old = Task {
      await model.update {
        await oldRead.pause()
        return value
      }
    }
    await oldRead.waitForEntry()
    let logout = Task { await model.update { .init() } }
    await published.waitForEntry()
    #expect(seen.count == 1 && seen[0].reviews == 0)
    await published.resume()
    await oldRead.resume()
    await old.value
    await logout.value
    #expect(seen.count == 1 && seen[0].reviews == 0)
  }

  @Test func failedReadsDoNotPublishFabricatedCompanionProgress() async {
    let (model, _, _) = configured()
    var seen: [StudyCompanionSnapshot] = []
    model.didRead = { seen.append(.init($0)) }
    let value = snapshot
    await model.update { value }
    await model.update { throw NotificationProbe.Failure.expected }
    #expect(seen.count == 1 && seen[0].reviews == 1 && model.deliveryError != nil)
  }

  @Test func permissionChecksWithoutAnAccountSourceDoNotPublishAFakeLogout() async {
    let (model, _, _) = configured()
    var reads = 0
    model.didRead = { _ in reads += 1 }
    await model.refresh()
    #expect(reads == 0)
    await model.update { .init() }
    #expect(reads == 1)
  }

}
