// Synthetic audio transport and cache; never replaces a user's downloaded audio.
#if DEBUG
  import Foundation
  import StudyCore
  import Synchronization
  import Observation
  #if os(iOS)
    import WaniKaniAPI

    extension Screenshotter {
      @nonobjc @MainActor static func audioFixture() -> StudyAudioDownloads? {
        guard isActive, ProcessInfo.processInfo.arguments.contains("AudioFlowFixture") else {
          return nil
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
          "audio-fixture-\(UUID())")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.arguments.contains("AudioCacheFixture") {
          try? Data("ID3-fixture".utf8).write(to: directory.appendingPathComponent("a71-1.mp3"))
        }
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        for key in ["offlineAudio", "offlineAudioCellular"] {
          arguments[key] = try? NSKeyedArchiver.archivedData(
            withRootObject: false, requiringSecureCoding: true)
        }
        arguments["offlineAudioVoiceActors"] = try? NSKeyedArchiver.archivedData(
          withRootObject: Set<Int64>(), requiringSecureCoding: true)
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AudioFixtureProtocol.self]
        return StudyAudioDownloads(directory: directory, configuration: configuration)
      }
    }

    final class AudioFixtureCachingClient: FakeLocalCachingClient {
      override func getVoiceActors() -> [TKMVoiceActor] {
        [Int64(1), 2].map {
          var voice = TKMVoiceActor()
          voice.id = $0
          voice.name = "Voice \($0) fixture"
          voice.description_p = "Tokyo accent"
          voice.gender = $0 == 1 ? .male : .female
          return voice
        }
      }
      override func getAudioUrls(levels: [Int], voiceActorIds: [Int64]) -> [AudioUrl] {
        let level = max(1, Int(getUserInfo()?.currentLevel ?? 1))
        return voiceActorIds.sorted().filter { [1, 2].contains($0) }.map {
          (
            subjectId: 70 + $0, voiceActorId: $0, level: level,
            url: "https://audio.example.test/\($0).mp3"
          )
        }
      }
    }

  #endif

  @MainActor @Observable final class SampleAudioPlayback: StudyAudioPlayback {
    private(set) var state = SubjectAudioState.idle
    private(set) var error: String?
    func play(url: URL, interruptBackgroundAudio: Bool) throws {
      if ProcessInfo.processInfo.arguments.contains("--audio-failure-fixture") {
        state = .idle
        error = "Synthetic pronunciation failure."
      } else {
        state =
          ProcessInfo.processInfo.arguments.contains("--audio-loading-fixture")
          ? .loading : .playing
        error = nil
      }
    }
    func stop() {
      state = .idle
      error = nil
    }
  }

  // Foundation invokes these mock callbacks outside MainActor.
  nonisolated final class AudioFixtureProtocol: URLProtocol, @unchecked Sendable {
    private let cancelled = Mutex(false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      let arguments = ProcessInfo.processInfo.arguments
      if arguments.contains("AudioHeldFixture") { return }
      DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
        guard let self, !self.cancelled.withLock({ $0 }) else { return }
        let failed = arguments.contains("AudioFailedFixture")
        let data = Data("ID3-fixture".utf8)
        let response = HTTPURLResponse(
          url: self.request.url!, statusCode: failed ? 503 : 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "audio/mpeg", "Content-Length": "\(data.count)"])!
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: data)
        self.client?.urlProtocolDidFinishLoading(self)
      }
    }
    override func stopLoading() { cancelled.withLock { $0 = true } }
  }
#endif
