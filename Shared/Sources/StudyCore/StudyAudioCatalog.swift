import Foundation

public struct StudyAudioOptions: Codable, Equatable, Sendable {
  public var enabled = false
  public var cellular = false
  public var voiceIDs: Set<Int64> = []
  public init() {}
}

public struct StudyAudioCatalog: Equatable, Sendable {
  public let accountID: String
  public let currentLevel: Int
  public let maximumLevel: Int
  public let voices: [StudyVoiceActor]
  public let audio: [StudyAudioReference]
  public init(
    accountID: String, currentLevel: Int, maximumLevel: Int,
    voices: [StudyVoiceActor], audio: [StudyAudioReference]
  ) {
    self.accountID = accountID
    self.currentLevel = currentLevel
    self.maximumLevel = maximumLevel
    self.voices = voices.sorted { $0.id < $1.id }
    self.audio = audio.sorted {
      ($0.level, $0.subjectID, $0.voiceActorID) < ($1.level, $1.subjectID, $1.voiceActorID)
    }
  }
  public func downloads(for selectedVoices: Set<Int64>) -> [StudyAudioReference] {
    guard maximumLevel > 0 else { return [] }
    let current = min(max(1, currentLevel), maximumLevel)
    let levels =
      [current] + (1..<current).reversed() + (current < maximumLevel ? [current + 1] : [])
    let knownVoices = Set(voices.map(\.id)).intersection(selectedVoices)
    return levels.flatMap { level in
      audio.filter { $0.level == level && knownVoices.contains($0.voiceActorID) }
    }
  }
}
