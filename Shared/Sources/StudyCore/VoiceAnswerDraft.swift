import Foundation

/// Collects only finalized speech from one recording of one question.
/// Recognized text is input to the normal grader, never a pronunciation score.
public struct VoiceAnswerDraft: Sendable {
  private struct Segment: Sendable {
    let start: Double
    let end: Double
    let text: String
    let alternatives: [String]
  }
  public let question: StudyQuestion
  public let recordingID: UUID
  public private(set) var isFinished = false
  private var isCancelled = false
  private var segments: [Segment] = []

  public init(question: StudyQuestion, recordingID: UUID) {
    self.question = question
    self.recordingID = recordingID
  }

  @discardableResult
  public mutating func receive(
    text: String, start: Double, end: Double, isFinal: Bool,
    recordingID: UUID, question: StudyQuestion, alternatives: [String] = []
  ) -> Bool {
    guard matches(recordingID, question), !isFinished, isFinal,
      start.isFinite, end.isFinite, end >= start
    else { return false }
    segments.removeAll {
      ($0.start == start && $0.end == end) || ($0.start < end && $0.end > start)
    }
    segments.append(
      Segment(
        start: start, end: end, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
        alternatives: alternatives))
    segments.sort { $0.start < $1.start }
    return true
  }

  public mutating func finish(recordingID: UUID, question: StudyQuestion) {
    if matches(recordingID, question) { isFinished = true }
  }

  public mutating func cancel() {
    isCancelled = true
    isFinished = false
    segments.removeAll()
  }

  public var transcript: String {
    segments.map(\.text).filter { !$0.isEmpty }.joined(
      separator: question.kind == .reading ? "" : " ")
  }

  /// Only recognizer-supplied kana, joined in audio order. Nothing consults the answer key.
  public var readingSuggestions: [String] {
    guard question.kind == .reading, isFinished, !isCancelled else { return [] }
    var suggestions = [""]
    for segment in segments {
      guard !Self.cleanTranscript(segment.text).isEmpty else { continue }
      var choices: [String] = []
      for value in [segment.text] + segment.alternatives {
        let value = Self.cleanTranscript(value)
        guard !value.isEmpty, !Self.needsKanaCorrection(value), !choices.contains(value) else {
          continue
        }
        choices.append(value)
        if choices.count == 3 { break }
      }
      guard !choices.isEmpty else { return [] }
      // Bound combinations instead of expanding every permutation of a long recording.
      suggestions = suggestions.flatMap { stem in choices.map { stem + $0 } }
        .reduce(into: []) { result, value in
          if result.count < 6, !result.contains(value) { result.append(value) }
        }
    }
    return suggestions.filter { $0 != Self.cleanTranscript(transcript) }
  }

  public func answer(for currentQuestion: StudyQuestion) -> String? {
    guard matches(recordingID, currentQuestion), isFinished else { return nil }
    let answer = Self.cleanTranscript(transcript)
    return answer.isEmpty ? nil : answer
  }

  public static func cleanTranscript(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
  }

  public static func needsKanaCorrection(_ text: String) -> Bool {
    let kana = CharacterSet(charactersIn: Unicode.Scalar(0x3040)!..<Unicode.Scalar(0x3100)!)
    return cleanTranscript(text).unicodeScalars.contains { !kana.contains($0) }
  }

  private func matches(_ id: UUID, _ question: StudyQuestion) -> Bool {
    !isCancelled && recordingID == id && self.question == question
  }
}
