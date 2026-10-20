import Foundation
import Testing

@testable import StudyCore

private enum AvatarFailure: CaseIterable {
  case offline, status, corrupt, oversized
}

private actor AvatarTransport {
  private let png: Data
  private var data: Data
  private var status = 200
  private var offline = false
  private var noStore = false
  private var hold = false
  private var pending: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?
  private(set) var requests: [URLRequest] = []

  init(png: Data) {
    self.png = png
    data = png
  }
  func configure(failure: AvatarFailure? = nil, noStore: Bool = false, hold: Bool = false) {
    data =
      failure == .corrupt
      ? Data("invalid avatar".utf8)
      : failure == .oversized ? Data(repeating: 0, count: 5_000_001) : png
    status = failure == .status ? 503 : 200
    offline = failure == .offline
    self.noStore = noStore
    self.hold = hold
  }
  func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
    requests.append(request)
    if hold {
      await withCheckedContinuation { continuation in
        pending = continuation
        started?.resume()
        started = nil
      }
    }
    if offline { throw URLError(.notConnectedToInternet) }
    let url = try #require(request.url)
    var headers = ["Content-Type": "image/png"]
    if noStore { headers["Cache-Control"] = "no-store" }
    return (
      data,
      try #require(
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    )
  }
  func waitForRequest() async {
    if pending != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func finish() {
    hold = false
    pending?.resume()
    pending = nil
  }
}

struct StudyAvatarLoadingTests {
  private let png = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO9WlVQAAAAASUVORK5CYII="
  )!

  @Test(arguments: ["", "custom@example.invalid"])
  func injectedTransportLoadsDefaultAndCustomEmailWithoutASeparateNetworkPath(email: String)
    async throws
  {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let responses = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
    let transport = AvatarTransport(png: png)
    let cache = LegacyAvatarCache(directory: root, cache: responses) {
      try await transport.send($0)
    }
    let url = StudyAvatar.url(email: email, pixelSize: 160)
    let image = try await cache.image(at: url)
    #expect(image.width == 1 && image.height == 1)
    #expect(responses.cachedResponse(for: URLRequest(url: url))?.data == png)
    let request = try #require(await transport.requests.first)
    #expect(request.url == url)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    _ = try await cache.image(at: url)
    #expect(await transport.requests.count == 1)
  }

  @Test func legacyAvatarLoadsThroughTheSameCacheWithoutTransport() async throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let format = root.appending(path: "auto-42x42-aspectfit")
    try FileManager.default.createDirectory(at: format, withIntermediateDirectories: true)
    let file = format.appending(path: "https%3A%2F%2Favatar.example.test%2Ffred.png")
    try png.write(to: file)
    let url = try #require(URL(string: "https://avatar.example.test/fred.png"))
    let transport = AvatarTransport(png: png)
    await transport.configure(failure: .offline)
    let cache = LegacyAvatarCache(
      directory: root, cache: URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
    ) { try await transport.send($0) }
    let image = try await cache.image(at: url)
    #expect(image.width == 1 && image.height == 1)
    #expect(await transport.requests.isEmpty)
    #expect(try Data(contentsOf: file) == png)
  }

  @Test(arguments: AvatarFailure.allCases)
  private func rejectedOrOfflineResponseIsNotCachedAndCanRetry(failure: AvatarFailure)
    async throws
  {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let responses = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
    let transport = AvatarTransport(png: png)
    await transport.configure(failure: failure)
    let cache = LegacyAvatarCache(directory: root, cache: responses) {
      try await transport.send($0)
    }
    let url = StudyAvatar.defaultURL
    await #expect(throws: URLError.self) { _ = try await cache.image(at: url) }
    #expect(responses.cachedResponse(for: URLRequest(url: url)) == nil)
    await transport.configure()
    _ = try await cache.image(at: url)
    #expect(responses.cachedResponse(for: URLRequest(url: url))?.data == png)
    #expect(await transport.requests.count == 2)
  }

  @Test func noStoreResponseCanDisplayWithoutRetainingItsBytes() async throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let responses = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
    let transport = AvatarTransport(png: png)
    await transport.configure(noStore: true)
    let cache = LegacyAvatarCache(directory: root, cache: responses) {
      try await transport.send($0)
    }
    let url = StudyAvatar.defaultURL
    let image = try await cache.image(at: url)
    #expect(image.width == 1 && image.height == 1)
    #expect(responses.cachedResponse(for: URLRequest(url: url)) == nil)
    _ = try await cache.image(at: url)
    #expect(await transport.requests.count == 2)
  }

  @Test func clearRejectsAnInFlightImageAndOnlyANewRequestCanRepopulateTheCache() async throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let responses = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
    let transport = AvatarTransport(png: png)
    await transport.configure(hold: true)
    let cache = LegacyAvatarCache(directory: root, cache: responses) {
      try await transport.send($0)
    }
    let url = StudyAvatar.defaultURL
    let load = Task { try await cache.image(at: url) }
    await transport.waitForRequest()
    try await cache.clear()
    await transport.finish()
    await #expect(throws: CancellationError.self) { _ = try await load.value }
    #expect(responses.cachedResponse(for: URLRequest(url: url)) == nil)
    _ = try await cache.image(at: url)
    #expect(responses.cachedResponse(for: URLRequest(url: url))?.data == png)
    #expect(await transport.requests.count == 2)
  }

  @Test func cancelledLoadCannotReturnAnOldImageOrRepopulateTheCache() async throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let responses = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
    let transport = AvatarTransport(png: png)
    await transport.configure(hold: true)
    let cache = LegacyAvatarCache(directory: root, cache: responses) {
      try await transport.send($0)
    }
    let url = StudyAvatar.defaultURL
    let load = Task { try await cache.image(at: url) }
    await transport.waitForRequest()
    load.cancel()
    await transport.finish()
    await #expect(throws: CancellationError.self) { _ = try await load.value }
    #expect(responses.cachedResponse(for: URLRequest(url: url)) == nil)
  }
}
