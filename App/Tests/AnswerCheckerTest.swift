// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import StudyCore
import Testing

struct AnswerCheckerTest {
  @Test func testKatakanaToHiragana() {
    #expect(AnswerGrader.convertKatakanaToHiragana("ヒラガナ") == "ひらがな")
    #expect(AnswerGrader.convertKatakanaToHiragana("ビール") == "びーる")
    #expect(AnswerGrader.convertKatakanaToHiragana("ビー") == "びー")
    #expect(AnswerGrader.convertKatakanaToHiragana("ール") == "ーる")
  }

  @Test func testNormalizedString() {
    #expect(
      AnswerGrader
        .normalizedString(" Foo-B.a'/r nn ", taskType: .meaning) == "foo bar nn")
    #expect(
      AnswerGrader
        .normalizedString(" Foo-B.a'/r nn ", taskType: .reading) == "foobarんん")
  }

  private func subject(
    _ japanese: String = "一", meanings: [String] = ["One"],
    primary: [String] = ["いち"], alternate: [String] = ["ひと"],
    vocabulary: Bool = false, blacklist: [String] = [], components: [Int64] = []
  ) -> GradingSubject {
    GradingSubject(
      japanese: japanese, kind: vocabulary ? .vocabulary : .kanji,
      meanings: meanings, blacklistedMeanings: blacklist, primaryReadings: primary,
      alternateReadings: alternate, componentSubjectIds: components)
  }

  private func check(
    _ answer: String, subject: GradingSubject? = nil, type: StudyQuestionKind = .meaning,
    synonyms: [String] = [], lookup: (Int64) -> GradingSubject? = { _ in nil }
  ) -> AnswerGrade {
    AnswerGrader.checkNormalizedAnswer(
      answer, subject: subject ?? self.subject(), synonyms: synonyms,
      taskType: type, subjectLookup: lookup)
  }

  @Test func testMeaningSynonymsAndAuxiliaryWhitelist() {
    let item = subject(meanings: ["One", "Single"])
    #expect(check("one", subject: item) == .precise)
    #expect(check("single", subject: item) == .precise)
    #expect(check("unity", subject: item, synonyms: ["Unity"]) == .precise)
  }

  @Test func testBlacklistWinsEvenOverExactSynonym() {
    let item = subject(blacklist: ["Won"])
    #expect(check("won", subject: item, synonyms: ["Won"]) == .incorrect)
  }

  @Test func testMeaningTypoToleranceAndTransposition() {
    #expect(check("bnuny", subject: subject(meanings: ["Bunny"])) == .imprecise)
    #expect(check("bunn", subject: subject(meanings: ["Bunny"])) == .imprecise)
    #expect(check("bxxny", subject: subject(meanings: ["Bunny"])) == .incorrect)
    #expect(check("oen") == .incorrect)  // Three-letter meanings have no typo allowance.
  }

  @Test func testPrimaryAndAlternateReadingSemantics() {
    #expect(check("いち", type: .reading) == .precise)
    #expect(check("イチ", type: .reading) == .precise)
    #expect(check("ひと", type: .reading) == .otherKanjiReading)
    #expect(check("ひと", subject: subject(vocabulary: true), type: .reading) == .precise)
    #expect(check("いぢ", type: .reading) == .incorrect)  // Reading typos are not accepted.
  }

  @Test func testKatakanaSubjectPreservesLongVowel() {
    let item = subject("ビール", meanings: ["Beer"], primary: ["ビール"], alternate: [], vocabulary: true)
    #expect(check("びーる", subject: item, type: .reading) == .precise)
    #expect(check("びる", subject: item, type: .reading) == .incorrect)
  }

  @Test func testSingleKanjiVocabularyConsultsItsComponent() {
    let item = subject("一", primary: ["ひとつ"], alternate: [], vocabulary: true, components: [99])
    var lookedUp: [Int64] = []
    let result = check(
      "いち", subject: item, type: .reading,
      lookup: { id in
        lookedUp.append(id)
        return self.subject()
      })
    #expect(lookedUp == [99])
    #expect(result == .otherKanjiReading)
    #expect(check("いち", subject: item, type: .reading) == .incorrect)
  }

  @Test func testInvalidScriptRanges() {
    #expect(
      check("ichい", type: .reading) == .containsInvalidCharacters([NSRange(location: 0, length: 3)])
    )
    #expect(check("a漢字b") == .containsInvalidCharacters([NSRange(location: 1, length: 2)]))
  }

  @Test func testMismatchingOkuriganaIsNotAnOrdinaryWrongAnswer() {
    let item = subject("食べる", primary: ["たべる"], alternate: [], vocabulary: true)
    #expect(
      check("たべろ", subject: item, type: .reading)
        == .mismatchingOkurigana([NSRange(location: 2, length: 1)]))
    #expect(check("たべる", subject: item, type: .reading) == .precise)
  }

  @Test func testReadingEnteredForMeaningGetsSpecificFeedback() {
    #expect(check("ichi") == .isReadingButWantMeaning)
    #expect(check("hito") == .otherKanjiReading)
    #expect(check("not an answer") == .incorrect)
  }
}
