import Foundation
import StudyCore
import Testing

struct StudyLinkTests {
  @Test(arguments: ["tsurukame", "usagiunagi"])
  func customSchemesAcceptPathAndAuthorityRoutes(scheme: String) throws {
    for base in ["\(scheme):/", "\(scheme):///", "\(scheme)://"] {
      #expect(StudyLink(url: try #require(URL(string: base + "reviews"))) == .reviews)
      #expect(StudyLink(url: try #require(URL(string: base + "lessons"))) == .lessons)
      #expect(StudyLink(url: try #require(URL(string: base + "wrap-up"))) == .wrapUp)
      #expect(StudyLink(url: try #require(URL(string: base + "subject/42"))) == .subject(.id(42)))
    }
    #expect(StudyLink(url: try #require(URL(string: "\(scheme):///"))) == .activate)
  }
  @Test func universalPathsAndEncodedJapaneseKeepTheirExactSubject() throws {
    let examples: [(String, StudyLink)] = [
      ("https://tsurukame.app/", .activate),
      ("https://tsurukame.app:443/lessons", .lessons),
      ("https://tsurukame.app/reviews?source=shortcut#top", .reviews),
      ("https://tsurukame.app/kanji/%E4%B8%80", .subject(.japanese(.kanji, "一"))),
      ("usagiunagi://radical/%E4%BA%85", .subject(.japanese(.radical, "亅"))),
      ("tsurukame:///vocabulary/%E4%B8%80%E3%81%A4", .subject(.japanese(.vocabulary, "一つ"))),
      ("usagiunagi:///vocabulary/%E6%9C%A8%2F%E5%B1%B1", .subject(.japanese(.vocabulary, "木/山"))),
    ]
    for (text, expected) in examples {
      #expect(StudyLink(url: try #require(URL(string: text))) == expected)
    }
    #expect(StudyLink(activity: .reviews) == .reviews)
    #expect(StudyLink(activity: .lessons) == .lessons)
  }
  @Test(arguments: [
    "https://example.com/reviews", "http://tsurukame.app/reviews", "file:///reviews",
    "https://tsurukame.app.example.com/reviews", "https://someone@tsurukame.app/reviews",
    "usagiunagi://someone:password@reviews", "tsurukame://reviews:123",
    "usagiunagi:///subject/0", "usagiunagi:///subject/-42",
    "usagiunagi:///subject/9223372036854775808", "usagiunagi:///subject/nope",
    "usagiunagi:///subject/42/extra", "usagiunagi:///reviews/extra",
    "usagiunagi:///kanji/%FF", "usagiunagi:///reviews%2Flessons", "usagiunagi:///kanji/",
    "usagiunagi:///kanji/%20", "usagiunagi:///upload",
  ])
  func unrelatedOrMalformedURLsAreNotRoutes(text: String) throws {
    #expect(StudyLink(url: try #require(URL(string: text))) == nil)
  }
}
