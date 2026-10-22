import Foundation
import Testing

@testable import StudyCore

struct HiraganaReadingTests {
  @Test(arguments: [
    ("いち", "いち"), ("カタカナ", "かたかな"), ("スーパー", "すーぱー"),
    ("ｶﾞｯｺｳ", "がっこう"), (" きょう と\n", "きょうと"),
    ("1つ", "ひとつ"), ("１つ", "ひとつ"), ("1人", "ひとり"), ("2人", "ふたり"),
    ("20日", "はつか"), ("２０日", "はつか"), ("100円", "ひゃくえん"),
  ])
  func nativeReadingPreservesKanaAndExpandsCounters(_ input: String, _ expected: String) {
    #expect(KanaConverter.hiraganaReading(input) == expected)
  }

  @Test(arguments: ["生", "日本", "一日"])
  func ambiguousWordsRemainDictionaryCandidatesRatherThanVerifiedPronunciations(_ text: String)
    throws
  {
    // The platform dictionary may prefer なま/せい, にっぽん/にほん or いちにち/ついたち.
    // A kana candidate alone does not prove which reading was spoken or that an answer is correct.
    let reading = try #require(KanaConverter.hiraganaReading(text))
    #expect(!reading.isEmpty && reading != text)
    #expect(reading.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) || $0 == "ー" })
  }

  @Test(arguments: [
    "", " \n", "One", "一🐰", "一/二", "1.5人", "0001つ", "1000000000つ",
    "れ\u{301}", String(repeating: "あ", count: 257),
  ])
  func unsupportedOrUnboundedInputCannotBecomeAnAnswer(_ text: String) {
    #expect(KanaConverter.hiraganaReading(text) == nil)
  }
}
