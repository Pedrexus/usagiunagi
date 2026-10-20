import CryptoKit
import Foundation
import ImageIO

/// Loads public avatars and imports the former Haneke cache without its Objective-C dependency.
public actor LegacyAvatarCache {
  public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
  private let directory: URL
  private let cache: URLCache
  private let transport: Transport
  private var generation = UUID()
  public init(
    directory: URL, cache: URLCache = .shared,
    transport: @escaping Transport = LegacyAvatarCache.download
  ) {
    self.directory = directory
    self.cache = cache
    self.transport = transport
  }

  public func image(at url: URL) async throws -> CGImage {
    try Task.checkCancellation()
    restore(url)
    let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
    if let cached = cache.cachedResponse(for: request), let decoded = Self.decode(cached.data) {
      return decoded.image
    }
    let generation = generation
    let (data, response) = try await transport(request)
    try Task.checkCancellation()
    guard self.generation == generation else { throw CancellationError() }
    guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode)
    else { throw URLError(.badServerResponse) }
    guard let decoded = Self.decode(data) else { throw URLError(.cannotDecodeContentData) }
    if response.value(forHTTPHeaderField: "Cache-Control")?.localizedCaseInsensitiveContains(
      "no-store") != true
    {
      cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
    }
    return decoded.image
  }

  @discardableResult public func restore(_ url: URL) -> Bool {
    let request = URLRequest(url: url)
    guard cache.cachedResponse(for: request) == nil else { return false }
    let digest = Insecure.MD5.hash(data: Data(url.absoluteString.utf8)).map {
      String(format: "%02x", $0)
    }.joined()
    let manager = FileManager.default
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
    let formats =
      (try? manager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    let files: [URL] = formats.flatMap { format in
      (try? manager.contentsOfDirectory(
        at: format, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)) ?? []
    }
    let matches = files.filter { file in
      file.lastPathComponent.removingPercentEncoding == url.absoluteString
        || file.deletingPathExtension().lastPathComponent == digest
    }
    let candidates = matches.sorted { left, right in
      let leftDate =
        (try? left.resourceValues(forKeys: keys).contentModificationDate) ?? Date.distantPast
      let rightDate =
        (try? right.resourceValues(forKeys: keys).contentModificationDate) ?? Date.distantPast
      return leftDate > rightDate
    }
    for file in candidates {
      guard !Task.isCancelled,
        let metadata = try? file.resourceValues(forKeys: keys), metadata.isRegularFile == true,
        let size = metadata.fileSize, (1...5_000_000).contains(size),
        let data = try? Data(contentsOf: file), data.count <= 5_000_000,
        let decoded = Self.decode(data), ["public.png", "public.jpeg"].contains(decoded.type),
        let response = HTTPURLResponse(
          url: url, statusCode: 200, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": decoded.type == "public.png" ? "image/png" : "image/jpeg"])
      else { continue }
      guard !Task.isCancelled, cache.cachedResponse(for: request) == nil else { return false }
      cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
      return true
    }
    return false
  }

  private static func decode(_ data: Data) -> (image: CGImage, type: String)? {
    guard (1...5_000_000).contains(data.count),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let type = CGImageSourceGetType(source) as String?,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
      let width = properties.object(forKey: kCGImagePropertyPixelWidth) as? Int,
      let height = properties.object(forKey: kCGImagePropertyPixelHeight) as? Int,
      (1...1024).contains(width), (1...1024).contains(height),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 1024,
        ] as CFDictionary)
    else { return nil }
    return (image, type)
  }

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.urlCredentialStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 30
    return URLSession(configuration: configuration)
  }()
  @concurrent public static func download(_ request: URLRequest) async throws -> (Data, URLResponse)
  {
    try await session.data(for: request)
  }

  public func clear() throws {
    generation = UUID()
    cache.removeAllCachedResponses()
    do { try FileManager.default.removeItem(at: directory) } catch CocoaError.fileNoSuchFile {}
  }
}
