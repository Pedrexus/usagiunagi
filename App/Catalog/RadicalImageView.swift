import CoreImage.CIFilterBuiltins
import ImageIO
import StudyCore
import SwiftUI
import WebKit

extension EnvironmentValues {
  @Entry public var studyRadicalImages: RadicalImageCache = .shared
}

/// SVG stays inside an image context. Web content cannot run scripts or fetch other resources.
public struct RadicalImageView: View {
  let url: URL
  @Environment(\.studyRadicalImages) private var cache
  var available: (Bool) -> Void = { _ in }
  @Environment(\.colorScheme) private var colorScheme
  @State private var page = makePage()

  private static func makePage() -> WebPage {
    var configuration = WebPage.Configuration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultNavigationPreferences.allowsContentJavaScript = false
    configuration.deviceSensorAuthorization = .init(decision: .deny)
    return WebPage(configuration: configuration)
  }
  @State private var error: String?
  @State private var loaded = false
  @State private var attempt = 0

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
      let html = Self.html(data, filter: filter)
      for try await _ in page.load(html: html) { try Task.checkCancellation() }
      try Task.checkCancellation()
      loaded = true
      available(true)
    } catch is CancellationError {} catch {
      guard !Task.isCancelled else { return }
      self.error = "Couldn't load this radical. \(error.localizedDescription)"
    }
  }

  /// A bounded bitmap lets image-only radicals use the same validated SVG on Watch.
  public static func bitmap(at url: URL, cache: RadicalImageCache) async throws -> Data {
    let data = try await cache.image(at: url)
    try Task.checkCancellation()
    let page = makePage()
    defer { page.stopLoading() }
    for try await _ in page.load(
      html: html(
        data, filter: "invert(1)", size: "128px", background: "black"))
    {
      try Task.checkCancellation()
    }
    let rendered = try await page.exported(
      as: .image(
        region: .rect(CGRect(x: 0, y: 0, width: 128, height: 128)),
        allowTransparentBackground: true, snapshotWidth: 128))
    try Task.checkCancellation()
    guard let source = CGImageSourceCreateWithData(rendered as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 128,
        ] as CFDictionary)
    else { throw RadicalImageError.invalidImage }
    let mask = CIFilter.maskToAlpha()
    mask.inputImage = CIImage(cgImage: image)
    guard let output = mask.outputImage,
      let transparent = CIContext().createCGImage(output, from: output.extent)
    else { throw RadicalImageError.invalidImage }
    let bytes = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil)
    else { throw RadicalImageError.invalidImage }
    CGImageDestinationAddImage(destination, transparent, nil)
    guard CGImageDestinationFinalize(destination), bytes.length <= 32_000 else {
      throw RadicalImageError.tooLarge
    }
    return bytes as Data
  }

  private static func html(
    _ data: Data, filter: String, size: String = "100%", background: String = "transparent"
  ) -> String {
    """
    <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'">
    <style>html,body{margin:0;width:\(size);height:\(size);overflow:hidden;background:\(background)}img{width:100%;height:100%;object-fit:contain;filter:\(filter)}</style>
    </head><body><img alt="" src="data:image/svg+xml;base64,\(data.base64EncodedString())"></body></html>
    """
  }
}
