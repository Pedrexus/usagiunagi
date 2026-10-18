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

@testable import StudyCore
import UIKit
import XCTest

@MainActor
final class TKMKanaInputTest: XCTestCase {
  private final class Delegate: NSObject, UITextFieldDelegate {
    var allowsChange = true
    var allowsReturn = false
    func textField(_: UITextField, shouldChangeCharactersIn _: NSRange,
                   replacementString _: String) -> Bool { allowsChange }
    func textFieldShouldReturn(_: UITextField) -> Bool { allowsReturn }
  }

  private final class MarkedTextField: UITextField {
    override var markedTextRange: UITextRange? {
      textRange(from: beginningOfDocument, to: endOfDocument)
    }
  }

  private func input(_ delegate: UITextFieldDelegate = Delegate()) -> TKMKanaInput {
    let input = TKMKanaInput(delegate: delegate)
    input.enabled = true
    return input
  }

  func testDisabledInputAndDeletionPassThrough() {
    let converter = input()
    let field = UITextField()
    field.text = "かな"
    converter.enabled = false
    XCTAssertTrue(converter.textField(field,
                                      shouldChangeCharactersIn: NSRange(location: 2, length: 0),
                                      replacementString: "a"))
    XCTAssertEqual(field.text, "かな")
    converter.enabled = true
    XCTAssertTrue(converter.textField(field,
                                      shouldChangeCharactersIn: NSRange(location: 0, length: 2),
                                      replacementString: ""))
    XCTAssertEqual(field.text, "かな")
  }

  func testEveryRomanizationPattern() {
    let converter = input()
    let field = UITextField()
    XCTAssertEqual(KanaConverter.replacements.count, 290)
    for (roman, kana) in KanaConverter.replacements where roman != "n " {
      field.text = String(roman.dropLast())
      XCTAssertFalse(converter
        .textField(field, shouldChangeCharactersIn: NSRange(location: roman.utf16.count - 1,
                                                            length: 0),
                   replacementString: String(roman.suffix(1))), roman)
      XCTAssertEqual(field.text, kana, roman)
      XCTAssertEqual(field
        .offset(from: field.beginningOfDocument, to: field.selectedTextRange!.start),
        kana.utf16.count, roman)
    }
  }

  func testLowercaseAndUppercaseDoubledConsonants() {
    let converter = input()
    let field = UITextField()
    for letter in "bcdfghjklpqrstvwxyz".map(String.init) {
      for (character, kana) in [(letter, "っ"), (letter.uppercased(), "ッ")] {
        field.text = character
        XCTAssertTrue(converter.textField(field,
                                          shouldChangeCharactersIn: NSRange(location: 1, length: 0),
                                          replacementString: character))
        XCTAssertEqual(field.text, kana)
      }
    }
  }

  func testLowercaseAndUppercaseNasalBeforeConsonant() {
    let converter = input()
    let field = UITextField()
    for consonant in "bcdfghjklmpqrstvwxz".map(String.init) {
      for (nasal, kana) in [("n", "ん"), ("m", "ん"), ("N", "ン"), ("M", "ン")] {
        field.text = nasal
        XCTAssertTrue(converter.textField(field,
                                          shouldChangeCharactersIn: NSRange(location: 1, length: 0),
                                          replacementString: consonant))
        XCTAssertEqual(field.text, kana)
      }
    }
  }

  func testKatakanaAlphabetAndSelectedVowel() {
    let converter = input()
    converter.alphabet = .katakana
    let field = UITextField()
    field.text = "かな"
    XCTAssertFalse(converter.textField(field,
                                       shouldChangeCharactersIn: NSRange(location: 0, length: 2),
                                       replacementString: "a"))
    XCTAssertEqual(field.text, "ア")
    XCTAssertEqual(field
      .offset(from: field.beginningOfDocument, to: field.selectedTextRange!.start),
      1)
    field.text = "ky"
    XCTAssertFalse(converter.textField(field,
                                       shouldChangeCharactersIn: NSRange(location: 2, length: 0),
                                       replacementString: "a"))
    XCTAssertEqual(field.text, "キャ")
  }

  func testPastePlacesCursorAfterAllInsertedKana() {
    let converter = input()
    let field = UITextField()
    field.text = "😀い"
    XCTAssertFalse(converter.textField(field,
                                       shouldChangeCharactersIn: NSRange(location: 2, length: 0),
                                       replacementString: "kya"))
    XCTAssertEqual(field.text, "😀きゃい")
    XCTAssertEqual(field
      .offset(from: field.beginningOfDocument, to: field.selectedTextRange!.start),
      4)
  }

  func testDelegateVetoAndReturnAreForwarded() {
    let delegate = Delegate()
    let converter = input(delegate)
    let field = UITextField()
    field.text = "k"
    delegate.allowsChange = false
    XCTAssertFalse(converter.textField(field,
                                       shouldChangeCharactersIn: NSRange(location: 1, length: 0),
                                       replacementString: "a"))
    XCTAssertEqual(field.text, "k")
    XCTAssertFalse(converter.textFieldShouldReturn(field))
    delegate.allowsReturn = true
    XCTAssertTrue(converter.textFieldShouldReturn(field))
  }

  func testMarkedTextIsLeftToTheInputMethod() {
    let converter = input()
    let field = MarkedTextField()
    field.text = "k"
    XCTAssertNotNil(field.markedTextRange)
    XCTAssertTrue(converter.textField(field,
                                      shouldChangeCharactersIn: NSRange(location: 1, length: 0),
                                      replacementString: "a"))
    XCTAssertEqual(field.text, "k")
  }
}
