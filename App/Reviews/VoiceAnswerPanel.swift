import StudyCore
import SwiftUI

/// Stable environment identity; each question still receives its own capture actor.
nonisolated public final class StudyVoiceCaptureFactory: Sendable, Equatable {
  public static let system = StudyVoiceCaptureFactory()
  private let makeCapture: @Sendable () -> any VoiceCapture
  public init(_ makeCapture: @escaping @Sendable () -> any VoiceCapture = { AppleVoiceCapture() }) {
    self.makeCapture = makeCapture
  }
  public func callAsFunction() -> any VoiceCapture { makeCapture() }
  public static func == (left: StudyVoiceCaptureFactory, right: StudyVoiceCaptureFactory) -> Bool {
    left === right
  }
}

extension EnvironmentValues {
  @Entry public var studyVoiceCapture = StudyVoiceCaptureFactory.system
}

/// Practice sheets retain the exact question captured at presentation.
struct VoiceAnswerRequest: Identifiable {
  let question: StudyQuestion
  var id: StudyQuestion { question }
}

/// Practice can still confirm one transcript; reviews use the same controls inline.
public struct VoiceAnswerPanel: View {
  @State private var model: VoiceReviewController
  private let submit: (String) -> Void
  private let cancel: () -> Void

  public init(
    model: VoiceReviewController,
    submit: @escaping (String) -> Void, cancel: @escaping () -> Void
  ) {
    _model = State(initialValue: model)
    self.submit = submit
    self.cancel = cancel
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          Label(model.languageName + " answer", systemImage: "waveform")
          Text("Speak your answer, then check what was heard before submitting.")
            .foregroundStyle(.secondary)
        }
        Section {
          VoiceAnswerControls(
            model: model, automaticallySubmit: false, submit: submit, cancel: cancel)
        } footer: {
          Text(
            "Audio is processed on your device and isn’t saved by the app. Speech models are downloaded from Apple when needed."
          )
        }
      }
      .navigationTitle("Voice answer")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            model.cancel()
            cancel()
          }
        }
      }
    }
  }
}

/// One recording per question. Only finished text reaches the host's ordinary grader.
struct VoiceAnswerControls: View {
  @State private var model: VoiceReviewController
  private let automaticallySubmit: Bool
  private let startDelay: Duration
  private let submit: (String) -> Void
  private let cancel: () -> Void
  @Environment(\.scenePhase) private var scenePhase
  @Environment(StudyAudioLibrary.self) private var audio
  @AppStorage("native.autoSwitchKeyboard") private var automaticJapanese = false
  @State private var transcriptFocused = false
  @State private var audioLease: UUID?
  @State private var submission: Task<Void, Never>?
  @State private var sending = false
  @State private var captureBusy = false
  @State private var captureCleanup: Task<Void, Never>?
  @State private var starting: Task<Void, Never>?
  @State private var startRequested = false

  init(
    model: VoiceReviewController, automaticallySubmit: Bool, startDelay: Duration = .zero,
    submit: @escaping (String) -> Void, cancel: @escaping () -> Void
  ) {
    _model = State(initialValue: model)
    self.automaticallySubmit = automaticallySubmit
    self.startDelay = startDelay
    self.submit = submit
    self.cancel = cancel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if captureBusy {
        Label(
          "The microphone is busy. Finish the other voice session, then try again.",
          systemImage: "mic.slash"
        )
        .accessibilityIdentifier("voice.busy")
        Button("Try again", systemImage: "arrow.counterclockwise") { start() }
      } else {
        captureControls
      }
      Button("Use keyboard", systemImage: "keyboard") { cancel() }
        .accessibilityIdentifier("voice.keyboard")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .disabled(sending)
    .task {
      do { try await Task.sleep(for: startDelay) } catch { return }
      guard scenePhase == .active, model.phase == .idle, !startRequested else { return }
      start()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active {
        submission?.cancel()
        releaseCapture()
      }
    }
    .onChange(of: model.phase) { _, phase in
      if phase != .reviewing { transcriptFocused = false }
      switch phase {
      case .failed, .needsModel: releaseCapture(keepingMessage: true)
      default: break
      }
      guard automaticallySubmit else { return }
      if phase == .reviewing {
        if model.answer(for: model.question, usingSingleKanaInterpretation: true) != nil {
          checkAnswer()
        } else {
          repeatAnswer()
        }
      } else if model.shouldRepeat {
        repeatAnswer()
      }
    }
    .onDisappear {
      submission?.cancel()
      releaseCapture()
    }
  }

  @ViewBuilder private var captureControls: some View {
    switch model.phase {
    case .idle:
      Button("Start listening", systemImage: "mic.fill") { start() }
        .accessibilityIdentifier("voice.start")
    case .preparing, .downloading:
      ProgressView(
        model.phase == .downloading ? "Downloading speech model…" : "Preparing voice input…")
    case .needsModel:
      Text("Download the \(model.languageName) speech model to use voice answers on this device.")
      Button("Download model", systemImage: "arrow.down.circle") { start(downloadModel: true) }
    case .listening:
      HStack {
        Label("Listening in \(model.languageName)…", systemImage: "mic.fill")
          .accessibilityIdentifier("voice.listening")
        Spacer()
        Button("Finish answer", systemImage: "stop.fill") { model.stop() }
          .labelStyle(.iconOnly).accessibilityIdentifier("voice.stop")
      }
      Text(model.liveText.isEmpty ? "Speak, then pause to check your answer." : model.liveText)
        .foregroundStyle(.secondary).accessibilityIdentifier("voice.heard")
    case .finishing:
      ProgressView("Checking what was heard…")
    case .reviewing:
      if automaticallySubmit {
        Text(model.text).accessibilityValue(model.text).accessibilityIdentifier("voice.transcript")
        if !model.canSubmit {
          Text("I couldn’t get a clear kana reading. Say it again when listening resumes.")
            .font(.callout).foregroundStyle(.secondary)
        }
      } else if model.question.kind == .reading {
        StudyAnswerInput(
          prompt: "Your answer", text: $model.text, focused: $transcriptFocused,
          reading: true, automaticJapanese: automaticJapanese, editable: true,
          alphabet: .hiragana, submitted: { checkAnswer() }, retried: {},
          accessibilityIdentifier: "voice.transcript"
        ).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        if !model.readingSuggestions.isEmpty {
          Menu("Other interpretations", systemImage: "text.bubble") {
            ForEach(model.readingSuggestions, id: \.self) { suggestion in
              Button(suggestion) {
                model.text = suggestion
                transcriptFocused = false
              }
            }
          }.accessibilityIdentifier("voice.readings")
        }
      } else {
        TextField("Your answer", text: $model.text, axis: .vertical)
          .lineLimit(1...4).autocorrectionDisabled().accessibilityIdentifier("voice.transcript")
      }
      if model.needsKanaCorrection {
        Text("Use kana for the reading before submitting.").font(.callout).foregroundStyle(
          .secondary)
      }
      Button("Check answer", systemImage: "checkmark") { checkAnswer() }
        .disabled(!model.canSubmit).accessibilityIdentifier("voice.submit")
      Button("Try again", systemImage: "arrow.counterclockwise") { start() }
    case .failed(let message):
      Label(message, systemImage: "mic.slash").accessibilityIdentifier("voice.error")
      Button("Try again", systemImage: "arrow.counterclockwise") { start() }
    }
  }

  private func start(downloadModel: Bool = false) {
    submission?.cancel()
    submission = nil
    starting?.cancel()
    startRequested = true
    let cleanup = captureCleanup
    starting = Task {
      await cleanup?.value
      guard !Task.isCancelled, scenePhase == .active else { return }
      if audioLease == nil {
        guard let lease = audio.beginVoiceInput() else {
          captureBusy = true
          return
        }
        audioLease = lease
      }
      captureBusy = false
      model.start(downloadModel: downloadModel)
    }
  }

  @discardableResult private func releaseCapture(keepingMessage: Bool = false)
    -> Task<Void, Never>
  {
    starting?.cancel()
    starting = nil
    startRequested = true
    let cleanup = keepingMessage ? model.releaseCapture() : model.cancel()
    let lease = audioLease
    audioLease = nil
    let previous = captureCleanup
    let release = Task {
      await previous?.value
      await cleanup?.value
      if let lease { audio.endVoiceInput(lease) }
    }
    captureCleanup = release
    return release
  }

  private func checkAnswer() {
    guard !sending, let answer = model.answer(for: model.question) else { return }
    sending = true
    let cleanup = releaseCapture()
    submission = Task {
      defer { sending = false }
      await cleanup.value
      guard !Task.isCancelled, scenePhase == .active else { return }
      submit(answer)
    }
  }

  private func repeatAnswer() {
    submission?.cancel()
    submission = Task {
      do { try await Task.sleep(for: .seconds(3)) } catch { return }
      guard scenePhase == .active else { return }
      start()
    }
  }
}
