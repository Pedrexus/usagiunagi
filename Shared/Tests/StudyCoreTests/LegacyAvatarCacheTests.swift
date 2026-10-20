import Foundation
import Testing

@testable import StudyCore

struct LegacyAvatarCacheTests {
  @Test func invalidOrOversizedMatchingFilesCannotPopulateTheNativeCache() async throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let format = root.appending(path: "auto-42x42-aspectfit")
    try FileManager.default.createDirectory(at: format, withIntermediateDirectories: true)
    let file = format.appending(path: "https%3A%2F%2Favatar.example.test%2Ffred.png")
    let url = URL(string: "https://avatar.example.test/fred.png")!
    let cache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0, diskPath: nil)
    let importer = LegacyAvatarCache(directory: root, cache: cache)
    for data in [Data("corrupt".utf8), Data(repeating: 0, count: 5_000_001)] {
      try data.write(to: file)
      #expect(await importer.restore(url) == false)
      #expect(cache.cachedResponse(for: URLRequest(url: url)) == nil)
    }
  }

  private let png = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
  )!

  @Test func importsEscapedAvatarWithoutChangingItsSourceOrNewerNativeCache() async throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let format = root.appending(path: "shared/auto-42x42-aspectfit")
    try FileManager.default.createDirectory(at: format, withIntermediateDirectories: true)
    let old = format.appending(path: "https%3A%2F%2Favatar.example.test%2Ffred.png")
    try png.write(to: old)
    let url = URL(string: "https://avatar.example.test/fred.png")!
    let cache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0, diskPath: nil)
    let importer = LegacyAvatarCache(directory: root.appending(path: "shared"), cache: cache)
    #expect(await importer.restore(url))
    #expect(cache.cachedResponse(for: URLRequest(url: url))?.data == png)
    #expect(try Data(contentsOf: old) == png)
    let current = Data("newer native response".utf8)
    cache.storeCachedResponse(
      CachedURLResponse(
        response: URLResponse(
          url: url, mimeType: "image/png", expectedContentLength: current.count,
          textEncodingName: nil), data: current), for: URLRequest(url: url))
    #expect(await importer.restore(url) == false)
    #expect(cache.cachedResponse(for: URLRequest(url: url))?.data == current)
  }

  @Test func importsTheHistoricalLongKeyDigestAndSkipsCorruptCandidates() async throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let format = root.appending(path: "auto-80x80-aspectfit")
    try FileManager.default.createDirectory(at: format, withIntermediateDirectories: true)
    let name = "a059364712cb43ca4bc32f3ca1b94f4a.png"
    try png.write(to: format.appending(path: name))
    let corrupt = root.appending(path: "auto-42x42-aspectfit")
    try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
    try Data("not an image".utf8).write(to: corrupt.appending(path: name))
    let url = URL(
      string: "https://avatar.example.test/" + String(repeating: "x", count: 300) + ".png")!
    let cache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0, diskPath: nil)
    let importer = LegacyAvatarCache(directory: root, cache: cache)
    #expect(await importer.restore(url))
    #expect(cache.cachedResponse(for: URLRequest(url: url))?.data == png)
    let missing = URL(string: "https://avatar.example.test/other.png")!
    #expect(await importer.restore(missing) == false)
  }

  @Test func explicitClearCannotRaceWithImportOrTouchNeighboringStudyData() async throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let shared = root.appending(path: "shared")
    let format = shared.appending(path: "auto-42x42-aspectfit")
    try FileManager.default.createDirectory(at: format, withIntermediateDirectories: true)
    try png.write(to: format.appending(path: "https%3A%2F%2Favatar.example.test%2Ffred.png"))
    let neighbor = root.appending(path: "study.sqlite")
    try Data("untouched study data".utf8).write(to: neighbor)
    let url = URL(string: "https://avatar.example.test/fred.png")!
    let cache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0, diskPath: nil)
    let importer = LegacyAvatarCache(directory: shared, cache: cache)
    async let imported = importer.restore(url)
    async let cleared: Void = importer.clear()
    _ = try await (imported, cleared)
    #expect(cache.cachedResponse(for: URLRequest(url: url)) == nil)
    #expect(!FileManager.default.fileExists(atPath: shared.path))
    #expect(try String(contentsOf: neighbor, encoding: .utf8) == "untouched study data")
    try await importer.clear()
    #expect(await importer.restore(url) == false)
  }
}
