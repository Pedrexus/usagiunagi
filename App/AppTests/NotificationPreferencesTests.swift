import Foundation
import StudyCore
import Testing

@testable import Tsurukame

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct NotificationPreferencesTests {
  @Test func disconnectedSettingsHostIgnoresLateAccountNotifications() async throws {
    let fixture = NativeAppAssemblyTests()
    let (assembly, store, server, spy, domain, directory) = try await fixture.environment(
      pending: true)
    defer { fixture.cleanup(domain, directory) }
    await assembly.model.restore()
    #expect(assembly.model.snapshot?.username == "Assembly fixture")
    #expect(assembly.model.profile?.level == 1)
    let gate = AssemblyGate()
    await server.pauseDownloads(using: gate)
    let refresh = Task { try await assembly.model.refresh(accountID: "assembly-fixture") }
    await gate.waitForEntry()
    let disconnect = Task { await assembly.model.disconnect() }
    await gate.waitForCancellation()
    #expect(assembly.model.isDisconnecting)
    gate.resume()
    await disconnect.value
    await #expect(throws: CancellationError.self) { try await refresh.value }
    await assembly.notifications.refresh()
    #expect(assembly.model.snapshot == nil && assembly.model.profile == nil)
    #expect(assembly.model.error == nil && !assembly.model.isSyncing)
    #expect(spy.packets.last?.level == 0 && spy.packets.last?.reviews == 0)
    #expect(try await store.pendingReviews(accountID: "assembly-fixture").count == 1)
    #expect(await server.writes == 0 && spy.requests == 0)
  }

  @Test func commonNotificationChoicesPreserveTheOriginalArchivedSettings() throws {
    try PreferenceTestValues.withDefaults { defaults in
      let options = NotificationPreference.allCases
      for option in options {
        try PreferenceTestValues.archive(true, key: option.key, in: defaults)
      }
      let originals = options.map { defaults.data(forKey: $0.key) }
      let source = try LegacyPreferenceImporter.read(defaults: defaults)
      try StudyPreferenceImport(defaults: defaults).apply(source, accountID: "fixture")
      let preferences = DefaultsStudyNotificationPreferences(defaults: defaults)
      for option in options {
        #expect(preferences.value(for: option))
        preferences.set(false, for: option)
        #expect(!preferences.value(for: option))
        #expect(defaults.object(forKey: "native.\(option.key)") is Bool)
      }
      #expect(options.map { defaults.data(forKey: $0.key) } == originals)
      #expect(originals.allSatisfy { $0 != nil })
    }
  }
  #if os(iOS)
    @Test func logoutQueuesAnEmptyWatchPacketWithoutActivatingARealSession() throws {
      let helper = WatchHelper(session: nil)
      helper.companion.update(.init())
      let packet = try #require(helper.pendingPacket)
      #expect(packet["reviewCount"] as? Int == 0 && packet["reviewHrCount"] as? Int == 0)
      #expect(packet["reviewHourly"] as? [Int] == [] && packet["nextReview"] as? Int64 == 0)
      #expect(packet["levelTotal"] as? Int == 0 && packet["levelLearn"] as? Int == 0)
      #expect(helper.companion.lastSentAt == nil)
    }
    @Test func companionWirePacketRetainsEveryExistingKeyAndValueType() {
      let now = Date(timeIntervalSince1970: 10_000)
      let source = StudyServiceSnapshot(
        reviewDates: [now, now.addingTimeInterval(3600)], onVacation: false,
        currentLevel: .init(
          number: 4, progress: [.init(kind: .kanji, stages: [(5, true), (1, true), (nil, false)])]))
      let packet = WatchHelper.packet(StudyCompanionSnapshot(source, now: now))
      #expect(
        Set(packet.keys) == [
          "reviewCount", "reviewHrCount", "reviewHourly", "level", "levelTotal", "levelLearn",
          "levelHalf", "nextReview",
        ])
      #expect(packet["reviewCount"] as? Int == 1 && packet["reviewHrCount"] as? Int == 1)
      #expect((packet["reviewHourly"] as? [Int])?.count == 24)
      #expect(
        packet["level"] as? Int == 4 && packet["levelTotal"] as? Int == 3
          && packet["levelLearn"] as? Int == 1)
      #expect(packet["levelHalf"] as? Bool == false && packet["nextReview"] as? Int64 == 13_600)
    }
  #endif
}
