import AVFoundation
import Foundation
import ImageIO
import Observation
import SwiftUI
import WatchKit

enum WatchReviewError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let text): text
    }
  }
}

/// Foreground capture; pauses discard local audio and the phone fences in-flight answers.
@MainActor @Observable final class WatchVoiceReview {
  private(set) var response: WatchReviewResponse?
  private(set) var running = false
  private(set) var status = "English meanings · Japanese readings"
  private(set) var listening = false
  private(set) var radicalImage: CGImage?
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var recorder: AVAudioRecorder?
  private var runID = UUID()

  func start() {
    guard !running else { return }
    runID = UUID()
    let id = runID
    let previous = operation
    running = true
    status = "Connecting to iPhone…"
    operation = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.runID == id {
          self.running = false
          self.listening = false
        }
      }
      do {
        await previous?.value
        try Task.checkCancellation()
        guard await AVAudioApplication.requestRecordPermission() else {
          throw WatchReviewError.message(
            "Allow microphone access in Watch Settings to review by voice.")
        }
        try Task.checkCancellation()
        var next = try await WatchHelper.sharedInstance.review(.init(action: .start, runID: id))
        while !Task.isCancelled, self.runID == id {
          self.response = next
          guard next.outcome != .unavailable else {
            throw WatchReviewError.message(next.feedback ?? "Open the app on your iPhone first.")
          }
          if next.outcome == .finished {
            self.status = "Reviews saved on iPhone. WaniKani sync continues there."
            WKInterfaceDevice.current().play(.success)
            return
          }
          guard next.outcome != .paused, next.prompt != nil, let revision = next.revision else {
            throw WatchReviewError.message("Review paused. Resume to reload it from your iPhone.")
          }
          self.status = next.feedback ?? "Get ready…"
          switch next.outcome {
          case .incorrect:
            WKInterfaceDevice.current().play(.failure)
            try await Task.sleep(for: .seconds(3))
            next = try await WatchHelper.sharedInstance.review(
              .init(action: .advance, runID: id, revision: revision))
            continue
          case .repeatAnswer:
            WKInterfaceDevice.current().play(.retry)
            try await Task.sleep(for: .seconds(3))
          case .correct:
            WKInterfaceDevice.current().play(.success)
            try await Task.sleep(for: .milliseconds(650))
          default: break
          }
          self.radicalImage = nil
          if let prompt = next.prompt, prompt.characters.isEmpty {
            guard let url = prompt.imageURL, url.scheme == "https" else {
              throw WatchReviewError.message(
                "This radical needs an image. Continue this review on your iPhone.")
            }
            self.status = "Loading radical…"
            let (bytes, response) = try await URLSession.shared.data(
              for: URLRequest(url: url, timeoutInterval: 10))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              bytes.count <= 256_000,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
              throw WatchReviewError.message(
                "The radical image couldn’t load. Resume or continue on your iPhone.")
            }
            self.radicalImage = image
          }
          try Task.checkCancellation()
          let bytes = try await self.recordAnswer(reading: next.prompt?.reading == true)
          self.status = bytes == nil ? "Waiting for your answer…" : "Checking on iPhone…"
          next = try await WatchHelper.sharedInstance.review(
            .init(
              action: bytes == nil ? .refresh : .answer, runID: id, revision: revision, audio: bytes
            ))
        }
      } catch {
        guard !Task.isCancelled, self.runID == id else { return }
        self.status = error.localizedDescription
        self.sendPause(id)
      }
    }
  }

  func pause() {
    operation?.cancel()
    recorder?.stop()
    listening = false
    running = false
    status = "Paused. Your review progress is saved on iPhone."
    sendPause(runID)
  }

  private func sendPause(_ id: UUID) {
    Task { _ = try? await WatchHelper.sharedInstance.review(.init(action: .pause, runID: id)) }
  }

  private func recordAnswer(reading: Bool) async throws -> Data? {
    let url = URL.temporaryDirectory.appending(path: "watch-answer-\(UUID()).m4a")
    let session = AVAudioSession.sharedInstance()
    let previous = (session.category, session.mode, session.categoryOptions)
    defer {
      recorder?.stop()
      recorder = nil
      listening = false
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      try? session.setCategory(previous.0, mode: previous.1, options: previous.2)
      try? FileManager.default.removeItem(at: url)
    }
    try session.setCategory(.record, mode: .measurement)
    try session.setActive(true)
    let recording = try AVAudioRecorder(
      url: url,
      settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 16_000,
      ])
    recorder = recording
    recording.isMeteringEnabled = true
    guard recording.record() else {
      throw WatchReviewError.message("The Watch microphone could not start. Resume to try again.")
    }
    listening = true
    status = reading ? "Listening in Japanese…" : "Listening in English…"
    let clock = ContinuousClock()
    let started = clock.now
    var lastSpeech: ContinuousClock.Instant?
    while true {
      try await Task.sleep(for: .milliseconds(100))
      guard recording.isRecording else {
        throw WatchReviewError.message("Recording was interrupted. Resume when you’re ready.")
      }
      recording.updateMeters()
      if recording.averagePower(forChannel: 0) > -42 { lastSpeech = clock.now }
      if let lastSpeech, lastSpeech.duration(to: clock.now) >= .milliseconds(1200) { break }
      let elapsed = started.duration(to: clock.now)
      if lastSpeech == nil, elapsed >= .seconds(10) {
        return nil
      }
      if elapsed >= .seconds(15) {
        throw WatchReviewError.message(
          "That answer was too long or the room is noisy. Resume and try a shorter answer.")
      }
    }
    recording.stop()
    listening = false
    try Task.checkCancellation()
    let data = try Data(contentsOf: url)
    guard !data.isEmpty, data.count <= WatchReviewRequest.maximumAudioBytes else {
      throw WatchReviewError.message("That answer was too long. Resume and try a shorter answer.")
    }
    return data
  }
}

struct WatchReviewView: View {
  @State private var model = WatchVoiceReview()
  @ScaledMetric(relativeTo: .largeTitle) private var questionSize = 42.0
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 12) {
          if !model.running {
            Button(
              model.response == nil ? "Start reviews" : "Resume reviews", systemImage: "mic.fill"
            ) { model.start() }
            .buttonStyle(.borderedProminent).tint(.pink)
          }
          if let value = model.response, let prompt = value.prompt {
            VStack(spacing: 6) {
              if !prompt.characters.isEmpty {
                Text(prompt.characters).font(.system(size: questionSize)).minimumScaleFactor(0.4)
                  .lineLimit(2)
              } else if let image = model.radicalImage {
                Image(decorative: image, scale: 1).resizable().scaledToFit().frame(height: 56)
              } else {
                ProgressView("Loading radical…")
              }
              Text(prompt.kind.capitalized + (prompt.reading ? " Reading" : " Meaning"))
                .font(.caption)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(subjectColor(prompt.kind), in: .rect(cornerRadius: 14))
            .foregroundStyle(.white)
            Text("\(value.completed) done · \(value.remaining) left")
              .font(.caption2).foregroundStyle(.secondary)
          } else if model.response?.outcome == .finished {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            Text("\(model.response?.correct ?? 0) / \(model.response?.completed ?? 0) correct")
              .font(.headline)
          } else {
            Text("Speak, then pause.").font(.headline)
            Text("Keep your iPhone nearby.").font(.caption2).foregroundStyle(.secondary)
          }
          if let heard = model.response?.heard, !heard.isEmpty {
            Text(heard).font(.footnote).foregroundStyle(.secondary)
          }
          Label(model.status, systemImage: model.listening ? "waveform" : "mic")
            .font(.footnote).accessibilityAddTraits(.updatesFrequently)
        }.padding(.horizontal, 8)
      }
      .navigationTitle("Reviews")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if model.running {
            Button("Pause reviews", systemImage: "pause.fill") { model.pause() }
          } else {
            NavigationLink {
              WatchSettingsView()
            } label: {
              Image(systemName: "gearshape")
            }.accessibilityLabel("Watch settings")
          }
        }
      }
    }
    .onChange(of: scenePhase) { _, phase in if phase != .active, model.running { model.pause() } }
    .onDisappear { if model.running { model.pause() } }
  }

  private func subjectColor(_ kind: String) -> Color {
    switch kind {
    case "radical": .cyan
    case "kanji": .pink
    default: .purple
    }
  }
}
