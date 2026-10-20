import Foundation

public enum VoiceCaptureEvent: Sendable {
  case needsModel, downloading, listening
  case segment(text: String, start: Double, end: Double, isFinal: Bool)
  case finished
  case failed(String)
}

/// Export the closure's isolation semantics so Swift 5/6 hosts share the same callback type.
public typealias VoiceCaptureReport = @Sendable (VoiceCaptureEvent) async -> Void

public protocol VoiceCapture: Actor {
  func start(
    id: UUID, locale: Locale, downloadModel: Bool,
    report: @escaping VoiceCaptureReport) async throws
  func finish(id: UUID) async throws
  func cancel(id: UUID) async
}

public enum VoiceCaptureError: LocalizedError {
  case unavailable, languageUnavailable, microphoneDenied, noMicrophone, interrupted
  public var errorDescription: String? {
    switch self {
    case .unavailable: "Voice input isn’t available on this device. You can keep typing."
    case .languageUnavailable:
      "Speech recognition isn’t available for this language on this device."
    case .microphoneDenied:
      "Microphone access is off. Allow microphone access in Settings to use voice answers."
    case .noMicrophone: "No microphone is available. Connect one or keep typing."
    case .interrupted: "Recording was interrupted. Try again or keep typing."
    }
  }
}
