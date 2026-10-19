import Foundation

public enum StudyReviewOrder: UInt, Codable, CaseIterable, Sendable, CustomStringConvertible {
  // Values preserve the original iOS archives.
  case random = 1
  case ascendingSRSStage = 2
  case currentLevelFirst = 3
  case lowestLevelFirst = 4
  case newestAvailableFirst = 5
  case oldestAvailableFirst = 6
  case descendingSRSStage = 7
  case longestRelativeWait = 8
  case alternatingSRSStage = 9
  public var description: String {
    switch self {
    case .random: "Random"
    case .ascendingSRSStage: "Ascending SRS stage"
    case .descendingSRSStage: "Descending SRS stage"
    case .currentLevelFirst: "Current level first"
    case .lowestLevelFirst: "Lowest level first"
    case .newestAvailableFirst: "Newest available first"
    case .oldestAvailableFirst: "Oldest available first"
    case .longestRelativeWait: "Longest relative wait"
    case .alternatingSRSStage: "Alternating SRS stage"
    }
  }
}

public struct StudyReviewSortKey: Sendable {
  public let stage: Int
  public let level: Int
  public let kind: SubjectKind
  public let availableAt: Int64
  public let relativeWait: Double
  public init(
    stage: Int, level: Int, kind: SubjectKind, availableAt: Int64, relativeWait: Double = 0
  ) {
    self.stage = stage
    self.level = level
    self.kind = kind
    self.availableAt = availableAt
    self.relativeWait = relativeWait
  }
  fileprivate var kindOrder: Int { kind == .radical ? 0 : kind == .kanji ? 1 : 2 }
}

/// Scheduled-review selection only. Lessons and extra study do not use the review cap.
public struct StudyReviewPolicy: Codable, Hashable, Sendable {
  public var order = StudyReviewOrder.random
  public var limitEnabled = false
  public var limit = 15
  public var leechThreshold = 1.0
  public init() {}
  public var normalized: Self {
    var value = self
    value.limit = max(1, limit)
    if !leechThreshold.isFinite || leechThreshold <= 0 { value.leechThreshold = 1 }
    return value
  }
  public func select<Item, RNG: RandomNumberGenerator>(
    _ items: [Item], using generator: inout RNG,
    key: (Item) throws -> StudyReviewSortKey
  ) rethrows -> [Item] {
    var result = items.shuffled(using: &generator)
    if order != .random {
      // Project once; a comparator must never fetch a subject from storage.
      var keyed = try result.enumerated().map {
        (offset: $0.offset, item: $0.element, key: try key($0.element))
      }
      keyed.sort { lhs, rhs in
        let a = lhs.key
        let b = rhs.key
        let primary: Bool?
        switch order {
        case .ascendingSRSStage, .alternatingSRSStage:
          primary = a.stage == b.stage ? nil : a.stage < b.stage
        case .descendingSRSStage: primary = a.stage == b.stage ? nil : a.stage > b.stage
        case .currentLevelFirst: primary = a.level == b.level ? nil : a.level > b.level
        case .lowestLevelFirst: primary = a.level == b.level ? nil : a.level < b.level
        case .newestAvailableFirst:
          primary = a.availableAt == b.availableAt ? nil : a.availableAt > b.availableAt
        case .oldestAvailableFirst:
          primary = a.availableAt == b.availableAt ? nil : a.availableAt < b.availableAt
        case .longestRelativeWait:
          primary = a.relativeWait == b.relativeWait ? nil : a.relativeWait > b.relativeWait
        case .random: primary = nil
        }
        return primary
          ?? (a.kindOrder == b.kindOrder ? lhs.offset < rhs.offset : a.kindOrder < b.kindOrder)
      }
      if order == .alternatingSRSStage {
        result = keyed.indices.map {
          keyed[$0.isMultiple(of: 2) ? $0 / 2 : keyed.count - 1 - $0 / 2].item
        }
      } else {
        result = keyed.map(\.item)
      }
    }
    return limitEnabled ? Array(result.prefix(normalized.limit)) : result
  }
  public func isLeech(_ stats: StudyAnswerStatistics, hasReading: Bool) -> Bool {
    guard !stats.hidden else { return false }
    let errors =
      hasReading ? max(stats.meaningIncorrect, stats.readingIncorrect) : stats.meaningIncorrect
    let streak =
      hasReading
      ? min(stats.meaningCurrentStreak, stats.readingCurrentStreak) : stats.meaningCurrentStreak
    return errors >= 0 && streak > 0
      && Double(errors) / pow(Double(streak), 1.5) >= normalized.leechThreshold
  }
}
