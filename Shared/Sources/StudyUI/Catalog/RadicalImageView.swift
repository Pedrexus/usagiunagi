import StudyCore
import SwiftUI
import WebKit

extension EnvironmentValues {
  @Entry public var studyRadicalImages: RadicalImageCache = .shared
}

/// SVG stays inside an image context. Web content cannot run scripts or fetch other resources.
public struct RadicalImageView: View {
  private let url: URL
  @Environment(\.studyRadicalImages) private var cache
  private let available: (Bool) -> Void
  @Environment(\.colorScheme) private var colorScheme
  @State private var page = {
    var configuration = WebPage.Configuration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultNavigationPreferences.allowsContentJavaScript = false
    configuration.deviceSensorAuthorization = .init(decision: .deny)
    return WebPage(configuration: configuration)
  }()
  @State private var error: String?
  @State private var loaded = false
  @State private var attempt = 0

  public init(
    url: URL, available: @escaping (Bool) -> Void = { _ in }
  ) {
    self.url = url
    self.available = available
  }

  public var body: some View {
    ZStack {
      WebView(page).webViewContentBackground(.hidden).allowsHitTesting(false)
        .accessibilityHidden(true).opacity(loaded ? 1 : 0)
      if let error {
        VStack {
          Text(error).font(.caption)
          Button("Retry image", systemImage: "arrow.clockwise") { attempt += 1 }
        }
      } else if !loaded {
        ProgressView("Loading radical")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Radical image")
    .task(id: "\(url.absoluteString)|\(colorScheme)|\(attempt)") { await load() }
    .onDisappear { page.stopLoading() }
  }

  private func load() async {
    loaded = false
    error = nil
    available(false)
    do {
      let data = try await cache.image(at: url)
      try Task.checkCancellation()
      let filter = colorScheme == .dark ? "invert(1)" : "none"
      let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'">
        <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}img{width:100%;height:100%;object-fit:contain;filter:\(filter)}</style>
        </head><body><img alt="" src="data:image/svg+xml;base64,\(data.base64EncodedString())"></body></html>
        """
      for try await _ in page.load(html: html) { try Task.checkCancellation() }
      try Task.checkCancellation()
      loaded = true
      available(true)
    } catch is CancellationError {} catch {
      guard !Task.isCancelled else { return }
      self.error = "Couldn't load this radical. \(error.localizedDescription)"
    }
  }
}
