import Foundation
import ImageIO
import StudyCore
import Testing

@testable import Tsurukame

@MainActor @Suite(.timeLimit(.minutes(1)))
struct RadicalImageExportTests {
  @Test func validatedSVGBecomesABoundedVisibleWatchBitmap() async throws {
    let directory = URL.temporaryDirectory.appending(path: "radical-export-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = RadicalImageCache(
      directory: directory,
      transport: { request in
        let svg = """
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
          <rect x="32" y="32" width="64" height="64" fill="black"/></svg>
          """
        return (
          Data(svg.utf8),
          HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/svg+xml"])!
        )
      })
    let url = try #require(URL(string: "https://cdn.wanikani.com/watch-fixture.svg"))
    let bytes = try await RadicalImageView.bitmap(at: url, cache: cache)
    #expect(!bytes.isEmpty && bytes.count <= 32_000)
    let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 128 && image.height == 128)
    var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
    try pixels.withUnsafeMutableBytes { buffer in
      let context = try #require(
        CGContext(
          data: buffer.baseAddress, width: 128, height: 128, bitsPerComponent: 8,
          bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 128))
    }
    #expect(pixels[(64 * 128 + 64) * 4 + 3] > 200, "The radical must render before listening")
    #expect(pixels[3] < 20, "The Watch subject color must remain visible around the radical")
  }
}
