import StudyCore
import StudySpeech
import SwiftUI

/// Bind sheet presentation to its captured question so first presentation cannot be empty.
struct VoiceAnswerRequest: Identifiable {
    let question: StudyQuestion
    var id: StudyQuestion { question }
}

/// Shared native voice controls; hosts validate the captured question again before grading.
public struct VoiceAnswerPanel: View {
    @State private var model: VoiceReviewController
    @Environment(\.scenePhase) private var scenePhase
    private let submit: (String) -> Void
    private let cancel: () -> Void

    public init(question: StudyQuestion, submit: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.init(model: VoiceReviewController(question: question), submit: submit, cancel: cancel)
    }

    public init(model: VoiceReviewController, submit: @escaping (String) -> Void, cancel: @escaping () -> Void) {
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
                    switch model.phase {
                    case .idle:
                        Button("Start listening", systemImage: "mic.fill") { model.start() }
                            .accessibilityIdentifier("voice.start")
                    case .preparing, .downloading:
                        ProgressView(model.phase == .downloading ? "Downloading speech model…" : "Preparing voice input…")
                    case .needsModel:
                        Text("Download the \(model.languageName) speech model to use voice answers on this device.")
                        Button("Download model", systemImage: "arrow.down.circle") { model.start(downloadModel: true) }
                    case .listening:
                        Label("Listening…", systemImage: "mic.fill")
                            .accessibilityIdentifier("voice.listening")
                        Button("Stop listening", systemImage: "stop.fill") { model.stop() }
                            .accessibilityIdentifier("voice.stop")
                    case .finishing:
                        ProgressView("Finishing transcription…")
                    case .reviewing:
                        TextField("Your answer", text: $model.text, axis: .vertical)
                            .lineLimit(1...4)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("voice.transcript")
                        if model.needsKanaCorrection {
                            Text("Speech recognition returned characters other than kana. Edit the reading into kana before submitting.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Button("Check answer", systemImage: "checkmark") {
                            if let answer = model.answer(for: model.question) { submit(answer) }
                        }
                        .disabled(!model.canSubmit)
                        .accessibilityIdentifier("voice.submit")
                        Button("Try again", systemImage: "arrow.counterclockwise") { model.start() }
                    case let .failed(message):
                        Label(message, systemImage: "mic.slash")
                            .accessibilityIdentifier("voice.error")
                        Button("Try again", systemImage: "arrow.counterclockwise") { model.start() }
                    }
                } footer: {
                    Text("Audio is processed on your device and isn’t saved by the app. Speech models are downloaded from Apple when needed.")
                }
                Section {
                    Button("Use keyboard", systemImage: "keyboard") { model.cancel(); cancel() }
                        .accessibilityIdentifier("voice.keyboard")
                }
            }
            .navigationTitle("Voice answer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel(); cancel() }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.cancel() } }
        .onDisappear { model.cancel() }
    }
}
