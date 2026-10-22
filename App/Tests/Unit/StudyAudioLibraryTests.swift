import Foundation
import Observation
import StudyCore
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor struct StudyAudioLibraryTests {
  private func subject(
    _ urls: [String] = ["https://audio.example.test/1.mp3", "https://audio.example.test/2.mp3"]
  ) -> CatalogSubject {
    var value = CatalogSubject(id: 3, kind: .vocabulary)
    value.audio = urls.enumerated().map {
      .init(url: $0.element, voiceActorID: Int64($0.offset + 1))
    }
    return value
  }
  private func catalog(_ account: String = "a") -> StudyAudioCatalog {
    StudyAudioCatalog(
      accountID: account, currentLevel: 2, maximumLevel: 3,
      voices: [1, 2].map { StudyVoiceActor(id: $0) },
      audio: [1, 2, 3, 4].map {
        .init(
          subjectID: Int64($0), voiceActorID: 1, level: $0,
          url: "https://audio.example.test/\($0).mp3")
      })
  }
  private func wait(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !predicate(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(predicate())
  }
  private func withLibrary(
    _ body:
      @MainActor (
        StudyAudioLibrary, AudioPreferencesFixture, AudioPlaybackFixture, AudioDownloadStub
      ) async throws -> Void
  ) async throws {
    let stub = AudioDownloadStub()
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    let preferences = AudioPreferencesFixture()
    let playback = AudioPlaybackFixture()
    let library = StudyAudioLibrary(
      downloads: StudyAudioDownloads(directory: root, configuration: stub.configuration),
      preferences: preferences, playback: playback)
    defer {
      library.updateCatalog(nil)
      stub.remove()
      try? FileManager.default.removeItem(at: root)
    }
    try await body(library, preferences, playback, stub)
  }
  @Test func playbackPrefersAnyCachedVoiceAndPreservesTheLegacyFileNames() async throws {
    try await withLibrary { library, _, playback, _ in
      try FileManager.default.createDirectory(
        at: library.downloads.directory, withIntermediateDirectories: true)
      let file = library.downloads.cacheURL(subjectID: 3, voiceActorID: 1)
      try Data("ID3-fixture".utf8).write(to: file)
      library.play(subject: subject(), interruptBackgroundAudio: true)
      #expect(playback.urls == [file] && file.lastPathComponent == "a3-1.mp3")
      #expect(playback.interrupts == [true] && library.state(for: 3) == .playing)
      #expect(library.state(for: 9) == .idle)
      library.toggle(subject: subject())
      #expect(library.state == .idle && library.subjectID == nil)
      try Data().write(to: file)
      library.play(subject: subject())
      #expect(playback.urls.last?.scheme == "https")
      library.stop()
    }
  }
  @Test(arguments: [
    "http://audio.example.test/a.mp3", "file:///private/tmp/a.mp3",
    "https://user:secret@audio.example.test/a.mp3", "not a URL",
  ])
  func unsafeCatalogURLsDoNotReachThePlayer(_ url: String) async throws {
    try await withLibrary { library, _, playback, _ in
      library.play(subject: subject([url]))
      #expect(playback.urls.isEmpty && library.error != nil)
      library.play(subject: subject(["https://audio.example.test/good.mp3"]))
      #expect(playback.urls.count == 1 && library.error == nil)
    }
  }
  @Test func audioPriorityAndVoiceSelectionRespectSubscriptionLimits() {
    let value = catalog()
    #expect(value.downloads(for: [1]).map(\.level) == [2, 1, 3])
    #expect(value.downloads(for: [2, 99]).isEmpty)
    let capped = StudyAudioCatalog(
      accountID: "a", currentLevel: 9, maximumLevel: 1, voices: value.voices, audio: value.audio)
    #expect(capped.downloads(for: [1]).map(\.level) == [1])
  }
  @Test func downloadsSurviveReopeningAndUnchangedCatalogDoesNotRestartThem() async throws {
    try await withLibrary { library, preferences, _, stub in
      library.updateCatalog(catalog())
      library.send(.enabled(true))
      #expect(preferences.options.enabled && preferences.options.voiceIDs == [1, 2])
      try await wait { library.downloads.status == .finished }
      #expect(stub.state.requests == ["2.mp3", "1.mp3", "3.mp3"])
      let progress = library.downloads.progress
      library.updateCatalog(catalog())
      #expect(library.downloads.progress === progress)
      library.send(.voice(2, false))
      library.send(.cellular(true))
      #expect(preferences.options.voiceIDs == [1] && preferences.options.cellular)
      try await wait { library.downloads.status == .finished }
      #expect(stub.state.requests.count == 3)
    }
  }
  @Test func accountHandoffCancelsLoadingAndKeepsTheDownloadedFiles() async throws {
    try await withLibrary { library, preferences, playback, stub in
      library.play(subject: subject())
      library.updateCatalog(nil)
      #expect(library.state == .idle && library.subjectID == nil)
      stub.update { $0.hold = true }
      library.updateCatalog(catalog())
      library.send(.enabled(true))
      try await wait { !stub.state.requests.isEmpty }
      library.play(subject: subject())
      playback.state = .loading
      library.updateCatalog(nil)
      try await wait { stub.state.stopped > 0 }
      #expect(library.state == .idle && library.voices.isEmpty && preferences.options.enabled)
      #expect(library.downloads.status == .cancelled)
      library.updateCatalog(catalog("b"))
      #expect(library.catalog?.accountID == "b")
    }
  }
  @Test func deletionDisablesDownloadsButRetainsVoicePreferences() async throws {
    try await withLibrary { library, preferences, _, _ in
      library.updateCatalog(catalog())
      library.send(.enabled(true))
      try await wait { library.downloads.status == .finished }
      library.play(subject: subject())
      library.send(.delete)
      try await wait { library.downloads.status == .idle }
      #expect(!preferences.options.enabled && preferences.options.voiceIDs == [1, 2])
      #expect(
        library.state == .idle
          && !FileManager.default.fileExists(atPath: library.downloads.directory.path))
    }
  }
  @Test func failedPlaybackCanBeRetriedAndLoadingCanBeCancelled() async throws {
    try await withLibrary { library, _, playback, _ in
      playback.shouldFail = true
      library.play(subject: subject())
      #expect(library.error(for: 3) != nil && library.error(for: 4) == nil)
      playback.shouldFail = false
      library.toggle(subject: subject())
      #expect(library.error == nil && library.state == .playing)
      playback.state = .loading
      library.toggle(subject: subject())
      #expect(library.state == .idle)
    }
  }
  @Test func voiceOwnershipRejectsAnotherCaptureUntilTheCurrentOwnerReleasesIt() async throws {
    try await withLibrary { library, _, playback, _ in
      library.play(subject: subject())
      let first = try #require(library.beginVoiceInput())
      #expect(library.beginVoiceInput() == nil)
      #expect(library.state == .idle && library.voiceInputActive)
      let count = playback.urls.count
      library.play(subject: subject())
      #expect(playback.urls.count == count && library.error != nil)
      library.endVoiceInput(UUID())
      #expect(library.voiceInputActive)
      library.endVoiceInput(first)
      #expect(!library.voiceInputActive && library.error == nil)
      let second = try #require(library.beginVoiceInput())
      library.endVoiceInput(first)
      #expect(library.voiceInputActive)
      library.endVoiceInput(second)
      #expect(!library.voiceInputActive && library.error == nil)
      library.play(subject: subject())
      #expect(playback.urls.count == count + 1)
    }
  }
  @Test func nativePreferencesKeepOtherKeysAndReloadExternalChanges() throws {
    let name = "audio-options-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("keep", forKey: "other")
    let preferences = DefaultsStudyAudioPreferences(defaults: defaults)
    var value = StudyAudioOptions()
    value.enabled = true
    value.voiceIDs = [2, 9]
    preferences.options = value
    let reopened = DefaultsStudyAudioPreferences(defaults: defaults)
    #expect(reopened.options == value && defaults.string(forKey: "other") == "keep")
  }
}

@MainActor private final class AudioPreferencesFixture: StudyAudioPreferences {
  var options = StudyAudioOptions()
}
@MainActor @Observable private final class AudioPlaybackFixture: StudyAudioPlayback {
  var state = SubjectAudioState.idle
  var error: String?
  var urls: [URL] = []
  var interrupts: [Bool] = []
  var shouldFail = false
  func play(url: URL, interruptBackgroundAudio: Bool) throws {
    urls.append(url)
    interrupts.append(interruptBackgroundAudio)
    error = shouldFail ? "Fixture failed" : nil
    state = shouldFail ? .idle : .playing
  }
  func stop() {
    state = .idle
    error = nil
  }
}
