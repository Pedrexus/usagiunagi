import Foundation
import Synchronization
import Testing

@testable import StudyCore
@testable import Tsurukame

@MainActor struct StudyAudioDownloadsTests {
  private func withDownloads(_ body: (StudyAudioDownloads, AudioDownloadStub) async throws -> Void)
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "audio-test-\(UUID())")
    let stub = AudioDownloadStub()
    let downloads = StudyAudioDownloads(directory: directory, configuration: stub.configuration)
    defer {
      downloads.cancel()
      stub.remove()
      try? FileManager.default.removeItem(at: directory)
    }
    try await body(downloads, stub)
  }
  private func asset(_ id: Int64, level: Int = 1) -> StudyAudioReference {
    .init(subjectID: id, voiceActorID: 9, level: level, url: "https://audio.example.test/\(id).mp3")
  }
  private func wait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
  }

  @Test func downloadsInOrderDeduplicatesAndReopensWithoutNetwork() async throws {
    try await withDownloads { downloads, stub in
      stub.update { $0.type = "Audio/MPEG" }
      let first = asset(70)
      let second = asset(80, level: 2)
      downloads.start([first, second, first], allowsCellular: false)
      try await wait { downloads.status == .finished && downloads.cachedBytes != nil }
      #expect(downloads.failedFiles == 0)
      #expect(downloads.error == nil)
      #expect(stub.state.requests == ["70.mp3", "80.mp3"])
      #expect(downloads.progress?.fractionCompleted == 1)
      let file = downloads.cacheURL(subjectID: 70, voiceActorID: 9)
      #expect(file.lastPathComponent == "a70-9.mp3")
      #expect(try Data(contentsOf: file) == stub.state.data)
      #expect((downloads.cachedBytes ?? 0) > 0)
      stub.update { $0.hold = true }
      let reopened = StudyAudioDownloads(
        directory: downloads.directory, configuration: stub.configuration)
      reopened.start([first, second], allowsCellular: false)
      try await wait { reopened.status == .finished && reopened.cachedBytes != nil }
      #expect(reopened.isCached(subjectID: 80, voiceActorID: 9))
      #expect(stub.state.requests.count == 2)
    }
  }

  @Test(arguments: [0, 1, 2]) func rejectsFailedResponsesAndCanRetry(_ scenario: Int) async throws {
    try await withDownloads { downloads, stub in
      stub.update {
        if scenario == 0 { $0.status = 503 }
        if scenario == 1 { $0.type = "text/html" }
        if scenario == 2 { $0.data = Data() }
      }
      downloads.start([asset(70)], allowsCellular: true)
      try await wait { downloads.status == .finished }
      #expect(downloads.failedFiles == 1)
      #expect(downloads.error != nil)
      #expect(!downloads.isCached(subjectID: 70, voiceActorID: 9))
      stub.update {
        $0.status = 200
        $0.type = "audio/mpeg"
        $0.data = Data("ID3-fixture".utf8)
      }
      downloads.start([asset(70)], allowsCellular: true)
      try await wait { downloads.status == .finished }
      #expect(downloads.failedFiles == 0)
      #expect(downloads.error == nil)
      #expect(downloads.isCached(subjectID: 70, voiceActorID: 9))
    }
  }

  @Test(arguments: [false, true]) func cancellationAndDeletionStopActiveTransfers(_ delete: Bool)
    async throws
  {
    try await withDownloads { downloads, stub in
      stub.update { $0.hold = true }
      downloads.start([asset(70)], allowsCellular: false)
      try await wait { stub.state.requests.count == 1 }
      if delete { await downloads.deleteAll() } else { downloads.cancel() }
      try await wait { stub.state.stopped > 0 }
      #expect(!downloads.isCached(subjectID: 70, voiceActorID: 9))
      #expect(downloads.error == nil)
      #expect(downloads.status == (delete ? .idle : .cancelled))
      if delete { #expect(downloads.cachedBytes == 0) }
      stub.update { $0.hold = false }
      downloads.start([asset(80)], allowsCellular: false)
      try await wait { downloads.status == .finished }
      #expect(downloads.isCached(subjectID: 80, voiceActorID: 9))
      #expect(!downloads.isCached(subjectID: 70, voiceActorID: 9))
    }
  }

  @Test func replacementBatchCannotPublishCancelledResults() async throws {
    try await withDownloads { downloads, stub in
      stub.update { $0.hold = true }
      downloads.start([asset(70)], allowsCellular: false)
      try await wait { stub.state.requests.count == 1 }
      stub.update { $0.hold = false }
      downloads.start([asset(80)], allowsCellular: true)
      try await wait { downloads.status == .finished && stub.state.stopped > 0 }
      #expect(downloads.failedFiles == 0)
      #expect(downloads.error == nil)
      #expect(downloads.progress?.fractionCompleted == 1)
      #expect(!downloads.isCached(subjectID: 70, voiceActorID: 9))
      #expect(downloads.isCached(subjectID: 80, voiceActorID: 9))
      await downloads.deleteAll()
      #expect(!downloads.isCached(subjectID: 80, voiceActorID: 9))
    }
  }

  @Test func rejectsInsecureAddressesBeforeRequesting() async throws {
    try await withDownloads { downloads, stub in
      let invalid = [
        "http://audio.example.test/70.mp3", "https://user:password@audio.example.test/70.mp3",
      ]
      .enumerated().map {
        StudyAudioReference(subjectID: Int64($0.offset), voiceActorID: 9, level: 1, url: $0.element)
      }
      downloads.start(invalid, allowsCellular: true)
      try await wait { downloads.status == .finished }
      #expect(stub.state.requests.isEmpty)
      #expect(downloads.failedFiles == 2)
    }
  }

  @Test func bulkTransfersAreBoundedAndAllActiveRequestsCancel() async throws {
    try await withDownloads { downloads, stub in
      stub.update { $0.hold = true }
      downloads.start((1...12).map { asset(Int64($0)) }, allowsCellular: false)
      try await wait { stub.state.requests.count == 4 }
      try await Task.sleep(for: .milliseconds(25))
      #expect(stub.state.requests.count == 4)
      downloads.cancel()
      try await wait { stub.state.stopped == 4 }
      #expect(downloads.failedFiles == 0)
    }
  }

  @Test func emptyLegacyFileIsReplacedOnlyByValidAudio() async throws {
    try await withDownloads { downloads, stub in
      try FileManager.default.createDirectory(
        at: downloads.directory, withIntermediateDirectories: true)
      let destination = downloads.cacheURL(subjectID: 70, voiceActorID: 9)
      try Data().write(to: destination)
      #expect(!downloads.isCached(subjectID: 70, voiceActorID: 9))
      stub.update { $0.status = 503 }
      downloads.start([asset(70)], allowsCellular: false)
      try await wait { downloads.status == .finished }
      #expect(try Data(contentsOf: destination).isEmpty)
      stub.update { $0.status = 200 }
      downloads.start([asset(70)], allowsCellular: false)
      try await wait { downloads.status == .finished }
      #expect(try Data(contentsOf: destination) == stub.state.data)
      #expect(downloads.isCached(subjectID: 70, voiceActorID: 9))
    }
  }
}

struct AudioDownloadStub: Sendable {
  struct State: Sendable {
    var data = Data("ID3-fixture".utf8)
    var status = 200
    var type = "audio/mpeg"
    var hold = false
    var requests: [String] = []
    var stopped = 0
  }
  static let states = Mutex<[String: State]>([:])
  let id = UUID().uuidString
  init() { Self.states.withLock { $0[id] = State() } }
  var state: State { Self.states.withLock { $0[id]! } }
  func update(_ change: (inout State) -> Void) { Self.states.withLock { change(&$0[id]!) } }
  func remove() { Self.states.withLock { $0[id] = nil } }
  var configuration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AudioDownloadProtocol.self]
    configuration.httpAdditionalHeaders = ["X-Audio-Test": id]
    return configuration
  }
}

private final class AudioDownloadProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let id = request.value(forHTTPHeaderField: "X-Audio-Test"),
      let state = AudioDownloadStub.states.withLock({ values -> AudioDownloadStub.State? in
        values[id]?.requests.append(request.url!.lastPathComponent)
        return values[id]
      })
    else { return }
    if state.hold { return }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: state.status, httpVersion: nil,
      headerFields: ["Content-Type": state.type, "Content-Length": "\(state.data.count)"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: state.data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {
    if let id = request.value(forHTTPHeaderField: "X-Audio-Test") {
      AudioDownloadStub.states.withLock { $0[id]?.stopped += 1 }
    }
  }
}
