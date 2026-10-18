import StudyCore
import SwiftUI

public enum OfflineAudioAction {
  case enabled(Bool)
  case cellular(Bool)
  case voice(Int64, Bool)
  case retry, delete
}

public struct OfflineAudioView: View {
  let enabled: Bool
  let cellular: Bool
  let selectedVoices: Set<Int64>
  let voices: [StudyVoiceActor]
  @Bindable var downloads: StudyAudioDownloads
  let action: (OfflineAudioAction) -> Void
  @State private var confirmingDeletion = false

  public init(
    enabled: Bool, cellular: Bool, selectedVoices: Set<Int64>, voices: [StudyVoiceActor],
    downloads: StudyAudioDownloads, action: @escaping (OfflineAudioAction) -> Void
  ) {
    self.enabled = enabled
    self.cellular = cellular
    self.selectedVoices = selectedVoices
    self.voices = voices
    self.downloads = downloads
    self.action = action
  }

  public var body: some View {
    Form {
      Section {
        Toggle(
          "Enable offline audio",
          isOn: Binding(
            get: { enabled },
            set: {
              action(.enabled($0))
              if !$0 { confirmingDeletion = true }
            })
        ).accessibilityIdentifier("offlineAudio.enabled")
        Toggle(
          "Download over cellular", isOn: Binding(get: { cellular }, set: { action(.cellular($0)) })
        )
        .disabled(!enabled).accessibilityIdentifier("offlineAudio.cellular")
      } footer: {
        Text(
          "Save pronunciation audio for your current level, earlier levels and the next level so it can play offline."
        )
      }
      Section("Voice actors") {
        if enabled && selectedVoices.isEmpty {
          Text("Choose at least one voice to download audio.").foregroundStyle(.secondary)
        }
        if voices.isEmpty {
          Text("Sync WaniKani to load the available voices.").foregroundStyle(.secondary)
        }
        ForEach(voices, id: \.id) { voice in
          Toggle(
            isOn: Binding(
              get: { selectedVoices.contains(voice.id) }, set: { action(.voice(voice.id, $0)) })
          ) {
            VStack(alignment: .leading, spacing: 4) {
              Text(voice.name)
              Text(
                [voice.description, voice.gender == 1 ? "Male" : voice.gender == 2 ? "Female" : ""]
                  .filter { !$0.isEmpty }.joined(separator: " · ")
              )
              .font(.caption).foregroundStyle(.secondary)
            }
          }.disabled(!enabled).accessibilityIdentifier("offlineAudio.voice.\(voice.id)")
        }
      }
      Section {
        if downloads.isDeleting {
          ProgressView("Deleting audio…")
        } else if enabled {
          switch downloads.status {
          case .preparing: ProgressView("Finding audio to download…")
          case .downloading:
            if let progress = downloads.progress {
              ProgressView(progress).accessibilityLabel("Audio download progress")
                .accessibilityIdentifier("offlineAudio.progress")
            }
          case .finished:
            Label(
              downloads.failedFiles == 0
                ? "Up to date" : "\(downloads.failedFiles) files could not be downloaded",
              systemImage: downloads.failedFiles == 0
                ? "checkmark.circle" : "exclamationmark.circle"
            )
            .accessibilityIdentifier("offlineAudio.status")
          case .idle, .cancelled: Text("Ready to download")
          }
          Button("Check for downloads", systemImage: "arrow.clockwise") { action(.retry) }
            .accessibilityIdentifier("offlineAudio.retry")
        } else {
          Label("Downloads disabled", systemImage: "pause.circle").accessibilityIdentifier(
            "offlineAudio.status")
        }
        LabeledContent(
          "Cache size",
          value: downloads.cachedBytes.map { $0.formatted(.byteCount(style: .file)) }
            ?? "Calculating…"
        )
        .accessibilityIdentifier("offlineAudio.cacheSize")
        if let error = downloads.error {
          Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier(
            "offlineAudio.error")
        }
        Button("Delete downloaded audio", systemImage: "trash", role: .destructive) {
          confirmingDeletion = true
        }
        .accessibilityIdentifier("offlineAudio.delete")
      } header: {
        Text("Status")
      } footer: {
        Text(
          "Saved audio remains available when downloads are disabled. Downloads may pause while the app is suspended."
        )
      }
    }.disabled(downloads.isDeleting)
      #if os(macOS)
        .formStyle(.grouped)
      #endif
      .navigationTitle("Offline Audio")
      .alert("Delete offline audio?", isPresented: $confirmingDeletion) {
        Button("Keep", role: .cancel) {}
        Button("Delete", role: .destructive) { action(.delete) }
      } message: {
        Text(
          "Free up space by deleting downloaded pronunciation audio. Downloads will be disabled. Your voice choices are kept, and you can download the audio again later."
        )
      }
  }
}
