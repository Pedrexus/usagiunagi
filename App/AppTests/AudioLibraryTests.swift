import Foundation
import StudyCore
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor struct AudioLibraryTests {
  @Test func sharedAudioPreservesTheExistingArchivedPreferences() {
    let keys = ["offlineAudio", "offlineAudioCellular", "offlineAudioVoiceActors"]
    let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer {
      for (key, value) in zip(keys, previous) {
        if let value {
          UserDefaults.standard.set(value, forKey: key)
        } else {
          UserDefaults.standard.removeObject(forKey: key)
        }
      }
    }
    Settings.offlineAudio = true
    Settings.offlineAudioCellular = false
    Settings.offlineAudioVoiceActors = [3, 9]
    let adapter = LegacyAudioPreferences()
    #expect(adapter.options.enabled && adapter.options.voiceIDs == [3, 9])
    var options = adapter.options
    options.enabled = false
    options.cellular = true
    options.voiceIDs = [9]
    adapter.options = options
    #expect(
      !Settings.offlineAudio && Settings.offlineAudioCellular
        && Settings.offlineAudioVoiceActors == [9])
    #expect(keys.allSatisfy { UserDefaults.standard.data(forKey: $0) != nil })
  }
}
