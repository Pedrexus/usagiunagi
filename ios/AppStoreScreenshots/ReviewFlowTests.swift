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
    let initial = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    initial.name = "SwiftUI review question"
    initial.lifetime = .keepAlways
    add(initial)
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
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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

  @MainActor
  private func launchSingleReview(extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "SingleReviewFixture",
                           "-groupMeaningReading", "YES", "-meaningFirst", "YES", "-ankiMode", "NO",
                           "-autoSwitchKeyboard", "NO", "-playAudioAutomatically", "NO",
                           "-allowSkippingReviews", "NO", "-showAnswerImmediately", "NO",
                           "-enableCheats", "YES"] + extra
    app.launch()
    let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 10))
    return app
  }

  @MainActor
  private func clearFixture(_ app: XCUIApplication) {
    app.terminate()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "ResetUserDefaults"]
    app.launch()
    app.terminate()
  }

  @MainActor
  func testIncorrectAnswerRevealAndOverride() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("banana")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    app.buttons["review.reveal"].tap()
    XCTAssertTrue(app.buttons["review.corrections"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "SwiftUI incorrect answer details"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["review.corrections"].tap()
    app.buttons["My answer was correct"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("watashijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testCombinedAnkiIncorrectThenCorrectCompletesOneSubject() {
    continueAfterFailure = false
    let app = launchSingleReview(extra: [
      "-ankiMode",
      "YES",
      "-ankiModeCombineReadingMeaning",
      "YES",
    ])
    defer { clearFixture(app) }
    XCTAssertFalse(app.buttons["review.voice"].exists)
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.incorrect"].waitForExistence(timeout: 5))
    app.buttons["review.incorrect"].tap()
    XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 5))
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.correct"].waitForExistence(timeout: 5))
    app.buttons["review.correct"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testLandscapeReviewKeepsAnswerControlsAccessible() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { XCUIDevice.shared.orientation = .portrait
      clearFixture(app)
    }
    XCUIDevice.shared.orientation = .landscapeLeft
    let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("personally")
    XCTAssertTrue(app.buttons["review.submit"].isHittable)
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "SwiftUI landscape review"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["review.submit"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("watashijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }
}
