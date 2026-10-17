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

import XCTest

final class ReviewFlowTests: XCTestCase {
  @MainActor
  func testCompleteSampleReviewsThroughTypedAnswers() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-FASTLANE_SNAPSHOT",
      "YES",
      "-groupMeaningReading",
      "YES",
      "-meaningFirst",
      "YES",
      "-ankiMode",
      "NO",
      "-autoSwitchKeyboard",
      "NO",
      "-playAudioAutomatically",
      "NO",
      "-reviewItemsLimitEnabled",
      "NO",
      "-skipKanjiReadings",
      "NO",
      "-allowSkippingReviews",
      "NO",
    ]
    app.launch()
    defer {
      app.terminate()
      app.launchArguments.append("ResetUserDefaults")
      app.launch()
      app.terminate()
    }
    let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    let question = app.staticTexts["review.question"]
    let prompt = app.staticTexts["review.prompt"]
    let summary = app.staticTexts["Session complete"]
    let meanings = ["私自身": "personally", "私": "i", "自": "self", "身": "somebody"]
    for _ in 0 ..< 5 {
      let previousQuestion = question.value as? String ?? ""
      let previousPrompt = prompt.label
      let answer = previousPrompt.contains("Reading") ? "watashijishin" : meanings[previousQuestion]
      XCTAssertNotNil(answer, "Unexpected sample question: \(previousQuestion), \(previousPrompt)")
      field.tap()
      field.typeText(answer!)
      app.buttons["review.submit"].tap()
      let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        summary.exists || (question.value as? String != previousQuestion) || prompt
          .label != previousPrompt
      }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
      if summary.exists { break }
    }
    XCTAssertTrue(summary.waitForExistence(timeout: 10))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Completed sample review session"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testVoiceTranscriptUsesNormalGradingAndKanaFallback() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-FASTLANE_SNAPSHOT",
      "YES",
      "VoiceReviewFixture",
      "-groupMeaningReading",
      "YES",
      "-meaningFirst",
      "YES",
      "-ankiMode",
      "NO",
      "-autoSwitchKeyboard",
      "NO",
      "-playAudioAutomatically",
      "NO",
      "-allowSkippingReviews",
      "NO",
    ]
    app.launch()
    defer {
      app.terminate()
      app.launchArguments.append("ResetUserDefaults")
      app.launch()
      app.terminate()
    }
    let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    XCTAssertTrue(app.buttons["review.voice"].waitForExistence(timeout: 10))
    app.buttons["review.voice"].tap()
    XCTAssertTrue(app.buttons["voice.start"].waitForExistence(timeout: 5))
    app.buttons["voice.start"].tap()
    XCTAssertTrue(app.buttons["voice.stop"].waitForExistence(timeout: 5))
    app.buttons["voice.stop"].tap()
    XCTAssertTrue(app.buttons["voice.submit"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["voice.submit"].isEnabled)
    app.buttons["voice.submit"].tap()
    let prompt = app.staticTexts["review.prompt"]
    let reading = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      prompt.exists && prompt.label.contains("Reading")
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [reading], timeout: 5), .completed)
    app.buttons["review.voice"].tap()
    XCTAssertTrue(app.buttons["voice.start"].waitForExistence(timeout: 5))
    app.buttons["voice.start"].tap()
    XCTAssertTrue(app.buttons["voice.stop"].waitForExistence(timeout: 5))
    app.buttons["voice.stop"].tap()
    XCTAssertTrue(app.buttons["voice.submit"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["voice.submit"]
      .isEnabled) // Kanji transcription is not a reading answer.
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Voice reading correction"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["voice.keyboard"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("watashijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }
}
