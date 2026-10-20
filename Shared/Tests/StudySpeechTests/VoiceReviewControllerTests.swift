import Foundation
import StudyCore
import StudySpeech
import Testing

private actor FakeCapture: VoiceCapture {
  var callbacks: [UUID: VoiceCaptureReport] = [:]
  var ids: [UUID] = []
  var cancelled: [UUID] = []
  let cancelDelay: Duration
  let transcript: String
  let needsModel: Bool
  let startError: VoiceCaptureError?
  init(
    transcript: String = "One.", needsModel: Bool = false, startError: VoiceCaptureError? = nil,
    cancelDelay: Duration = .zero
  ) {
    self.transcript = transcript
    self.needsModel = needsModel
    self.startError = startError
    self.cancelDelay = cancelDelay
  }
  func start(id: UUID, locale: Locale, downloadModel: Bool, report: @escaping VoiceCaptureReport)
    async throws
  {
    if let startError { throw startError }
    ids.append(id)
    callbacks[id] = report
    if needsModel && !downloadModel { await report(.needsModel) } else { await report(.listening) }
  }
  func finish(id: UUID) async {
    await callbacks[id]?(.segment(text: "interim error", start: 0, end: 1, isFinal: false))
    await callbacks[id]?(.segment(text: transcript, start: 0, end: 1, isFinal: true))
    await callbacks[id]?(.finished)
  }
  func cancel(id: UUID) async {
    try? await Task.sleep(for: cancelDelay)
    cancelled.append(id)
  }  // Keep callbacks so tests can inject a late result after cancellation.
  func fail(id: UUID) async { await callbacks[id]?(.failed("Recording interrupted")) }
  func lateResult(id: UUID) async {
    await callbacks[id]?(.segment(text: "Late", start: 0, end: 1, isFinal: true))
    await callbacks[id]?(.finished)
  }
}

@MainActor struct VoiceReviewControllerTests {
  private func question(reading: Bool = false) throws -> StudyQuestion {
    var session = try StudySession(items: [
      StudySessionItem(
        id: 0, subjectID: 1, assignmentID: 1, srsStage: 1,
        hasMeaning: !reading, hasReading: reading)
    ])
    let value = session.nextQuestion()
    return try #require(value)
  }
  private func waitFor(_ predicate: () -> Bool) async throws {
    for _ in 0..<200 {
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(predicate())
  }

  @Test func explicitStopProducesEditableFinalAnswer() async throws {
    let question = try question()
    let model = VoiceReviewController(question: question, capture: FakeCapture())
    model.start()
    try await waitFor { model.phase == .listening }
    #expect(!model.canSubmit && model.answer(for: question) == nil)
    model.stop()
    try await waitFor { model.phase == .reviewing }
    #expect(model.text == "One" && model.answer(for: question) == "One")
    model.text = "Single"
    #expect(model.answer(for: question) == "Single")
    model.cancel()
  }

  @Test func cancellationAndRestartRejectLateResults() async throws {
    let capture = FakeCapture()
    let model = VoiceReviewController(question: try question(), capture: capture)
    model.start()
    try await waitFor { model.phase == .listening }
    let ids = await capture.ids
    let first = try #require(ids.first)
    model.cancel()
    await capture.lateResult(id: first)
    try await Task.sleep(for: .milliseconds(20))
    #expect(model.phase == .idle && model.text.isEmpty)
    model.start()
    try await waitFor { model.phase == .listening }
    await capture.lateResult(id: first)
    try await Task.sleep(for: .milliseconds(20))
    #expect(model.phase == .listening && model.text.isEmpty)
    model.cancel()
  }

  @Test(arguments: [
    VoiceCaptureError.unavailable, .languageUnavailable, .microphoneDenied, .noMicrophone,
    .interrupted,
  ])
  func unavailableCaptureKeepsGradingDisabled(error: VoiceCaptureError) async throws {
    let question = try question()
    let model = VoiceReviewController(question: question, capture: FakeCapture(startError: error))
    model.start()
    try await waitFor { model.phase == .failed(error.localizedDescription) }
    #expect(!model.canSubmit && model.answer(for: question) == nil)
    model.cancel()
    #expect(model.phase == .idle)
  }

  @Test func interruptedCaptureCannotBeRevivedByLateResults() async throws {
    let capture = FakeCapture()
    let question = try question()
    let model = VoiceReviewController(question: question, capture: capture)
    model.start()
    try await waitFor { model.phase == .listening }
    let id = try #require(await capture.ids.first)
    await capture.fail(id: id)
    await capture.lateResult(id: id)
    #expect(model.phase == .failed("Recording interrupted"))
    #expect(!model.canSubmit && model.answer(for: question) == nil)
    model.cancel()
  }

  @Test func downloadNeedsAnExplicitAction() async throws {
    let model = VoiceReviewController(
      question: try question(), capture: FakeCapture(needsModel: true))
    model.start()
    try await waitFor { model.phase == .needsModel }
    #expect(!model.canSubmit)
    model.start(downloadModel: true)
    try await waitFor { model.phase == .listening }
    model.cancel()
  }

  @Test(arguments: [("一。", "いち"), ("1つ", "ひとつ")])
  func nonKanaTranscriptRequiresAnExplicitKanaCorrection(
    transcript: String, correction: String
  ) async throws {
    let question = try question(reading: true)
    let model = VoiceReviewController(
      question: question, capture: FakeCapture(transcript: transcript))
    model.start()
    try await waitFor { model.phase == .listening }
    model.stop()
    try await waitFor { model.phase == .reviewing }
    #expect(model.needsKanaCorrection && !model.canSubmit)
    #expect(model.answer(for: question) == nil)
    model.text = correction
    #expect(model.answer(for: question) == correction)
    model.cancel()
  }

  @Test func repeatedCancellationReturnsThePendingResourceCleanup() async throws {
    let capture = FakeCapture(cancelDelay: .milliseconds(50))
    let model = VoiceReviewController(question: try question(), capture: capture)
    model.start()
    try await waitFor { model.phase == .listening }
    let ids = await capture.ids
    model.cancel()
    let cleanup = model.cancel()
    #expect(model.phase == .idle && model.text.isEmpty)
    await cleanup?.value
    #expect(await capture.cancelled == ids)
  }

}
