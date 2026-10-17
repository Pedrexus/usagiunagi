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

import WaniKaniAPI
import XCTest

class AnswerCheckerTest: XCTestCase {
  func testKatakanaToHiragana() {
    XCTAssertEqual(AnswerChecker.convertKatakanaToHiragana("ヒラガナ"), "ひらがな")
    XCTAssertEqual(AnswerChecker.convertKatakanaToHiragana("ビール"), "びーる")
    XCTAssertEqual(AnswerChecker.convertKatakanaToHiragana("ビー"), "びー")
    XCTAssertEqual(AnswerChecker.convertKatakanaToHiragana("ール"), "ーる")
  }

  func testNormalizedString() {
    XCTAssertEqual(AnswerChecker.normalizedString(" Foo-B.a'/r nn ", taskType: TaskType.meaning),
                   "foo bar nn")
    XCTAssertEqual(AnswerChecker.normalizedString(" Foo-B.a'/r nn ", taskType: TaskType.reading),
                   "foobarんん")
  }

  private func subject(_ japanese: String = "一", meanings: [String] = ["One"],
                       primary: [String] = ["いち"], alternate: [String] = ["ひと"],
                       vocabulary: Bool = false) -> TKMSubject {
    var subject = TKMSubject()
    subject.id = 1
    subject.japanese = japanese
    if vocabulary { subject.vocabulary = .init() } else { subject.kanji = .init() }
    subject.meanings = meanings.map { text in
      var meaning = TKMMeaning()
      meaning.meaning = text
      meaning.type = .primary
      return meaning
    }
    subject.readings = (primary.map { ($0, true) } + alternate.map { ($0, false) })
      .map { text, primary in
        var reading = TKMReading()
        reading.reading = text
        reading.isPrimary = primary
        return reading
      }
    return subject
  }

  private func check(_ answer: String, subject: TKMSubject? = nil, type: TaskType = .meaning,
                     materials: TKMStudyMaterials? = nil,
                     lookup: (Int64) -> TKMSubject? = { _ in nil }) -> AnswerChecker
    .AnswerCheckerResult {
    AnswerChecker.checkAnswer(answer, subject: subject ?? self.subject(), studyMaterials: materials,
                              taskType: type, subjectLookup: lookup)
  }

  func testMeaningSynonymsAndAuxiliaryWhitelist() {
    var item = subject()
    var whitelist = TKMMeaning()
    whitelist.meaning = "Single"
    whitelist.type = .auxiliaryWhitelist
    item.meanings.append(whitelist)
    var materials = TKMStudyMaterials()
    materials.meaningSynonyms = ["Unity"]
    XCTAssertEqual(check("one", subject: item), .precise)
    XCTAssertEqual(check("single", subject: item), .precise)
    XCTAssertEqual(check("unity", subject: item, materials: materials), .precise)
  }

  func testBlacklistWinsEvenOverExactSynonym() {
    var item = subject()
    var blacklist = TKMMeaning()
    blacklist.meaning = "Won"
    blacklist.type = .blacklist
    item.meanings.append(blacklist)
    var materials = TKMStudyMaterials()
    materials.meaningSynonyms = ["Won"]
    XCTAssertEqual(check("won", subject: item, materials: materials), .incorrect)
  }

  func testMeaningTypoToleranceAndTransposition() {
    XCTAssertEqual(check("bnuny", subject: subject(meanings: ["Bunny"])), .imprecise)
    XCTAssertEqual(check("bunn", subject: subject(meanings: ["Bunny"])), .imprecise)
    XCTAssertEqual(check("bxxny", subject: subject(meanings: ["Bunny"])), .incorrect)
    XCTAssertEqual(check("oen"), .incorrect) // Three-letter meanings have no typo allowance.
  }

  func testPrimaryAndAlternateReadingSemantics() {
    XCTAssertEqual(check("いち", type: .reading), .precise)
    XCTAssertEqual(check("イチ", type: .reading), .precise)
    XCTAssertEqual(check("ひと", type: .reading), .otherKanjiReading)
    XCTAssertEqual(check("ひと", subject: subject(vocabulary: true), type: .reading), .precise)
    XCTAssertEqual(check("いぢ", type: .reading), .incorrect) // Reading typos are not accepted.
  }

  func testKatakanaSubjectPreservesLongVowel() {
    let item = subject("ビール", meanings: ["Beer"], primary: ["ビール"], alternate: [], vocabulary: true)
    XCTAssertEqual(check("びーる", subject: item, type: .reading), .precise)
    XCTAssertEqual(check("びる", subject: item, type: .reading), .incorrect)
  }

  func testSingleKanjiVocabularyConsultsItsComponent() {
    var item = subject("一", primary: ["ひとつ"], alternate: [], vocabulary: true)
    item.componentSubjectIds = [99]
    XCTAssertEqual(check("いち", subject: item, type: .reading, lookup: { id in
      XCTAssertEqual(id, 99)
      return self.subject()
    }), .otherKanjiReading)
    XCTAssertEqual(check("いち", subject: item, type: .reading), .incorrect)
  }

  func testInvalidScriptRanges() {
    XCTAssertEqual(check("ichい", type: .reading),
                   .containsInvalidCharacters([NSRange(location: 0, length: 3)]))
    XCTAssertEqual(check("a漢字b"), .containsInvalidCharacters([NSRange(location: 1, length: 2)]))
  }

  func testMismatchingOkuriganaIsNotAnOrdinaryWrongAnswer() {
    let item = subject("食べる", primary: ["たべる"], alternate: [], vocabulary: true)
    XCTAssertEqual(check("たべろ", subject: item, type: .reading),
                   .mismatchingOkurigana([NSRange(location: 2, length: 1)]))
    XCTAssertEqual(check("たべる", subject: item, type: .reading), .precise)
  }

  func testReadingEnteredForMeaningGetsSpecificFeedback() {
    XCTAssertEqual(check("ichi"), .isReadingButWantMeaning)
    XCTAssertEqual(check("hito"), .otherKanjiReading)
    XCTAssertEqual(check("not an answer"), .incorrect)
  }
}
