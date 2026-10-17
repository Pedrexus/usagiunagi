import Foundation
import Observation
import StudyCore

@MainActor @Observable
public final class VoiceReviewController {
    public enum Phase: Equatable { case idle, preparing, needsModel, downloading, listening, finishing, reviewing, failed(String) }
    public private(set) var phase = Phase.idle
    public var text = ""
    public let question: StudyQuestion
    public var languageName: String { question.kind == .reading ? "Japanese" : "English" }
    public var needsKanaCorrection: Bool { question.kind == .reading && VoiceAnswerDraft.needsKanaCorrection(text) }
    public var canSubmit: Bool { phase == .reviewing && !VoiceAnswerDraft.cleanTranscript(text).isEmpty && !needsKanaCorrection }
    private let capture: any VoiceCapture
    private var draft: VoiceAnswerDraft?
    private var operation: Task<Void, Never>?
    private var timeout: Task<Void, Never>?

    public init(question: StudyQuestion, capture: any VoiceCapture = AppleVoiceCapture()) {
        self.question = question
        self.capture = capture
    }

    public func start(downloadModel: Bool = false) {
        let previous = operation
        cancel()
        let id = UUID()
        draft = VoiceAnswerDraft(question: question, recordingID: id)
        text = ""
        phase = .preparing
        let capture = capture
        let locale = Locale(identifier: question.kind == .reading ? "ja-JP" : "en-US")
        operation = Task { [weak self] in
            do {
                await previous?.value
                try Task.checkCancellation()
                try await capture.start(id: id, locale: locale, downloadModel: downloadModel) { [weak self] event in
                    await self?.receive(event, id: id)
                }
            } catch {
                guard let self, self.draft?.recordingID == id, !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    public func stop() {
        guard phase == .listening, let id = draft?.recordingID else { return }
        phase = .finishing
        let capture = capture
        operation = Task { [weak self] in
            do { try await capture.finish(id: id) }
            catch {
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

    public func cancel() {
        operation?.cancel()
        operation = nil
        timeout?.cancel()
        timeout = nil
        if let id = draft?.recordingID {
            let capture = capture
            Task { await capture.cancel(id: id) }
        }
        draft?.cancel()
        draft = nil
        text = ""
        phase = .idle
    }

    /// Requires both a finished recording and the same current question at the submission boundary.
    public func answer(for currentQuestion: StudyQuestion) -> String? {
        guard canSubmit, draft?.answer(for: currentQuestion) != nil else { return nil }
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
        case .listening: phase = .listening
        case let .segment(text, start, end, isFinal):
            if draft?.receive(text: text, start: start, end: end, isFinal: isFinal,
                              recordingID: id, question: question) == true {
                self.text = draft?.transcript ?? ""
            }
        case .finished:
            draft?.finish(recordingID: id, question: question)
            timeout?.cancel()
            timeout = nil
            text = draft?.answer(for: question) ?? ""
            phase = text.isEmpty ? .failed("No speech was recognized. Try again or type your answer.") : .reviewing
        case let .failed(message):
            timeout?.cancel()
            let capture = capture
            Task { await capture.cancel(id: id) }
            phase = .failed(message)
        }
    }
}
