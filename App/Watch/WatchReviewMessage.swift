import Foundation

/// Paired-device messages carry a bounded answer, never credentials or an answer key.
struct WatchReviewRequest: Codable, Sendable {
  enum Action: String, Codable { case start, answer, advance, refresh, pause }
  static let maximumAudioBytes = 48_000
  static let maximumMessageBytes = 56_000
  var version = 1
  var id = UUID()
  let action: Action
  let runID: UUID
  var revision: UUID?
  var audio: Data?
}

struct WatchReviewResponse: Codable, Sendable {
  enum Outcome: String, Codable {
    case ready, correct, incorrect, repeatAnswer, finished, paused, unavailable
  }
  struct Prompt: Codable, Sendable {
    let characters: String
    let imageURL: URL?
    let kind: String
    let reading: Bool
  }
  let runID: UUID
  var outcome = Outcome.ready
  var requestID: UUID?
  var revision: UUID?
  var prompt: Prompt?
  var completed = 0
  var correct = 0
  var remaining = 0
  var feedback: String?
  var heard: String?
}
