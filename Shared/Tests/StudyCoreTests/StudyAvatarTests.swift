import Foundation
import Testing

@testable import StudyCore

struct StudyAvatarTests {
  @Test(arguments: [
    "MyEmailAddress@example.com ", "myemailaddress@example.com", "\n MyEmailAddress@example.com\t",
  ])
  func normalizedAddressUsesTheDocumentedHashAndOriginalCacheURL(_ email: String) {
    let url = StudyAvatar.url(email: email, pixelSize: 160)
    #expect(
      url.absoluteString
        == "https://www.gravatar.com/avatar/84059b07d4be67b806386c0aad8070a23f18836bbaae342275dc0a83414c32ee.jpg?s=160.0&d=https://cdn.wanikani.com/default-avatar-300x300-20121121.png"
    )
    #expect(!url.absoluteString.contains("@"))
  }
  @Test(arguments: ["", " ", "\n\t"])
  func noAddressUsesWaniKaniDefaultWithoutAnEmptyGravatarHash(_ email: String) {
    #expect(StudyAvatar.url(email: email, pixelSize: 240) == StudyAvatar.defaultURL)
  }
  @Test(arguments: [80.0, 160.0, 240.0])
  func displayScaleOnlyChangesRequestedPixels(_ pixels: Double) throws {
    let url = StudyAvatar.url(email: "MyEmailAddress@example.com", pixelSize: pixels)
    let values = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(values.first { $0.name == "s" }?.value == String(pixels))
    #expect(values.first { $0.name == "d" }?.value == StudyAvatar.defaultURL.absoluteString)
  }
}
