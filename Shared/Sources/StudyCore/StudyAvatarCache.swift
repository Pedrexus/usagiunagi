import Foundation
import ImageIO

/// Decodes bounded avatar images using the shared HTTP cache.
public actor StudyAvatarCache {
  public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
  private let cache: URLCache
  private let transport: Transport
  private var generation = UUID()
  public init(
    cache: URLCache = .shared,
    transport: @escaping Transport = StudyAvatarCache.download
  ) {
    self.cache = cache
    self.transport = transport
  }

  public func image(at url: URL) async throws -> CGImage {
    try Task.checkCancellation()
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

  public func clear() {
    generation = UUID()
    cache.removeAllCachedResponses()
  }
}
