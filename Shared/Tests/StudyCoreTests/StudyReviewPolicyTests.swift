import Foundation
import StudyCore
import Testing

struct StudyReviewPolicyTests {
  private let keys: [StudyReviewSortKey] = [
    .init(stage: 2, level: 2, kind: .kanji, availableAt: 100, relativeWait: 1),
    .init(stage: 1, level: 3, kind: .vocabulary, availableAt: 200, relativeWait: 4),
    .init(stage: 3, level: 1, kind: .radical, availableAt: 300, relativeWait: 2),
    .init(stage: 2, level: 2, kind: .radical, availableAt: 100, relativeWait: 1),
  ]
  @Test(arguments: [
    (StudyReviewOrder.ascendingSRSStage, [1, 3, 0, 2]), (.descendingSRSStage, [2, 3, 0, 1]),
    (.alternatingSRSStage, [1, 2, 3, 0]), (.currentLevelFirst, [1, 3, 0, 2]),
    (.lowestLevelFirst, [2, 3, 0, 1]), (.newestAvailableFirst, [2, 1, 3, 0]),
    (.oldestAvailableFirst, [3, 0, 1, 2]), (.longestRelativeWait, [1, 2, 3, 0]),
  ]) func originalOrdersProjectOnceAndApplyCapAfterSorting(order: StudyReviewOrder, expected: [Int])
  {
    var policy = StudyReviewPolicy()
    policy.order = order
    var generator = SystemRandomNumberGenerator()
    var calls = 0
    let sorted = policy.select(Array(keys.indices), using: &generator) {
      calls += 1
      return keys[$0]
    }
    #expect(sorted == expected && calls == keys.count)
    policy.limitEnabled = true
    policy.limit = 2
    #expect(
      policy.select(Array(keys.indices), using: &generator) { keys[$0] }
        == Array(expected.prefix(2)))
  }
  @Test func randomOrderPreservesEveryItemAndDoesNotReadUnusedMetadata() {
    var generator = SystemRandomNumberGenerator()
    let sorted = StudyReviewPolicy().select(Array(0..<100), using: &generator) { _ in
      Issue.record("Random order must not read SRS metadata")
      return keys[0]
    }
    #expect(Set(sorted) == Set(0..<100) && sorted.count == 100)
  }
  @Test func equalKeysRetainRandomTieOrder() {
    struct Generator: RandomNumberGenerator {
      var state: UInt64
      mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
      }
    }
    var policy = StudyReviewPolicy()
    policy.order = .ascendingSRSStage
    var a = Generator(state: 1)
    var b = Generator(state: 2)
    let first = policy.select(Array(0..<30), using: &a) { _ in keys[0] }
    let second = policy.select(Array(0..<30), using: &b) { _ in keys[0] }
    #expect(first != second && Set(first) == Set(second))
  }
  @Test func policyMergesOnlyChangedFieldsAndOlderArchivesKeepDefaults() throws {
    let original = ReviewPreferences()
    var saved = original
    saved.policy.order = .oldestAvailableFirst
    saved.policy.limit = 25
    var edited = original
    edited.policy.limitEnabled = true
    edited.policy.leechThreshold = 2.5
    saved.applyChanges(from: original, to: edited)
    #expect(saved.policy.order == .oldestAvailableFirst && saved.policy.limit == 25)
    #expect(saved.policy.limitEnabled && saved.policy.leechThreshold == 2.5)
    #expect(
      try JSONDecoder().decode(ReviewPreferences.self, from: JSONEncoder().encode(saved)) == saved)
    #expect(
      try JSONDecoder().decode(ReviewPreferences.self, from: Data("{}".utf8)).policy
        == original.policy)
    edited.policy.limit = -2
    edited.policy.leechThreshold = .nan
    #expect(edited.policy.normalized.limit == 1 && edited.policy.normalized.leechThreshold == 1)
  }
  @Test(arguments: [false, true]) func meaningOnlyLeechesDoNotNeedAReadingStreak(hasReading: Bool) {
    var policy = StudyReviewPolicy()
    let stats = StudyAnswerStatistics(subjectID: 1, meaningIncorrect: 4, meaningCurrentStreak: 2)
    #expect(policy.isLeech(stats, hasReading: hasReading) == !hasReading)
    policy.leechThreshold = 2
    #expect(!policy.isLeech(stats, hasReading: hasReading))
    let hidden = StudyAnswerStatistics(
      subjectID: 1, meaningIncorrect: 4, meaningCurrentStreak: 2, hidden: true)
    #expect(!StudyReviewPolicy().isLeech(hidden, hasReading: false))
  }
  @Test func cachedSRSOverridesLevelHeuristicAndMissingSystemsDoNotGuess() throws {
    var subject = CatalogSubject(id: 1, kind: .kanji)
    subject.level = 1
    subject.spacedRepetitionSystemID = 77
    let system = StudySRSSystem(
      id: 77, name: "Custom", unlockingStage: 0, startingStage: 1, passingStage: 2, burningStage: 3,
      stages: [
        .init(position: 0, interval: nil), .init(position: 1, interval: 90),
        .init(position: 2, interval: 180), .init(position: 3, interval: nil),
      ])
    try system.validate()
    #expect(try StudySRSSystem.interval(subject: subject, stage: 1, systems: [system]) == 90)
    #expect(throws: StudySRSSystem.MissingInterval.self) {
      try StudySRSSystem.interval(subject: subject, stage: 1, systems: nil)
    }
    subject.spacedRepetitionSystemID = nil
    #expect(try StudySRSSystem.interval(subject: subject, stage: 1, systems: nil) == 7200)
    subject.level = 3
    #expect(try StudySRSSystem.interval(subject: subject, stage: 1, systems: nil) == 14400)
  }
}
