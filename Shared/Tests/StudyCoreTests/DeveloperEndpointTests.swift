import Testing

@testable import StudyCore

struct DeveloperEndpointTests {
  private let standard = "https://api.wanikani.com/v2"
  @Test(arguments: [
    ("  https://example.test/v2///\n", "https://example.test/v2"),
    ("http://localhost:8080/api/", "http://localhost:8080/api"),
    ("HTTPS://example.test/api", "HTTPS://example.test/api"),
  ])
  func keepsCustomHTTPServersAndTrimsTrailingSlashes(_ input: String, _ expected: String) {
    #expect(DeveloperEndpoint.normalized(input, defaultURL: standard) == expected)
  }
  @Test(arguments: ["", " \n ", "/", "////"])
  func blankRestoresDefault(_ input: String) {
    #expect(DeveloperEndpoint.normalized(input, defaultURL: standard) == standard)
  }
  @Test(arguments: [
    "not a URL", "file:///tmp/cache.db", "ftp://example.test", "https://",
    "https://user:password@example.test/v2", "https://user@example.test/v2",
    "https://example.test/v2?token=fixture", "https://example.test/v2?",
    "https://example.test/v2#user", "https://example.test/v2#",
    "https://example.test/v2/../other", "https://example.test/v2/./other",
    "https://example.test/v2/%2e%2e/other",
  ])
  func invalidEndpointsCannotReplaceSavedValue(_ input: String) {
    #expect(DeveloperEndpoint.normalized(input, defaultURL: standard) == nil)
  }
}
