import Testing
import WaniKaniAPI

struct ProtobufVocabularyTests {
  @Test(arguments: [
    (0, ""), (1, "Noun"), (2, "Numeral"), (3, "Intransitive Verb"),
    (4, "Ichidan Verb"), (5, "Transitive Verb"), (6, "No Adjective"),
    (7, "Godan Verb"), (8, "Na Adjective"), (9, "I Adjective"), (10, "Suffix"),
    (11, "Adverb"), (12, "Suru Verb"), (13, "Prefix"), (14, "Proper Noun"),
    (15, "Expression"), (16, "Adjective"), (17, "Interjection"), (18, "Counter"),
    (19, "Pronoun"), (20, "Conjunction"), (999, ""),
  ])
  func historicalPartOfSpeechCodesKeepTheirDescriptions(code: Int, expected: String) throws {
    let value = try #require(TKMVocabulary.PartOfSpeech(rawValue: code))
    #expect(value.description == expected)
  }
}
