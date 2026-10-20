// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import SwiftUI
import Testing
import UIKit

@testable import StudyCore
@testable import StudyUI

@MainActor struct TKMKanaInputTest {
  private final class MarkedTextField: UITextField {
    override var markedTextRange: UITextRange? {
      textRange(from: beginningOfDocument, to: endOfDocument)
    }
  }
  private func input(
    reading: Bool = true, editable: Bool = true,
    alphabet: KanaAlphabet = .hiragana,
    submitted: @escaping () -> Void = {}, retried: @escaping () -> Void = {}
  )
    -> StudyAnswerInput.Coordinator
  {
    StudyAnswerInput(
      prompt: "Answer", text: .constant(""), focused: .constant(false),
      reading: reading, automaticJapanese: false, editable: editable,
      alphabet: alphabet, submitted: submitted, retried: retried
    ).makeCoordinator()
  }
  private func cursor(_ field: UITextField) throws -> Int {
    let selection = try #require(field.selectedTextRange)
    return field.offset(from: field.beginningOfDocument, to: selection.start)
  }

  @Test func testDisabledInputAndDeletionPassThrough() {
    let coordinator = input(reading: false)
    let field = UITextField()
    field.text = "かな"
    #expect(
      coordinator.textField(
        field, shouldChangeCharactersIn: NSRange(location: 2, length: 0),
        replacementString: "a"))
    #expect(field.text == "かな")
    coordinator.parent = input().parent
    #expect(
      coordinator.textField(
        field, shouldChangeCharactersIn: NSRange(location: 0, length: 2),
        replacementString: ""))
    #expect(field.text == "かな")
  }
  @Test func testEveryRomanizationPattern() throws {
    let coordinator = input()
    let field = UITextField()
    #expect(KanaConverter.replacements.count == 290)
    for (roman, kana) in KanaConverter.replacements where roman != "n " {
      field.text = String(roman.dropLast())
      #expect(
        !coordinator.textField(
          field,
          shouldChangeCharactersIn: NSRange(location: roman.utf16.count - 1, length: 0),
          replacementString: String(roman.suffix(1))), "\(roman)")
      #expect(field.text == kana, "\(roman)")
      #expect(try cursor(field) == kana.utf16.count, "\(roman)")
    }
  }
  @Test func testLowercaseAndUppercaseDoubledConsonants() {
    let coordinator = input()
    let field = UITextField()
    for letter in "bcdfghjklpqrstvwxyz".map(String.init) {
      for (character, kana) in [(letter, "っ"), (letter.uppercased(), "ッ")] {
        field.text = character
        #expect(
          coordinator.textField(
            field, shouldChangeCharactersIn: NSRange(location: 1, length: 0),
            replacementString: character))
        #expect(field.text == kana)
      }
    }
  }
  @Test func testLowercaseAndUppercaseNasalBeforeConsonant() {
    let coordinator = input()
    let field = UITextField()
    for consonant in "bcdfghjklmpqrstvwxz".map(String.init) {
      for (nasal, kana) in [("n", "ん"), ("m", "ん"), ("N", "ン"), ("M", "ン")] {
        field.text = nasal
        #expect(
          coordinator.textField(
            field, shouldChangeCharactersIn: NSRange(location: 1, length: 0),
            replacementString: consonant))
        #expect(field.text == kana)
      }
    }
  }
  @Test func testKatakanaAlphabetAndSelectedVowel() throws {
    let coordinator = input(alphabet: .katakana)
    let field = UITextField()
    field.text = "かな"
    #expect(
      !coordinator.textField(
        field, shouldChangeCharactersIn: NSRange(location: 0, length: 2),
        replacementString: "a"))
    #expect(field.text == "ア")
    #expect(try cursor(field) == 1)
    field.text = "ky"
    #expect(
      !coordinator.textField(
        field, shouldChangeCharactersIn: NSRange(location: 2, length: 0),
        replacementString: "a"))
    #expect(field.text == "キャ")
    #expect(try cursor(field) == 2)
  }
  @Test func testPastePlacesCursorAfterAllInsertedKana() throws {
    let coordinator = input()
    let field = UITextField()
    field.text = "😀い"
    #expect(
      !coordinator.textField(
        field, shouldChangeCharactersIn: NSRange(location: 2, length: 0),
        replacementString: "kya"))
    #expect(field.text == "😀きゃい")
    #expect(try cursor(field) == 4)
  }
  @Test func testReadOnlyInputVetoAndReturnReachTheNativeCallbacks() {
    var submissions = 0
    var retries = 0
    let coordinator = input(
      editable: false, submitted: { submissions += 1 }, retried: { retries += 1 })
    let field = UITextField()
    field.text = "k"
    #expect(
      !coordinator.textField(
        field, shouldChangeCharactersIn: NSRange(location: 1, length: 0),
        replacementString: "a"))
    #expect(field.text == "k" && retries == 0)
    #expect(
      !coordinator.textField(
        field, shouldChangeCharactersIn: NSRange(location: 0, length: 1),
        replacementString: ""))
    #expect(field.text == "k" && retries == 1)
    #expect(!coordinator.textFieldShouldReturn(field))
    #expect(submissions == 1)
  }
  @Test func testLockedAdapterCutPreservesSelectionAndActualBackspaceRetries() throws {
    var retries = 0
    let coordinator = input(editable: false, retried: { retries += 1 })
    let field = StudyJapaneseTextField()
    field.delegate = coordinator
    let original = "かな😀"
    field.text = original
    field.selectedTextRange = field.textRange(
      from: field.beginningOfDocument, to: field.endOfDocument)
    field.cut(nil)
    #expect(field.text == original)
    #expect(retries == 0)
    let selection = try #require(field.selectedTextRange)
    #expect(field.offset(from: field.beginningOfDocument, to: selection.start) == 0)
    #expect(
      field.offset(from: field.beginningOfDocument, to: selection.end) == original.utf16.count)
    field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
    field.deleteBackward()
    #expect(field.text == original)
    #expect(retries == 1)
    coordinator.parent = input(editable: true, retried: { retries += 1 }).parent
    field.text = "かな"
    field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
    field.deleteBackward()
    #expect(field.text == "か")
    #expect(retries == 1)
  }

  @Test func testMarkedTextIsLeftToTheInputMethod() {
    var submissions = 0
    let coordinator = input(submitted: { submissions += 1 })
    let field = MarkedTextField()
    field.text = "k"
    #expect(field.markedTextRange != nil)
    #expect(
      coordinator.textField(
        field, shouldChangeCharactersIn: NSRange(location: 1, length: 0),
        replacementString: "a"))
    #expect(field.text == "k")
    #expect(!coordinator.textFieldShouldReturn(field) && submissions == 0)
  }
}
