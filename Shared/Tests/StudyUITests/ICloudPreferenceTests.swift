import Foundation
import StudyCore
import SwiftData
import Testing

@testable import StudyPersistence
@testable import StudyUI

@MainActor struct ICloudPreferenceTests {
  private let key = "native.reviewPreferences"
  private typealias Change = PrivatePreferencesV1.Change

  @Test func openingNeverPublishesDeviceDefaults() throws {
    try fixture { store, defaults, _ in
      #expect(store.container != nil && !store.iCloudEnabled)
      let initial = try store.values()
      #expect(initial.isEmpty)
      #expect(defaults.data(forKey: key) == nil)
      store.recordChanges(from: .init(), to: .init())
      let unchanged = try store.values()
      #expect(unchanged.isEmpty)
      #expect(store.notice == nil)
    }
  }

  @Test func onlyTheThreeDisplayFieldsCanReachThePrivateStore() throws {
    try fixture { store, _, _ in
      var updated = ReviewPreferences()
      updated.appearance = .dark
      updated.fontScale = 1.5
      updated.stageIndicator = .dots
      updated.policy.limit = 77
      updated.exactMatch = true
      updated.autoplayAudio = true
      updated.sessionOptions.skipKanjiReadings = true
      store.recordChanges(from: .init(), to: updated)
      let values = try store.values()
      #expect(Set(values.map(\.field)) == ["appearance", "fontScale", "stageIndicator"])
      #expect(Set(values.map(\.value)) == ["dark", "1.5", "dots"])
      #expect(values.allSatisfy { $0.revision == 1 && $0.formatVersion == 1 })
      let container = try #require(store.container)
      #expect(container.schema.entities.count == 1)
      #expect(container.configurations.allSatisfy { $0.cloudKitContainerIdentifier == nil })
    }
  }

  @Test func remoteDisplayChangesPreserveGradingAndDoNotEchoIntoCloud() throws {
    try fixture { store, defaults, _ in
      var original = ReviewPreferences()
      original.exactMatch = true
      original.allowCorrections = false
      original.sessionOptions.skipKanjiReadings = true
      original.policy.limit = 77
      let protected = Data("fixture-only-account-and-upload-state".utf8)
      defaults.set(protected, forKey: "unrelated.account.state")
      defaults.set(try JSONEncoder().encode(original), forKey: key)
      let remote = [
        Change(field: "appearance", value: "dark", revision: 1),
        Change(field: "fontScale", value: "2.0", revision: 1),
        Change(field: "stageIndicator", value: "dots", revision: 1),
        Change(field: "apiToken", value: "must-never-apply", revision: 99),
      ].map(\.snapshot)
      store.reconcile(remote)
      var expected = original
      expected.appearance = .dark
      expected.fontScale = 2
      expected.stageIndicator = .dots
      let data = try #require(defaults.data(forKey: key))
      #expect(try JSONDecoder().decode(ReviewPreferences.self, from: data) == expected)
      #expect(defaults.data(forKey: "unrelated.account.state") == protected)
      #expect(defaults.object(forKey: "apiToken") == nil)
      store.reconcile(remote)
      #expect(defaults.data(forKey: key) == data)
      store.recordChanges(from: expected, to: expected)
      #expect(try store.values().isEmpty)
    }
  }

  @Test(arguments: [false, true])
  func concurrentEditsConvergePerFieldWithoutDependingOnArrivalOrder(reversed: Bool) throws {
    try fixture { store, defaults, _ in
      let lower = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
      let higher = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
      let edits = [
        Change(field: "appearance", value: "light", revision: 4, id: lower),
        Change(field: "appearance", value: "dark", revision: 4, id: higher),
        Change(field: "appearance", value: "system", revision: 3),
        Change(field: "fontScale", value: "1.75", revision: 1),
      ].map(\.snapshot)
      store.reconcile(reversed ? edits.reversed() : edits)
      let value = try JSONDecoder().decode(
        ReviewPreferences.self, from: #require(defaults.data(forKey: key)))
      #expect(value.appearance == .dark && value.fontScale == 1.75)
      #expect(value.stageIndicator == .name)
    }
  }

  @Test func committedEditsReopenAndAdvanceTheirLogicalVersion() throws {
    try fixture { store, defaults, directory in
      var dark = ReviewPreferences()
      dark.appearance = .dark
      store.recordChanges(from: .init(), to: dark)
      let original = try store.values()
      let reopened = StudyICloudPreferences(directory: directory, defaults: defaults)
      #expect(try reopened.values() == original)
      let restored = try JSONDecoder().decode(
        ReviewPreferences.self, from: #require(defaults.data(forKey: key)))
      #expect(restored.appearance == .dark)
      var light = dark
      light.appearance = .light
      reopened.recordChanges(from: dark, to: light)
      let edits = try reopened.values()
      #expect(edits.count == 2 && edits.map(\.revision).sorted() == [1, 2])
      #expect(edits.contains(original[0]))
      reopened.reconcile(edits)
      #expect(
        try JSONDecoder().decode(ReviewPreferences.self, from: #require(defaults.data(forKey: key)))
          .appearance == .light)
    }
  }

  @Test(arguments: ["NaN", "inf", "0.25", "2.75", "1.1", "not-a-number"])
  func invalidCloudFontSizesPreserveLocalData(value: String) throws {
    try fixture { store, defaults, _ in
      let original = try JSONEncoder().encode(ReviewPreferences())
      defaults.set(original, forKey: key)
      store.reconcile([Change(field: "fontScale", value: value, revision: 1).snapshot])
      #expect(defaults.data(forKey: key) == original)
      #expect(store.notice != nil)
      #expect(try store.values().isEmpty)
    }
  }

  @Test(arguments: [false, true])
  func futureVersionsAndRevisionOverflowCannotBeOverwritten(overflow: Bool) throws {
    try fixture { store, defaults, _ in
      let context = try #require(store.container?.mainContext)
      let remote = Change(field: "appearance", value: "dark", revision: overflow ? .max : 1)
      if !overflow { remote.formatVersion = 2 }
      context.insert(remote)
      try context.save()
      let original = try store.values()
      var edited = ReviewPreferences()
      edited.appearance = .light
      let local = try JSONEncoder().encode(edited)
      defaults.set(local, forKey: key)
      store.recordChanges(from: .init(), to: edited)
      #expect(try store.values() == original)
      #expect(defaults.data(forKey: key) == local && store.notice != nil)
      if !overflow {
        store.reconcile(original)
        #expect(defaults.data(forKey: key) == local)
      }
    }
  }

  @Test func malformedLocalPreferencesAreNotResetByCloud() throws {
    try fixture { store, defaults, _ in
      let original = Data("unreadable-future-local-settings".utf8)
      defaults.set(original, forKey: key)
      store.reconcile([Change(field: "appearance", value: "dark", revision: 1).snapshot])
      #expect(defaults.data(forKey: key) == original && store.notice != nil)
    }
  }

  @Test func unavailablePrivateStorageDoesNotBlockOrEraseLocalSettings() throws {
    try fixture { _, defaults, directory in
      let blocked = directory.appending(path: "not-a-directory")
      let marker = Data("preserve-this-file".utf8)
      try marker.write(to: blocked)
      let original = try JSONEncoder().encode(ReviewPreferences())
      defaults.set(original, forKey: key)
      let unavailable = StudyICloudPreferences(directory: blocked, defaults: defaults)
      #expect(unavailable.container == nil && !unavailable.iCloudEnabled)
      #expect(unavailable.notice != nil)
      #expect(defaults.data(forKey: key) == original)
      #expect(try Data(contentsOf: blocked) == marker)
      var edited = ReviewPreferences()
      edited.appearance = .dark
      let local = try JSONEncoder().encode(edited)
      defaults.set(local, forKey: key)
      unavailable.recordChanges(from: .init(), to: edited)
      unavailable.reconcile([Change(field: "appearance", value: "light", revision: 1).snapshot])
      #expect(defaults.data(forKey: key) == local && unavailable.notice != nil)
      try FileManager.default.removeItem(at: blocked)
      let retry = StudyICloudPreferences(directory: blocked, defaults: defaults)
      let saved = try retry.values()
      #expect(saved.count == 1 && saved[0].field == "appearance" && saved[0].value == "dark")
      #expect(defaults.object(forKey: "native.privateCloudPending.appearance") == nil)
      #expect(defaults.data(forKey: key) == local && retry.notice == nil)
    }
  }

  @Test func waniKaniModelsRemainInTheirExplicitlyLocalContainer() async throws {
    let store = try await StudyStore.open(
      at: URL.temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
    #expect(store.modelContainer.schema.entities.count == 10)
    #expect(
      store.modelContainer.configurations.allSatisfy { $0.cloudKitContainerIdentifier == nil })
    #expect(PrivatePreferencesV1.models.count == 1)
  }

  private func fixture(
    _ body: (StudyICloudPreferences, UserDefaults, URL) throws -> Void
  ) throws {
    let id = UUID().uuidString
    let directory = URL.temporaryDirectory.appending(path: "private-preferences-\(id)")
    let defaults = try #require(UserDefaults(suiteName: id))
    defer {
      defaults.removePersistentDomain(forName: id)
      try? FileManager.default.removeItem(at: directory)
    }
    try autoreleasepool {
      let store = StudyICloudPreferences(
        directory: directory, iCloudContainerIdentifier: "iCloud.com.pedrexus.usagiunagi.fixture",
        defaults: defaults)
      try body(store, defaults, directory)
    }
  }
}
