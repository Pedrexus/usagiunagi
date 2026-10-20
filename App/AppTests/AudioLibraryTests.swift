import Foundation
import StudyCore
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor struct AudioLibraryTests {
  @Test func sharedAudioPreservesTheExistingArchivedPreferences() throws {
    try PreferenceTestValues.withDefaults { defaults in
      let keys = ["offlineAudio", "offlineAudioCellular", "offlineAudioVoiceActors"]
      try PreferenceTestValues.archive(true, key: keys[0], in: defaults)
      try PreferenceTestValues.archive(false, key: keys[1], in: defaults)
      try PreferenceTestValues.archive(Set<Int64>([3, 9]), key: keys[2], in: defaults)
      let original = keys.map { defaults.data(forKey: $0) }
      let source = try LegacyPreferenceImporter.read(defaults: defaults)
      try StudyPreferenceImport(defaults: defaults).apply(source, accountID: "fixture")
      let preferences = DefaultsStudyAudioPreferences(defaults: defaults)
      #expect(preferences.options.enabled && !preferences.options.cellular)
      #expect(preferences.options.voiceIDs == [3, 9])
      var options = preferences.options
      options.enabled = false
      options.cellular = true
      options.voiceIDs = [9]
      preferences.options = options
      #expect(DefaultsStudyAudioPreferences(defaults: defaults).options == options)
      #expect(!defaults.bool(forKey: "native.offlineAudio"))
      #expect(defaults.bool(forKey: "native.offlineAudioCellular"))
      #expect(defaults.array(forKey: "native.offlineAudioVoices") as? [Int64] == [9])
      #expect(original.allSatisfy { $0 != nil })
      #expect(keys.map { defaults.data(forKey: $0) } == original)
    }
  }
}
