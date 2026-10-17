import Foundation
import Testing

@testable import StudyCore

private let radicalSVG = Data(
  #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path d="M10 10L90 90" stroke="black"/></svg>"#
    .utf8)
private let radicalURL = URL(string: "https://cdn.wanikani.com/images/fixture.svg?version=1")!

private actor ImageTransport {
  var requests: [URLRequest] = []
  var data = radicalSVG
  var status = 200
  var type = "image/svg+xml"
  var redirect: URL?
  var offline = false
  private var suspended: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?
  var hold = false

  func configure(
    data: Data = radicalSVG, status: Int = 200, type: String = "image/svg+xml",
    redirect: URL? = nil, offline: Bool = false, hold: Bool = false
  ) {
    self.data = data
    self.status = status
    self.type = type
    self.redirect = redirect
    self.offline = offline
    self.hold = hold
  }
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    if hold {
      await withCheckedContinuation { continuation in
        suspended = continuation
        started?.resume()
        started = nil
      }
    }
    if offline { throw URLError(.notConnectedToInternet) }
    let url = try #require(redirect ?? request.url)
    return (
      data,
      try #require(
        HTTPURLResponse(
          url: url, statusCode: status,
          httpVersion: nil, headerFields: ["Content-Type": type]))
    )
  }
  func waitForRequest() async {
    if suspended == nil { await withCheckedContinuation { started = $0 } }
  }
  func release() {
    hold = false
    suspended?.resume()
    suspended = nil
  }
}

struct RadicalImageCacheTests {
  private func directory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "radical-tests-\(UUID())")
  }

  @Test func cachedImagesSurviveReopenWithoutNetworkAndVersionsStaySeparate() async throws {
    let directory = directory()
    let transport = ImageTransport()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = RadicalImageCache(directory: directory) { try await transport.send($0) }
    #expect(try await cache.image(at: radicalURL) == radicalSVG)
    let request = try #require(await transport.requests.first)
    #expect(request.value(forHTTPHeaderField: "Accept") == "image/svg+xml")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    await transport.configure(offline: true)
    let reopened = RadicalImageCache(directory: directory) { try await transport.send($0) }
    #expect(try await reopened.image(at: radicalURL) == radicalSVG)
    #expect(await transport.requests.count == 1)
    let nextVersion = try #require(
      URL(string: "https://cdn.wanikani.com/images/fixture.svg?version=2"))
    await #expect(throws: URLError.self) { try await reopened.image(at: nextVersion) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
    #expect(try await reopened.image(at: radicalURL) == radicalSVG)
  }

  @Test func cancelledSceneDoesNotCancelSharedDownloadOrPoisonOfflineCache() async throws {
    let directory = directory()
    let transport = ImageTransport()
    defer { try? FileManager.default.removeItem(at: directory) }
    await transport.configure(hold: true)
    let cache = RadicalImageCache(directory: directory) { try await transport.send($0) }
    let first = Task { try await cache.image(at: radicalURL) }
    await transport.waitForRequest()
    let second = Task { try await cache.image(at: radicalURL) }
    first.cancel()
    await transport.release()
    #expect(try await first.value == radicalSVG)
    #expect(try await second.value == radicalSVG)
    #expect(await transport.requests.count == 1)
    await transport.configure(offline: true)
    #expect(try await cache.image(at: radicalURL) == radicalSVG)
  }

  @Test(arguments: [
    "http://cdn.wanikani.com/image.svg", "https://example.com/image.svg",
    "https://cdn.wanikani.com.evil.example/image.svg", "https://user@cdn.wanikani.com/image.svg",
    "https://cdn.wanikani.com:444/image.svg", "https://cdn.wanikani.com/image.png",
  ])
  func invalidAddressNeverReachesTransport(address: String) async throws {
    let transport = ImageTransport()
    let cache = RadicalImageCache(directory: directory()) { try await transport.send($0) }
    let url = try #require(URL(string: address))
    await #expect(throws: RadicalImageError.self) { try await cache.image(at: url) }
    #expect(await transport.requests.isEmpty)
  }

  @Test(arguments: [
    "html", "malformed", "empty", "entity", "oversized", "status", "type", "redirect",
  ])
  func invalidResponseIsNeverPublishedAndRetryCanRecover(fault: String) async throws {
    let directory = directory()
    let transport = ImageTransport()
    defer { try? FileManager.default.removeItem(at: directory) }
    switch fault {
    case "html": await transport.configure(data: Data("<html>Unavailable</html>".utf8))
    case "malformed":
      await transport.configure(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg"><path>"#.utf8))
    case "empty":
      await transport.configure(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8))
    case "entity":
      await transport.configure(
        data: Data(
          #"<!DOCTYPE svg [<!ENTITY name "answer">]><svg xmlns="http://www.w3.org/2000/svg"><text>&name;</text></svg>"#
            .utf8))
    case "oversized":
      await transport.configure(
        data: Data(repeating: 32, count: RadicalImageCache.maximumBytes + 1))
    case "status": await transport.configure(status: 503)
    case "type": await transport.configure(type: "text/html")
    case "redirect":
      await transport.configure(redirect: URL(string: "https://example.com/image.svg"))
    default: Issue.record("Unknown fixture")
    }
    let cache = RadicalImageCache(directory: directory) { try await transport.send($0) }
    await #expect(throws: RadicalImageError.self) { try await cache.image(at: radicalURL) }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    await transport.configure()
    #expect(try await cache.image(at: radicalURL) == radicalSVG)
    #expect(await transport.requests.count == 2)
  }

  @Test func corruptDiskEntryIsReplacedOnlyAfterSuccessfulDownload() async throws {
    let directory = directory()
    let transport = ImageTransport()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = RadicalImageCache(directory: directory) { try await transport.send($0) }
    _ = try await cache.image(at: radicalURL)
    let path = try #require(
      FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    let corrupt = Data("interrupted".utf8)
    try corrupt.write(to: path)
    await transport.configure(offline: true)
    await #expect(throws: URLError.self) { try await cache.image(at: radicalURL) }
    #expect(try Data(contentsOf: path) == corrupt)
    await transport.configure()
    #expect(try await cache.image(at: radicalURL) == radicalSVG)
    #expect(try Data(contentsOf: path) == radicalSVG)
  }
}
