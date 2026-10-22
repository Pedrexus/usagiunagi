import Foundation
import StudyCore
import Testing

@Suite(.serialized) @MainActor struct AudioLibraryTests {
  @Test func sharedAudioChoicesPersistInNativeDefaults() throws {
    try PreferenceTestValues.withDefaults { defaults in
      defaults.set("keep", forKey: "unrelated")
      let preferences = DefaultsStudyAudioPreferences(defaults: defaults)
      var options = preferences.options
      options.enabled = true
      options.cellular = false
      options.voiceIDs = [3, 9]
      preferences.options = options
      #expect(DefaultsStudyAudioPreferences(defaults: defaults).options == options)
      options.enabled = false
      options.cellular = true
      options.voiceIDs = [9]
      preferences.options = options
      #expect(DefaultsStudyAudioPreferences(defaults: defaults).options == options)
      #expect(!defaults.bool(forKey: "native.offlineAudio"))
      #expect(defaults.bool(forKey: "native.offlineAudioCellular"))
      #expect(defaults.array(forKey: "native.offlineAudioVoices") as? [Int64] == [9])
      #expect(defaults.string(forKey: "unrelated") == "keep")
    }
  }
}
