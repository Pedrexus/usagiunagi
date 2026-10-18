import Foundation
import Testing
@testable import StudyCore

struct KanaConverterTests {
    // Whole-string conversion preserves the legacy nn -> ん rule, even before a vowel.
    @Test(arguments: [
        ("", "", true), ("gakkou", "がっこう", true), ("shimbun", "しんぶん", true),
        ("konnichiha", "こんいちは", true), ("konnichiwa", "こんいちわ", true),
        ("kanj", "かん", false), ("kaq", "か", false), ("n ", "ん", true),
        ("m", "ん", true), ("nn", "ん", true), ("mm", "っん", true),
        ("KANJI", "KANJI", true), ("kyou", "きょう", true), ("thi", "てぃ", true),
        ("-", "ー", true), ("日本nk", "日本ん", false), ("😀a", "😀あ", true),
        ("é", "", false), ("e\u{301}", "え\u{301}", true), ("𠮷", "𠮷", true),
        ("ッン", "ッン", true)
    ])
    func wholeString(_ input: String, _ expected: String, _ complete: Bool) {
        let result = KanaConverter.convert(input)
        #expect(result.text == expected)
        #expect(result.convertedAllCharacters == complete)
    }

    @Test func completeMappingTable() {
        #expect(KanaConverter.replacements.count == 290)
        for (roman, kana) in KanaConverter.replacements {
            #expect(KanaConverter.convert(roman).text == kana)
            // Whole-string and incremental conversion intentionally handle n + space differently.
            guard roman != "n " else { continue }
            let prefix = String(roman.dropLast())
            let edit = KanaConverter.edit(text: prefix, range: NSRange(location: prefix.utf16.count, length: 0),
                                          replacement: String(roman.suffix(1)))
            #expect(edit?.text == kana)
            #expect(edit?.allowsSystemChange == false)
            #expect(edit?.cursor == kana.utf16.count)
        }
    }

    @Test func interactiveCaseAndKatakana() {
        for alphabet in [KanaAlphabet.hiragana, .katakana] {
            for (roman, kana) in KanaConverter.replacements where roman != "n " {
                let uppercase = roman.uppercased()
                let prefix = String(uppercase.dropLast())
                let edit = KanaConverter.edit(text: prefix, range: NSRange(location: prefix.utf16.count, length: 0),
                                              replacement: String(uppercase.suffix(1)), alphabet: alphabet)
                #expect(edit?.text == kana.applyingTransform(.hiraganaToKatakana, reverse: false))
            }
        }
    }

    @Test func sokuonAndNasalBoundaries() {
        for consonant in "bcdfghjklpqrstvwxz" {
            let letter = String(consonant)
            let edit = KanaConverter.edit(text: letter, range: NSRange(location: 1, length: 0), replacement: letter)
            #expect(edit?.text == "っ")
            #expect(edit?.allowsSystemChange == true)
            #expect(edit?.cursor == nil)
            for nasal in ["n", "m"] {
                #expect(KanaConverter.edit(text: nasal, range: NSRange(location: 1, length: 0), replacement: letter)?.text == "ん")
            }
        }
        #expect(KanaConverter.edit(text: "n", range: NSRange(location: 1, length: 0), replacement: "y") == nil)
        #expect(KanaConverter.edit(text: "m", range: NSRange(location: 1, length: 0), replacement: "m")?.text == "ん")
    }

    @Test func pasteSelectionAndUTF16Cursor() {
        let paste = KanaConverter.edit(text: "😀い", range: NSRange(location: 2, length: 0), replacement: "kya")
        #expect(paste?.text == "😀きゃい")
        #expect(paste?.cursor == 4)
        #expect(paste?.allowsSystemChange == false)
        let selection = KanaConverter.edit(text: "😀かな", range: NSRange(location: 2, length: 2), replacement: "A")
        #expect(selection?.text == "😀ア")
        #expect(selection?.cursor == 3)
        #expect(KanaConverter.edit(text: "かな", range: NSRange(location: 0, length: 2), replacement: "ka") == nil)
        #expect(KanaConverter.edit(text: "かな", range: NSRange(location: 1, length: 1), replacement: "") == nil)
        #expect(KanaConverter.edit(text: "かな", range: NSRange(location: 1, length: 0), replacement: "日本語") == nil)
        #expect(KanaConverter.edit(text: "かな", range: NSRange(location: NSNotFound, length: 1), replacement: "a") == nil)
    }
}
