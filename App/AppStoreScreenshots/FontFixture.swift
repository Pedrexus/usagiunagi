// Synthetic UI fixtures only; production font selection and storage are not replaced.
#if DEBUG
  import CoreText
  import Foundation
  import StudyCore
  import Synchronization

  @MainActor enum StudyFontFixture {
    static func make() -> (StudyFontCatalog, URLSessionConfiguration) {
      let font = CTFontCreateWithName("HiraMinProN-W3" as CFString, 24, nil)
      let name = CTFontCopyPostScriptName(font) as String
      let directory = URL.temporaryDirectory.appending(path: "font-fixture-\(UUID())")
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let catalog = StudyFontCatalog(
        definitions: [
          .init(name, "font-ready.ttf", "Installed font fixture", 1024),
          .init("DownloadFontFixture", "font-download.ttf", "Download font fixture", 1024),
          .init("MissingFontFixture", "font-failed.ttf", "Failed font fixture", 1024),
          .init("HeldFontFixture", "font-held.ttf", "Held font fixture", 1024),
        ], directory: directory,
        bundledFonts: nil)
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [FontFixtureProtocol.self]
      return (catalog, configuration)
    }
  }

  // URLProtocol invokes callbacks outside the main actor; cancellation state is mutex-protected.
  nonisolated final class FontFixtureProtocol: URLProtocol, @unchecked Sendable {
    private let cancelled = Mutex(false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      guard request.url?.lastPathComponent != "font-held.ttf" else { return }
      let failed = request.url?.lastPathComponent == "font-failed.ttf"
      DispatchQueue.global().asyncAfter(deadline: .now() + (failed ? 0 : 5)) { [weak self] in
        guard let self, !self.cancelled.withLock({ $0 }) else { return }
        do {
          let font = CTFontCreateWithName("HiraMinProN-W3" as CFString, 24, nil)
          guard let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL else {
            throw URLError(.fileDoesNotExist)
          }
          let data = failed ? Data("Unavailable".utf8) : try Data(contentsOf: url)
          guard !self.cancelled.withLock({ $0 }) else { return }
          let response = HTTPURLResponse(
            url: self.request.url!, statusCode: failed ? 503 : 200,
            httpVersion: nil, headerFields: ["Content-Length": "\(data.count)"])!
          self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          self.client?.urlProtocol(self, didLoad: data)
          self.client?.urlProtocolDidFinishLoading(self)
        } catch { self.client?.urlProtocol(self, didFailWithError: error) }
      }
    }
    override func stopLoading() { cancelled.withLock { $0 = true } }
  }
#endif
