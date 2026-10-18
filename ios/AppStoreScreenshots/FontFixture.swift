// Synthetic UI fixtures only; production font selection and storage are not replaced.
#if DEBUG
  import CoreText
  import Foundation
  import Synchronization

  extension Screenshotter {
    @nonobjc @MainActor static func fontFixture() -> (FontLoader, URLSessionConfiguration)? {
      guard isActive, ProcessInfo.processInfo.arguments.contains("FontFlowFixture") else {
        return nil
      }
      let font = CTFontCreateWithName("HiraginoMinchoProN-W3" as CFString, 24, nil)
      let family = CTFontCopyFamilyName(font) as String
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "font-fixture-\(UUID().uuidString)")
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let loader = FontLoader(
        definitions: [
          .init(family, "font-ready.ttf", "Installed font fixture", 1024),
          .init(family, "font-download.ttf", "Download font fixture", 1024),
          .init("MissingFontFixture", "font-failed.ttf", "Failed font fixture", 1024),
          .init(family, "font-held.ttf", "Held font fixture", 1024),
        ], directory: directory, bundledFonts: nil)
      for font in loader.allFonts where font.fileName != "font-ready.ttf" { font.didDelete() }
      var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
      arguments["selectedFonts"] = try? NSKeyedArchiver.archivedData(
        withRootObject: Set<String>(), requiringSecureCoding: true)
      UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [FontFixtureProtocol.self]
      return (loader, configuration)
    }
  }

  private final class FontFixtureProtocol: URLProtocol, @unchecked Sendable {
    private let work = Mutex((cancelled: false, task: Optional<Task<Void, Never>>.none))
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      guard request.url?.lastPathComponent != "font-held.ttf" else { return }
      let task = Task.detached { [weak self] in
        do {
          guard let self else { return }
          let failed = request.url?.lastPathComponent == "font-failed.ttf"
          if !failed { try await Task.sleep(for: .seconds(5)) }
          let font = CTFontCreateWithName("HiraginoMinchoProN-W3" as CFString, 24, nil)
          guard let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL else {
            throw URLError(.fileDoesNotExist)
          }
          let data = failed ? Data("Unavailable".utf8) : try Data(contentsOf: url)
          guard !Task.isCancelled else { return }
          let response = HTTPURLResponse(
            url: request.url!, statusCode: failed ? 503 : 200, httpVersion: nil,
            headerFields: ["Content-Length": "\(data.count)"])!
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: data)
          client?.urlProtocolDidFinishLoading(self)
        } catch {
          if !Task.isCancelled, let self { client?.urlProtocol(self, didFailWithError: error) }
        }
      }
      work.withLock { if $0.cancelled { task.cancel() } else { $0.task = task } }
    }
    override func stopLoading() {
      work.withLock {
        $0.cancelled = true
        $0.task?.cancel()
        $0.task = nil
      }
    }
  }
#endif
