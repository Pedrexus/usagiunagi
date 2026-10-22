import Foundation
import StudyCore
import Testing

@MainActor enum PreferenceTestValues {
  static func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
    let domain = "usagi-preferences-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    try test(defaults)
  }
}

@Suite(.serialized) @MainActor
struct ReviewSessionOptionsTests {
  @Test(arguments: StudySessionOptions.AnkiMode.allCases)
  func ankiModeAndCombinedAnswersSurviveNativeRoundTrip(mode: StudySessionOptions.AnkiMode)
    throws
  {
    var value = ReviewPreferences()
    value.sessionOptions.ankiMode = mode
    value.sessionOptions.combinedAnki = mode == .both
    let restored = try JSONDecoder().decode(
      ReviewPreferences.self, from: JSONEncoder().encode(value))
    #expect(restored.sessionOptions.ankiMode == mode)
    #expect(restored.sessionOptions.combinedAnki == (mode == .both))
    #expect(mode.includes(.meaning) == (mode == .meaning || mode == .both))
    #expect(mode.includes(.reading) == (mode == .reading || mode == .both))
  }
  @Test(arguments: StudyReviewOrder.allCases)
  func reviewOrderingSurvivesNativeRoundTrip(order: StudyReviewOrder) throws {
    var value = ReviewPreferences()
    value.policy.order = order
    let restored = try JSONDecoder().decode(
      ReviewPreferences.self, from: JSONEncoder().encode(value))
    #expect(restored.policy.order == order)
  }
}
