import CryptoKit
import Foundation
import ImageIO

/// Imports the former Haneke shared image cache without retaining its Objective-C dependency.
public actor LegacyAvatarCache {
  private let directory: URL
  private let cache: URLCache
  public init(directory: URL, cache: URLCache = .shared) {
    self.directory = directory
    self.cache = cache
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
        let image = CGImageSourceCreateWithData(data as CFData, nil),
        let type = CGImageSourceGetType(image) as String?,
        ["public.png", "public.jpeg"].contains(type),
        let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as NSDictionary?,
        let width = properties.object(forKey: kCGImagePropertyPixelWidth) as? Int,
        let height = properties.object(forKey: kCGImagePropertyPixelHeight) as? Int,
        (1...1024).contains(width), (1...1024).contains(height),
        CGImageSourceCreateImageAtIndex(image, 0, nil) != nil,
        let response = HTTPURLResponse(
          url: url, statusCode: 200, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": type == "public.png" ? "image/png" : "image/jpeg"])
      else { continue }
      guard !Task.isCancelled, cache.cachedResponse(for: request) == nil else { return false }
      cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
      return true
    }
    return false
  }

  public func clear() throws {
    cache.removeAllCachedResponses()
    do { try FileManager.default.removeItem(at: directory) } catch CocoaError.fileNoSuchFile {}
  }
}
