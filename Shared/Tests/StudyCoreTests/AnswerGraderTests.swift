import Foundation
import Testing
import StudyCore

struct AnswerGraderTests {
    private let kanji = GradingSubject(japanese: "一", kind: .kanji, meanings: ["One", "Single"],
                                       blacklistedMeanings: ["Won"], primaryReadings: ["いち"], alternateReadings: ["ひと"])

    @Test(arguments: [
        ("one", AnswerGrade.precise), ("single", .precise), ("unity", .precise),
        ("won", .incorrect), ("oen", .incorrect), ("ichi", .isReadingButWantMeaning),
        ("hito", .otherKanjiReading), ("not an answer", .incorrect)
    ])
    func meaningRules(_ answer: String, _ expected: AnswerGrade) {
        #expect(AnswerGrader.checkNormalizedAnswer(answer, subject: kanji, synonyms: ["Unity", "Won"], taskType: .meaning) == expected)
    }

    @Test(arguments: [
        ("いち", AnswerGrade.precise), ("イチ", .precise), ("ひと", .otherKanjiReading), ("いぢ", .incorrect)
    ])
    func readingRules(_ answer: String, _ expected: AnswerGrade) {
        #expect(AnswerGrader.checkNormalizedAnswer(answer, subject: kanji, taskType: .reading) == expected)
    }

    @Test func meaningTypoTolerance() {
        let subject = GradingSubject(japanese: "兎", kind: .radical, meanings: ["Bunny"])
        for answer in ["bnuny", "bunn"] {
            #expect(AnswerGrader.checkNormalizedAnswer(answer, subject: subject, taskType: .meaning) == .imprecise)
        }
        #expect(AnswerGrader.checkNormalizedAnswer("bxxny", subject: subject, taskType: .meaning) == .incorrect)
    }

    @Test func vocabularyAlternateAndComponentReadings() {
        let subject = GradingSubject(japanese: "一", kind: .vocabulary, meanings: ["One"], primaryReadings: ["ひとつ"],
                                     alternateReadings: ["ひと"], componentSubjectIds: [1])
        #expect(AnswerGrader.checkNormalizedAnswer("ひと", subject: subject, taskType: .reading) == .precise)
        #expect(AnswerGrader.checkNormalizedAnswer("いち", subject: subject, taskType: .reading) == .incorrect)
        #expect(AnswerGrader.checkNormalizedAnswer("いち", subject: subject, taskType: .reading,
                                                   subjectLookup: { _ in kanji }) == .otherKanjiReading)
        // Malformed component data must not recurse indefinitely.
        #expect(AnswerGrader.checkNormalizedAnswer("いち", subject: subject, taskType: .reading,
                                                   subjectLookup: { _ in subject }) == .incorrect)
    }

    @Test func okuriganaAndLongVowels() {
        let subject = GradingSubject(japanese: "食べる", kind: .vocabulary, meanings: ["To Eat"], primaryReadings: ["たべる"])
        #expect(AnswerGrader.checkNormalizedAnswer("たべろ", subject: subject, taskType: .reading)
            == .mismatchingOkurigana([NSRange(location: 2, length: 1)]))
        let beer = GradingSubject(japanese: "ビール", kind: .vocabulary, meanings: ["Beer"], primaryReadings: ["ビール"])
        #expect(AnswerGrader.checkNormalizedAnswer("びーる", subject: beer, taskType: .reading) == .precise)
        #expect(AnswerGrader.checkNormalizedAnswer("びる", subject: beer, taskType: .reading) == .incorrect)
        #expect(AnswerGrader.convertKatakanaToHiragana("ービーーールー") == "ーびーーーるー")
    }

    @Test func invalidScriptRangesUseNativeUTF16Offsets() {
        #expect(AnswerGrader.checkNormalizedAnswer("a😀漢字b", subject: kanji, taskType: .meaning)
            == .containsInvalidCharacters([NSRange(location: 3, length: 2)]))
        #expect(AnswerGrader.checkNormalizedAnswer("い😀aち𠮷", subject: kanji, taskType: .reading)
            == .containsInvalidCharacters([NSRange(location: 1, length: 3), NSRange(location: 5, length: 2)]))
    }

    @Test func okuriganaRangesRespectDecomposedKana() {
        let subject = GradingSubject(japanese: "食べる", kind: .vocabulary, meanings: ["To Eat"], primaryReadings: ["たべる"])
        let answer = "たへ\u{3099}ろ"
        guard case let .mismatchingOkurigana(ranges) = AnswerGrader.checkNormalizedAnswer(answer, subject: subject, taskType: .reading) else {
            Issue.record("Expected okurigana feedback")
            return
        }
        #expect(ranges == [NSRange(location: 2, length: 2)])
        #expect((answer as NSString).substring(with: ranges[0]) == "\u{3099}ろ")
    }

    @Test func normalizationPreservesQuestionSemantics() {
        #expect(AnswerGrader.normalizedString(" Foo-B.a'/r nn ", taskType: .meaning) == "foo bar nn")
        #expect(AnswerGrader.normalizedString(" Foo-B.a'/r nn ", taskType: .reading) == "foobarんん")
        #expect(AnswerGrader.normalizedString("ｎ n", taskType: .reading, alphabet: .katakana) == "ンン")
    }
}
