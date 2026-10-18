import StudyCore
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor
struct ReviewSessionOptionsTests {
  @Test func legacySettingsProducePortableAnkiModes() {
    let previous = (
      Settings.ankiMode, Settings.ankiModeTaskType, Settings.ankiModeCombineReadingMeaning
    )
    defer {
      Settings.ankiMode = previous.0
      Settings.ankiModeTaskType = previous.1
      Settings.ankiModeCombineReadingMeaning = previous.2
    }
    let modes: [(AnkiModeTaskType, StudySessionOptions.AnkiMode)] = [
      (.both, .both), (.meaningOnly, .meaning), (.readingOnly, .reading),
    ]
    for enabled in [true, false] {
      for (legacy, portable) in modes {
        Settings.ankiMode = enabled
        Settings.ankiModeTaskType = legacy
        Settings.ankiModeCombineReadingMeaning = true
        let options = ReviewSession.currentOptions()
        #expect(options.ankiMode == (enabled ? portable : .off))
        #expect(options.combinedAnki == (enabled && legacy == .both))
      }
    }
  }
}
