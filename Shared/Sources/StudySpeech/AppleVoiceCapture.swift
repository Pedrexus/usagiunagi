// AVCaptureSession is not Sendable in SDK 27. NotificationCenter retains it as a sender
// filter; all app-owned access to the session remains on this capture actor.
@preconcurrency import AVFoundation
import Foundation
import Speech

/// Owns microphone and analyzer resources on one actor, away from UI rendering.
public actor AppleVoiceCapture: VoiceCapture {
  private var activeID: UUID?
  private var provider: CaptureInputSequenceProvider?
  private var analyzer: SpeechAnalyzer?
  private var resultTask: Task<Void, Never>?
  private var interruptionTasks: [Task<Void, Never>] = []
  #if os(iOS)
    private var priorAudio:
      (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
  #endif

  public init() {}

  public func start(
    id: UUID, locale: Locale, downloadModel: Bool,
    report: @escaping VoiceCaptureReport
  ) async throws {
    if let activeID { await cancel(id: activeID) }
    activeID = id
    do {
      guard SpeechTranscriber.isAvailable else { throw VoiceCaptureError.unavailable }
      guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
        throw VoiceCaptureError.languageUnavailable
      }
      try check(id)
      let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
      let status = await AssetInventory.status(forModules: [transcriber])
      try check(id)
      guard status != .unsupported else { throw VoiceCaptureError.languageUnavailable }
      if status != .installed {
        guard downloadModel else {
          await report(.needsModel)
          return
        }
        await report(.downloading)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [
          transcriber
        ]) {
          try await installation.downloadAndInstall()
        }
        try check(id)
      }
      guard await AVCaptureDevice.requestAccess(for: .audio) else {
        throw VoiceCaptureError.microphoneDenied
      }
      try check(id)
      guard let device = AVCaptureDevice.default(for: .audio) else {
        throw VoiceCaptureError.noMicrophone
      }
      let session = AVCaptureSession()
      #if os(iOS)
        session.automaticallyConfiguresApplicationAudioSession = false
      #endif
      let capture = try await CaptureInputSequenceProvider.provider(
        from: device, in: session, compatibleWith: [transcriber])
      try check(id)
      #if os(iOS)
        let audio = AVAudioSession.sharedInstance()
        priorAudio = (audio.category, audio.mode, audio.categoryOptions)
        try audio.setCategory(
          .playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audio.setActive(true)
      #endif
      provider = capture
      let analyzer = SpeechAnalyzer(modules: [transcriber])
      self.analyzer = analyzer
      resultTask = Task { [weak self] in
        do {
          for try await result in transcriber.results {
            guard let self, await self.isActive(id) else { return }
            await report(
              .segment(
                text: String(result.text.characters), start: result.range.start.seconds,
                end: result.range.end.seconds, isFinal: result.isFinal))
          }
          if let self, await self.isActive(id) {
            await self.stopAfterResults(id: id)
            await report(.finished)
          }
        } catch {
          guard let self, await self.isActive(id), !Task.isCancelled else { return }
          await report(.failed(error.localizedDescription))
          await self.cancel(id: id)
        }
      }
      try await analyzer.start(inputSequence: capture.analyzerInputs)
      try check(id)
      capture.captureSession.startRunning()
      guard capture.captureSession.isRunning else { throw VoiceCaptureError.interrupted }
      for name in [
        AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification,
      ] {
        let notifications = NotificationCenter.default.notifications(
          named: name, object: capture.captureSession)
        interruptionTasks.append(
          Task { [weak self] in
            for await _ in notifications {
              guard let self, await self.isActive(id), !Task.isCancelled else { return }
              await report(.failed(VoiceCaptureError.interrupted.localizedDescription))
              await self.cancel(id: id)
              return
            }
          })
      }
      await report(.listening)
    } catch {
      await cancel(id: id)
      throw error
    }
  }

  public func finish(id: UUID) async throws {
    try check(id)
    stopObserving()
    // The provider's input stream ends when its session/output are released, not merely stopped.
    stopCapture()
    guard let analyzer else { return }
    do {
      try await analyzer.finalizeAndFinishThroughEndOfInput()
      await resultTask?.value
      if activeID == id {
        activeID = nil
        self.analyzer = nil
        resultTask = nil
      }
    } catch {
      await cancel(id: id)
      throw error
    }
  }

  public func cancel(id: UUID) async {
    guard activeID == id else { return }
    activeID = nil
    resultTask?.cancel()
    resultTask = nil
    stopObserving()
    stopCapture()
    let previous = analyzer
    analyzer = nil
    await previous?.cancelAndFinishNow()
  }

  private func isActive(_ id: UUID) -> Bool { activeID == id }
  private func check(_ id: UUID) throws {
    try Task.checkCancellation()
    guard activeID == id else { throw CancellationError() }
  }

  private func stopObserving() {
    for task in interruptionTasks { task.cancel() }
    interruptionTasks.removeAll()
  }

  private func stopAfterResults(id: UUID) {
    guard activeID == id else { return }
    stopObserving()
    stopCapture()
  }

  private func stopCapture() {
    provider?.captureSession.stopRunning()
    provider = nil
    #if os(iOS)
      if let priorAudio {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setActive(false, options: .notifyOthersOnDeactivation)
        try? audio.setCategory(priorAudio.0, mode: priorAudio.1, options: priorAudio.2)
        self.priorAudio = nil
      }
    #endif
  }
}
