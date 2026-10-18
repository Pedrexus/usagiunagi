// Synthetic audio transport and cache; never replaces a user's downloaded audio.
#if DEBUG
  import Foundation
  import StudyCore
  import Synchronization
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
      voiceActorIds.sorted().filter { [1, 2].contains($0) }.map {
        (
          subjectId: 70 + $0, voiceActorId: $0, level: 24,
          url: "https://audio.example.test/\($0).mp3"
        )
      }
    }
  }

  private final class AudioFixtureProtocol: URLProtocol, @unchecked Sendable {
    private let work = Mutex((cancelled: false, task: Optional<Task<Void, Never>>.none))
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      if ProcessInfo.processInfo.arguments.contains("AudioHeldFixture") { return }
      let task = Task.detached { [weak self] in
        do {
          try await Task.sleep(for: .seconds(5))
          guard !Task.isCancelled, let self else { return }
          let failed = ProcessInfo.processInfo.arguments.contains("AudioFailedFixture")
          let data = Data("ID3-fixture".utf8)
          let response = HTTPURLResponse(
            url: request.url!, statusCode: failed ? 503 : 200, httpVersion: nil,
            headerFields: ["Content-Type": "audio/mpeg", "Content-Length": "\(data.count)"])!
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: data)
          client?.urlProtocolDidFinishLoading(self)
        } catch {}
      }
      work.withLock { if $0.cancelled { task.cancel() } else { $0.task = task } }
    }
    override func stopLoading() {
      work.withLock {
        $0.cancelled = true
        $0.task?.cancel()
        $0.task = nil
      }
    }
  }
#endif
