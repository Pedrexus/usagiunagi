import Foundation
import StudyCore
import Testing

@testable import Tsurukame

private actor FakeCapture: VoiceCapture {
  var callbacks: [UUID: VoiceCaptureReport] = [:]
  var ids: [UUID] = []
  var cancelled: [UUID] = []
  var finishes = 0
  var locales: [String] = []
  let cancelDelay: Duration
  let transcript: String
  let alternatives: [String]
  let needsModel: Bool
  let startError: VoiceCaptureError?
  let partialBeforeListening: Bool
  init(
    transcript: String = "One.", needsModel: Bool = false, startError: VoiceCaptureError? = nil,
    cancelDelay: Duration = .zero, alternatives: [String] = [], partialBeforeListening: Bool = false
  ) {
    self.transcript = transcript
    self.alternatives = alternatives
    self.needsModel = needsModel
    self.startError = startError
    self.cancelDelay = cancelDelay
    self.partialBeforeListening = partialBeforeListening
  }
  func start(id: UUID, locale: Locale, downloadModel: Bool, report: @escaping VoiceCaptureReport)
    async throws
  {
    if let startError { throw startError }
    ids.append(id)
    locales.append(locale.identifier)
    callbacks[id] = report
    if needsModel && !downloadModel {
      await report(.needsModel)
    } else {
      if partialBeforeListening { await partial(id: id, text: "One") }
      await report(.listening)
    }
  }
  func finish(id: UUID) async {
    finishes += 1
    await callbacks[id]?(.segment(text: "interim error", start: 0, end: 1, isFinal: false))
    await callbacks[id]?(
      .segment(text: transcript, start: 0, end: 1, isFinal: true, alternatives: alternatives))
    await callbacks[id]?(.finished)
  }
  func cancel(id: UUID) async {
    try? await Task.sleep(for: cancelDelay)
    cancelled.append(id)
  }  // Keep callbacks so tests can inject a late result after cancellation.
  func fail(id: UUID) async { await callbacks[id]?(.failed("Recording interrupted")) }
  func partial(id: UUID, text: String) async {
    await callbacks[id]?(.segment(text: text, start: 0, end: 1, isFinal: false))
  }
  func lateResult(id: UUID) async {
    await callbacks[id]?(
      .segment(text: "Late", start: 0, end: 1, isFinal: true, alternatives: ["おそい"]))
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

  @Test func failedCaptureCleanupKeepsItsMessageAndWaitsForHardwareRelease() async throws {
    let capture = FakeCapture(cancelDelay: .milliseconds(50))
    let model = VoiceReviewController(question: try question(), capture: capture)
    model.start()
    try await waitFor { model.phase == .listening }
    let id = try #require(await capture.ids.first)
    await capture.fail(id: id)
    let cleanup = try #require(model.releaseCapture())
    #expect(model.phase == .failed("Recording interrupted"))
    await cleanup.value
    #expect(await capture.cancelled == [id])
    #expect(model.phase == .failed("Recording interrupted") && !model.shouldRepeat)
    await capture.lateResult(id: id)
    #expect(model.phase == .failed("Recording interrupted") && model.text.isEmpty)
    model.start()
    try await waitFor { model.phase == .listening }
    await model.cancel()?.value
  }

  @Test func missingModelCleanupKeepsTheDownloadActionAndRejectsLateResults() async throws {
    let capture = FakeCapture(needsModel: true, cancelDelay: .milliseconds(50))
    let model = VoiceReviewController(question: try question(), capture: capture)
    model.start()
    try await waitFor { model.phase == .needsModel }
    let id = try #require(await capture.ids.first)
    await model.releaseCapture()?.value
    #expect(model.phase == .needsModel && !model.canSubmit)
    #expect(await capture.cancelled == [id])
    await capture.lateResult(id: id)
    #expect(model.phase == .needsModel && model.text.isEmpty)
    model.start(downloadModel: true)
    try await waitFor { model.phase == .listening }
    await model.cancel()?.value
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

  @Test func aPauseFinishesOnceAndUsesFinalTextInsteadOfTheLivePreview() async throws {
    let capture = FakeCapture()
    let question = try question()
    let model = VoiceReviewController(question: question, capture: capture)
    model.start()
    try await waitFor { model.phase == .listening }
    let id = try #require(await capture.ids.first)
    await capture.partial(id: id, text: "Won")
    #expect(model.liveText == "Won" && model.text.isEmpty && !model.canSubmit)
    try await Task.sleep(for: .milliseconds(700))
    await capture.partial(id: id, text: "Single")
    try await Task.sleep(for: .milliseconds(700))
    #expect(model.phase == .listening && model.answer(for: question) == nil)
    try await waitFor { model.phase == .reviewing }
    #expect(model.answer(for: question) == "One")
    #expect(await capture.finishes == 1)
    await model.cancel()?.value
  }

  @Test func anExplicitFinishCancelsThePendingPause() async throws {
    let capture = FakeCapture()
    let model = VoiceReviewController(question: try question(), capture: capture)
    model.start()
    try await waitFor { model.phase == .listening }
    let id = try #require(await capture.ids.first)
    await capture.partial(id: id, text: "One")
    model.stop()
    try await waitFor { model.phase == .reviewing }
    try await Task.sleep(for: .milliseconds(1300))
    #expect(await capture.finishes == 1)
    await model.cancel()?.value
  }

  @Test func aCanceledPauseCannotFinishTheNextRecording() async throws {
    let capture = FakeCapture()
    let model = VoiceReviewController(question: try question(), capture: capture)
    model.start()
    try await waitFor { model.phase == .listening }
    let id = try #require(await capture.ids.first)
    await capture.partial(id: id, text: "One")
    await model.cancel()?.value
    model.start()
    try await waitFor { model.phase == .listening }
    await capture.partial(id: id, text: "Late")
    try await Task.sleep(for: .milliseconds(1300))
    #expect(model.phase == .listening && model.liveText.isEmpty)
    #expect(await capture.finishes == 0)
    await model.cancel()?.value
  }

  @Test func anEmptyFinalResultCannotSubmitAnEarlierPartial() async throws {
    let capture = FakeCapture(transcript: "")
    let question = try question()
    let model = VoiceReviewController(question: question, capture: capture)
    model.start()
    try await waitFor { model.phase == .listening }
    let id = try #require(await capture.ids.first)
    await capture.partial(id: id, text: "One")
    try await waitFor {
      model.phase == .failed("No speech was recognized. Try again or type your answer.")
    }
    #expect(!model.canSubmit && model.answer(for: question) == nil)
    #expect(model.shouldRepeat)
    await model.cancel()?.value
    #expect(!model.shouldRepeat)
  }

  @Test func speechArrivingDuringPreparationStillFinishesAfterAPause() async throws {
    let capture = FakeCapture(partialBeforeListening: true)
    let question = try question()
    let model = VoiceReviewController(question: question, capture: capture)
    model.start()
    try await waitFor { model.phase == .reviewing }
    #expect(model.answer(for: question) == "One")
    #expect(await capture.finishes == 1)
    await model.cancel()?.value
  }

  @Test(arguments: [
    ("一", ["いち"], "いち"), ("1つ", ["ひつ", "ひとつ"], "ひとつ"),
    ("生", ["せい", "しょう"], nil), ("一", [], nil), ("スーパー", [], "スーパー"),
    ("ビーる", [], "ビーる"), ("1つ", ["ヒつ", "ヒトつ"], "ヒトつ"),
  ])
  func continuousVoicePreservesKanaScriptWithoutUsingTheAnswerKey(
    transcript: String, alternatives: [String], expected: String?
  ) async throws {
    let question = try question(reading: true)
    let model = VoiceReviewController(
      question: question, capture: FakeCapture(transcript: transcript, alternatives: alternatives))
    model.start()
    try await waitFor { model.phase == .listening }
    model.stop()
    try await waitFor { model.phase == .reviewing }
    #expect(model.text == transcript)
    #expect(model.answer(for: try self.question(), usingSingleKanaInterpretation: true) == nil)
    #expect(model.text == transcript)
    let answer = model.answer(for: question, usingSingleKanaInterpretation: true)
    #expect(answer == expected)
    #expect(model.text == (expected ?? transcript))
    #expect(model.liveText == transcript)
    await model.cancel()?.value
  }

  @Test(arguments: [false, true])
  func theQuestionSelectsEnglishOrJapaneseWithoutAnotherUserChoice(reading: Bool) async throws {
    let capture = FakeCapture()
    let model = VoiceReviewController(question: try question(reading: reading), capture: capture)
    model.start()
    try await waitFor { model.phase == .listening }
    #expect(await capture.locales == [reading ? "ja-JP" : "en-US"])
    await model.cancel()?.value
  }

  @Test func aKanaAlternativeRequiresExplicitSelectionAndCannotSurviveRestart() async throws {
    let question = try question(reading: true)
    let capture = FakeCapture(transcript: "1つ", alternatives: ["1つ", "ひとつ", "一つ"])
    let model = VoiceReviewController(question: question, capture: capture)
    model.start()
    try await waitFor { model.phase == .listening }
    let id = try #require(await capture.ids.first)
    #expect(model.readingSuggestions.isEmpty && !model.canSubmit)
    model.stop()
    try await waitFor { model.phase == .reviewing }
    #expect(model.text == "1つ" && model.readingSuggestions == ["ひとつ"])
    #expect(model.needsKanaCorrection && model.answer(for: question) == nil)
    model.text = try #require(model.readingSuggestions.first)
    #expect(model.answer(for: question) == "ひとつ" && model.readingSuggestions.isEmpty)
    await capture.lateResult(id: id)
    #expect(model.text == "ひとつ" && model.phase == .reviewing)
    await model.cancel()?.value
    #expect(model.readingSuggestions.isEmpty && !model.canSubmit)
    model.start()
    try await waitFor { model.phase == .listening }
    await capture.lateResult(id: id)
    #expect(model.readingSuggestions.isEmpty && model.text.isEmpty && model.phase == .listening)
    await model.cancel()?.value
  }

}
