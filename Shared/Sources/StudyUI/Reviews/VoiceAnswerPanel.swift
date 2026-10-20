import StudyCore
import StudySpeech
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

/// Bind sheet presentation to its captured question so first presentation cannot be empty.
struct VoiceAnswerRequest: Identifiable {
  let question: StudyQuestion
  var id: StudyQuestion { question }
}

/// Shared native voice controls; hosts validate the captured question again before grading.
public struct VoiceAnswerPanel: View {
  @State private var model: VoiceReviewController
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("native.autoSwitchKeyboard") private var automaticJapanese = false
  @State private var transcriptFocused = false
  private let audio: StudyAudioLibrary?
  @State private var audioLease: UUID?
  private let submit: (String) -> Void
  private let cancel: () -> Void

  public init(
    model: VoiceReviewController, audio: StudyAudioLibrary? = nil,
    submit: @escaping (String) -> Void, cancel: @escaping () -> Void
  ) {
    _model = State(initialValue: model)
    self.audio = audio
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
          switch model.phase {
          case .idle:
            Button("Start listening", systemImage: "mic.fill") { model.start() }
              .accessibilityIdentifier("voice.start")
          case .preparing, .downloading:
            ProgressView(
              model.phase == .downloading ? "Downloading speech model…" : "Preparing voice input…")
          case .needsModel:
            Text(
              "Download the \(model.languageName) speech model to use voice answers on this device."
            )
            Button("Download model", systemImage: "arrow.down.circle") {
              model.start(downloadModel: true)
            }
          case .listening:
            Label("Listening…", systemImage: "mic.fill")
              .accessibilityIdentifier("voice.listening")
            Button("Stop listening", systemImage: "stop.fill") { model.stop() }
              .accessibilityIdentifier("voice.stop")
          case .finishing:
            ProgressView("Finishing transcription…")
          case .reviewing:
            if model.question.kind == .reading {
              StudyAnswerInput(
                prompt: "Your answer", text: $model.text, focused: $transcriptFocused,
                reading: true, automaticJapanese: automaticJapanese, editable: true,
                alphabet: .hiragana,
                submitted: { transcriptFocused = false }, retried: {},
                accessibilityIdentifier: "voice.transcript"
              ).frame(minHeight: 44)
              if !model.readingSuggestions.isEmpty {
                Menu("Other interpretations", systemImage: "text.bubble") {
                  ForEach(model.readingSuggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                      model.text = suggestion
                      transcriptFocused = false
                    }
                  }
                }
                .accessibilityIdentifier("voice.readings")
              }
            } else {
              TextField("Your answer", text: $model.text, axis: .vertical)
                .lineLimit(1...4)
                .autocorrectionDisabled()
                .accessibilityIdentifier("voice.transcript")
            }
            if model.needsKanaCorrection {
              Text("Use kana for the reading before submitting.")
                .font(.callout).foregroundStyle(.secondary)
            }
            Button("Check answer", systemImage: "checkmark") {
              if let answer = model.answer(for: model.question) {
                // A reviewable transcript follows capture completion; release before grading/autoplay.
                if let audioLease {
                  audio?.endVoiceInput(audioLease)
                  self.audioLease = nil
                }
                submit(answer)
              }
            }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("voice.submit")
            Button("Try again", systemImage: "arrow.counterclockwise") { model.start() }
          case .failed(let message):
            Label(message, systemImage: "mic.slash")
              .accessibilityIdentifier("voice.error")
            Button("Try again", systemImage: "arrow.counterclockwise") { model.start() }
          }
        } footer: {
          Text(
            "Audio is processed on your device and isn’t saved by the app. Speech models are downloaded from Apple when needed."
          )
        }
        Section {
          Button("Use keyboard", systemImage: "keyboard") {
            model.cancel()
            cancel()
          }
          .accessibilityIdentifier("voice.keyboard")
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
    .onChange(of: scenePhase) { _, phase in if phase == .background { model.cancel() } }
    .onChange(of: model.phase) { _, phase in
      if phase != .reviewing { transcriptFocused = false }
    }
    .onAppear {
      if audioLease == nil { audioLease = audio?.beginVoiceInput() }
      if model.phase == .idle { model.start() }
    }
    .onDisappear {
      let cleanup = model.cancel()
      if let audioLease {
        self.audioLease = nil
        Task {
          await cleanup?.value
          audio?.endVoiceInput(audioLease)
        }
      }
    }
  }
}
