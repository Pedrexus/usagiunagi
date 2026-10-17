import CryptoKit
import Foundation

public enum RadicalImageError: Error, LocalizedError {
  case invalidURL, invalidImage, tooLarge
  case response(Int)
  public var errorDescription: String? {
    switch self {
    case .invalidURL:
      "This radical does not have a valid WaniKani image address. Refresh its study content."
    case .invalidImage: "The radical image could not be read. Retry its download."
    case .tooLarge: "The radical image exceeds the supported download size."
    case .response(let code): "The radical image server returned HTTP \(code)."
    }
  }
}

/// Public image bytes only. URL versions are separate cache entries; no API credentials are used.
public actor RadicalImageCache {
  public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
  public static let shared = RadicalImageCache(
    directory: URL.applicationSupportDirectory.appending(path: "UsagiUnagi/RadicalImages"))
  public static let maximumBytes = 1_048_576
  private let directory: URL
  private let transport: Transport
  private var requests: [URL: Task<Data, any Error>] = [:]

  public init(directory: URL, transport: @escaping Transport = RadicalImageCache.download) {
    self.directory = directory
    self.transport = transport
  }

  public func image(at url: URL) async throws -> Data {
    try Self.validate(url)
    let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }
      .joined()
    let path = directory.appending(path: key + ".svg")
    do {
      let bytes = try Data(contentsOf: path, options: .mappedIfSafe)
      do {
        try Self.validate(bytes)
        return bytes
      } catch is RadicalImageError {
        // Replace corrupt cache only after a successful download.
      }
    } catch let error as CocoaError
      where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code)
    {}
    if let running = requests[url] { return try await running.value }
    let transport = transport
    let task = Task {
      var request = URLRequest(
        url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
      request.setValue("image/svg+xml", forHTTPHeaderField: "Accept")
      let (bytes, response) = try await transport(request)
      guard response.statusCode == 200 else {
        throw RadicalImageError.response(response.statusCode)
      }
      guard response.url == url, response.mimeType?.lowercased() == "image/svg+xml" else {
        throw RadicalImageError.invalidImage
      }
      try Self.validate(bytes)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try bytes.write(to: path, options: .atomic)
      return bytes
    }
    requests[url] = task
    defer { requests[url] = nil }
    return try await task.value
  }

  private static func validate(_ url: URL) throws {
    guard url.scheme == "https", url.host == "cdn.wanikani.com", url.user == nil,
      url.password == nil,
      url.port == nil || url.port == 443, url.pathExtension.lowercased() == "svg"
    else { throw RadicalImageError.invalidURL }
  }
  private static func validate(_ bytes: Data) throws {
    guard bytes.count <= maximumBytes else { throw RadicalImageError.tooLarge }
    guard let source = String(data: bytes, encoding: .utf8), !source.isEmpty,
      !source.localizedCaseInsensitiveContains("<!DOCTYPE"),
      !source.localizedCaseInsensitiveContains("<!ENTITY")
    else { throw RadicalImageError.invalidImage }
    let delegate = SVGRoot()
    let parser = XMLParser(data: bytes)
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse(), delegate.validRoot, delegate.hasShape else {
      throw RadicalImageError.invalidImage
    }
  }

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 30
    return URLSession(configuration: configuration)
  }()
  @concurrent public static func download(_ request: URLRequest) async throws -> (
    Data, HTTPURLResponse
  ) {
    let (stream, response) = try await session.bytes(for: request, delegate: ImageRedirectPolicy())
    guard let response = response as? HTTPURLResponse else { throw RadicalImageError.invalidImage }
    guard response.expectedContentLength <= maximumBytes else { throw RadicalImageError.tooLarge }
    var data = Data()
    for try await byte in stream {
      guard data.count < maximumBytes else { throw RadicalImageError.tooLarge }
      data.append(byte)
    }
    return (data, response)
  }
}

private final class ImageRedirectPolicy: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

private final class SVGRoot: NSObject, XMLParserDelegate {
  var validRoot = false, hasShape = false
  private var sawRoot = false
  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if !sawRoot {
      sawRoot = true
      validRoot = elementName == "svg" && namespaceURI == "http://www.w3.org/2000/svg"
      if !validRoot { parser.abortParsing() }
    }
    if ["path", "line", "rect", "circle", "ellipse", "polygon", "polyline", "use", "text"].contains(
      elementName)
    {
      hasShape = true
    }
  }
}
