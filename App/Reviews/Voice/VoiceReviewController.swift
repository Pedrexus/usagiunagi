import Foundation
import Observation
import StudyCore

@MainActor @Observable
public final class VoiceReviewController {
  public enum Phase: Equatable {
    case idle, preparing, needsModel, downloading, listening, finishing, reviewing
    case failed(String)
  }
  public private(set) var phase = Phase.idle
  public var text = ""
  public private(set) var liveText = ""
  public private(set) var shouldRepeat = false
  public let question: StudyQuestion
  public var languageName: String { question.kind == .reading ? "Japanese" : "English" }
  public var needsKanaCorrection: Bool {
    question.kind == .reading && VoiceAnswerDraft.needsKanaCorrection(text)
  }
  public var canSubmit: Bool {
    phase == .reviewing && !VoiceAnswerDraft.cleanTranscript(text).isEmpty && !needsKanaCorrection
  }
  public var readingSuggestions: [String] {
    draft?.readingSuggestions.filter { $0 != VoiceAnswerDraft.cleanTranscript(text) } ?? []
  }
  private let capture: any VoiceCapture
  @ObservationIgnored private var draft: VoiceAnswerDraft?
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var timeout: Task<Void, Never>?
  @ObservationIgnored private var endOfAnswer: Task<Void, Never>?

  public init(question: StudyQuestion, capture: any VoiceCapture = AppleVoiceCapture()) {
    self.question = question
    self.capture = capture
  }

  @discardableResult public func start(downloadModel: Bool = false) -> Task<Void, Never> {
    let previous = operation
    let cleanup = cancel()
    let id = UUID()
    draft = VoiceAnswerDraft(question: question, recordingID: id)
    text = ""
    phase = .preparing
    let capture = capture
    let locale = Locale(identifier: question.kind == .reading ? "ja-JP" : "en-US")
    let operation = Task { [weak self] in
      do {
        await previous?.value
        await cleanup?.value
        try Task.checkCancellation()
        try await capture.start(id: id, locale: locale, downloadModel: downloadModel) {
          [weak self] event in
          await self?.receive(event, id: id)
        }
      } catch {
        guard let self, self.draft?.recordingID == id, !Task.isCancelled else { return }
        self.phase = .failed(error.localizedDescription)
      }
    }
    self.operation = operation
    return operation
  }

  public func stop() {
    guard phase == .listening, let id = draft?.recordingID else { return }
    endOfAnswer?.cancel()
    endOfAnswer = nil
    phase = .finishing
    let capture = capture
    operation = Task { [weak self] in
      do { try await capture.finish(id: id) } catch {
        guard let self, self.draft?.recordingID == id, !Task.isCancelled else { return }
        guard self.phase == .finishing else { return }
        self.phase = .failed(error.localizedDescription)
      }
    }
    timeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(15)) } catch { return }
      guard let self, self.draft?.recordingID == id, self.phase == .finishing else { return }
      self.cancel()
      self.phase = .failed("Speech recognition took too long to finish. Try again or keep typing.")
    }
  }

  @ObservationIgnored private var cleanup: Task<Void, Never>?

  /// Releases hardware after failure or model setup without clearing the displayed message.
  @discardableResult public func releaseCapture() -> Task<Void, Never>? {
    operation?.cancel()
    operation = nil
    timeout?.cancel()
    timeout = nil
    endOfAnswer?.cancel()
    endOfAnswer = nil
    if let id = draft?.recordingID {
      let capture = capture
      let previous = cleanup
      cleanup = Task {
        await previous?.value
        await capture.cancel(id: id)
      }
    }
    draft?.cancel()
    draft = nil
    return cleanup
  }

  @discardableResult public func cancel() -> Task<Void, Never>? {
    let cleanup = releaseCapture()
    text = ""
    liveText = ""
    shouldRepeat = false
    phase = .idle
    return cleanup
  }

  /// Requires both a finished recording and the same current question at the submission boundary.
  public func answer(
    for currentQuestion: StudyQuestion, usingSingleKanaInterpretation: Bool = false
  ) -> String? {
    guard phase == .reviewing, draft?.answer(for: currentQuestion) != nil else { return nil }
    if usingSingleKanaInterpretation, needsKanaCorrection,
      let reading = draft?.resolvedKanaReading
    {
      text = reading
    }
    guard canSubmit else { return nil }
    return VoiceAnswerDraft.cleanTranscript(text)
  }

  private func receive(_ event: VoiceCaptureEvent, id: UUID) {
    guard draft?.recordingID == id else { return }
    // Terminal states cannot be revived by callbacks already queued during cancellation.
    switch phase {
    case .idle, .reviewing, .failed: return
    default: break
    }
    switch event {
    case .needsModel: phase = .needsModel
    case .downloading: phase = .downloading
    case .listening:
      phase = .listening
      if !liveText.isEmpty { finishAfterPause(id: id) }
    case .segment(let text, let start, let end, let isFinal, let alternatives):
      if draft?.receive(
        text: text, start: start, end: end, isFinal: isFinal,
        recordingID: id, question: question, alternatives: alternatives) == true
      {
        self.text = draft?.transcript ?? ""
      }
      guard start.isFinite, end.isFinite, end >= start,
        !VoiceAnswerDraft.cleanTranscript(text).isEmpty
      else { return }
      liveText = isFinal ? self.text : text
      if phase == .listening { finishAfterPause(id: id) }
    case .finished:
      draft?.finish(recordingID: id, question: question)
      timeout?.cancel()
      timeout = nil
      endOfAnswer?.cancel()
      endOfAnswer = nil
      text = draft?.answer(for: question) ?? ""
      shouldRepeat = text.isEmpty
      phase =
        text.isEmpty
        ? .failed("No speech was recognized. Try again or type your answer.") : .reviewing
    case .failed(let message):
      phase = .failed(message)
      releaseCapture()
    }
  }

  private func finishAfterPause(id: UUID) {
    endOfAnswer?.cancel()
    endOfAnswer = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
      guard let self, self.draft?.recordingID == id else { return }
      self.stop()
    }
  }
}
