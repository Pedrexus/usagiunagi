import Foundation

/// Server SRS intervals in seconds, cached with the account for offline review ordering.
public struct StudySRSSystem: Codable, Equatable, Identifiable, Sendable {
  public struct Stage: Codable, Equatable, Sendable {
    public let position: Int
    public let interval: TimeInterval?
    public init(position: Int, interval: TimeInterval?) {
      self.position = position
      self.interval = interval
    }
  }
  public let id: Int64
  public let name: String
  public let unlockingStage: Int
  public let startingStage: Int
  public let passingStage: Int
  public let burningStage: Int
  public let stages: [Stage]
  public init(
    id: Int64, name: String, unlockingStage: Int, startingStage: Int, passingStage: Int,
    burningStage: Int, stages: [Stage]
  ) {
    self.id = id
    self.name = name
    self.unlockingStage = unlockingStage
    self.startingStage = startingStage
    self.passingStage = passingStage
    self.burningStage = burningStage
    self.stages = stages
  }
  public func validate() throws(WaniKaniClient.APIError) {
    let positions = Set(stages.map(\.position))
    guard id > 0, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      unlockingStage >= 0, unlockingStage < startingStage, startingStage < passingStage,
      passingStage < burningStage, positions.count == stages.count,
      [unlockingStage, startingStage, passingStage, burningStage].allSatisfy(positions.contains),
      stages.allSatisfy({ stage in
        guard (unlockingStage...burningStage).contains(stage.position) else { return false }
        if stage.position == unlockingStage || stage.position == burningStage {
          return stage.interval == nil
        }
        return stage.interval.map { $0.isFinite && $0 > 0 } == true
      })
    else { throw .invalidResponse }
  }
  public static func interval(subject: CatalogSubject, stage: Int, systems: [Self]?) throws
    -> TimeInterval
  {
    if let id = subject.spacedRepetitionSystemID,
      let system = systems?.first(where: { $0.id == id }),
      let interval = system.stages.first(where: { $0.position == stage })?.interval
    {
      return interval
    }
    // Older imported subjects lack a system ID; old native caches only knew the two defaults.
    if subject.spacedRepetitionSystemID == nil
      || (systems == nil && [1, 2].contains(subject.spacedRepetitionSystemID))
    {
      let interval = legacyInterval(
        stage: stage,
        accelerated: subject.spacedRepetitionSystemID.map { $0 == 2 } ?? (subject.level <= 2))
      if interval > 0 { return interval }
    }
    throw MissingInterval()
  }
  public struct MissingInterval: Error, LocalizedError {
    public var errorDescription: String? {
      "Refresh WaniKani to load the SRS definitions needed for this review order."
    }
  }
  /// Compatibility for the original protobuf catalog, which did not retain SRS system IDs.
  public static func legacyInterval(stage: Int, accelerated: Bool) -> TimeInterval {
    switch stage {
    case 1: accelerated ? 7200 : 14400
    case 2: accelerated ? 14400 : 28800
    case 3: accelerated ? 28800 : 82800
    case 4: accelerated ? 82800 : 169200
    case 5: 601200
    case 6: 1_206_000
    case 7: 2_588_400
    case 8: 10_364_400
    default: 0
    }
  }
}
