// Synthetic audio transport and cache; never replaces a user's downloaded audio.
#if DEBUG
  import Foundation
  import StudyCore
  import Synchronization
  import Observation
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
