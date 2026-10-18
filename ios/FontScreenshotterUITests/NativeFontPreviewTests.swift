// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import CoreImage
import XCTest

final class NativeFontPreviewTests: XCTestCase {
  @MainActor func testScreenshotFontPreviews() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let previews = app.staticTexts.matching(identifier: "preview")
    XCTAssertEqual(previews.count, 8)
    let context = CIContext()
    for index in 0..<previews.count {
      let preview = previews.element(boundBy: index)
      for _ in 0..<12 {
        if preview.isHittable && preview.frame.maxY < app.frame.maxY - 20 { break }
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
      }
      XCTAssertTrue(preview.isHittable)
      let original = try XCTUnwrap(preview.screenshot().image.cgImage)
      let image = CIImage(cgImage: original)
      let mask = image.applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha")
      let black = CIImage(color: .black).cropped(to: image.extent)
      let clear = CIImage(color: .clear).cropped(to: image.extent)
      let transparent = black.applyingFilter(
        "CIBlendWithAlphaMask",
        parameters: [
          kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: mask,
        ])
      let output = try XCTUnwrap(context.createCGImage(transparent, from: image.extent))
      let attachment = XCTAttachment(image: UIImage(cgImage: output))
      attachment.name = preview.label
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }
}
