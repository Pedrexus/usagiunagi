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
  func testUpcomingReviewsShowsStageAndSubjectCountsAndReturns() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES"]
    app.launch()
    defer { clearFixture(app) }
    let forecast = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Upcoming reviews:")).firstMatch
    XCTAssertTrue(forecast.waitForExistence(timeout: 10))
    let due = try XCTUnwrap(forecast.label.split(separator: ":").last?.split(separator: " ").first)
    forecast.tap()
    XCTAssertTrue(app.navigationBars["Upcoming Reviews"].waitForExistence(timeout: 5))
    let hour = app.descendants(matching: .any).matching(identifier: "schedule.hour.0").firstMatch
    XCTAssertTrue(hour.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["\(due) reviews · +\(due) this hour"].exists)
    hour.tap()
    XCTAssertTrue(app.staticTexts["Apprentice"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Guru"].exists)
    XCTAssertTrue(app.staticTexts["Radical"].exists)
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "SwiftUI upcoming review breakdown"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.navigationBars["Upcoming Reviews"].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(forecast.waitForExistence(timeout: 5))
  }

  @MainActor
  func testSummaryShowsMissedMeaningAndOpensSubjectDetails() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("banana")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    app.buttons["review.reveal"].tap()
    app.buttons["review.submit"].tap()
    let complete = app.staticTexts["Session complete"]
    for _ in 0..<3 {
      if complete.exists { break }
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      let answer = app.staticTexts["review.prompt"].label.contains("Reading") ? "watashijishin" : "personally"
      field.tap()
      field.typeText(answer)
      app.buttons["review.submit"].tap()
    }
    XCTAssertTrue(complete.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Missed items"].exists)
    let missed = app.buttons["summary.subject.0"]
    XCTAssertTrue(missed.waitForExistence(timeout: 5))
    XCTAssertTrue(missed.label.contains("Meaning missed"))
    XCTAssertFalse(missed.label.contains("Reading missed"))
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "SwiftUI missed-subject summary"
    attachment.lifetime = .keepAlways
    add(attachment)
    missed.tap()
    XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
    app.buttons["Back"].tap()
    XCTAssertTrue(missed.waitForExistence(timeout: 5))
    app.navigationBars["Review Summary"].buttons["Done"].tap()
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews")).firstMatch.waitForExistence(timeout: 5))
  }

  @MainActor
  private func launchPractice(anki: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "-ankiMode", anki ? "YES" : "NO",
                           "-ankiModeTaskType", "2", "-autoSwitchKeyboard", "NO",
                           "-playAudioAutomatically", "NO", "-allowSkippingReviews", "NO"]
    app.launch()
    let tab = app.tabBars.buttons["Practice"]
    XCTAssertTrue(tab.waitForExistence(timeout: 10))
    tab.tap()
    XCTAssertTrue(app.buttons["practice.katakana"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "Native SwiftUI practice menu"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["practice.katakana"].tap()
    XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 10))
    return app
  }

  @MainActor
  func testPracticeMenuPreservesTypedReviewsAndReturns() {
    continueAfterFailure = false
    let app = launchPractice()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["review.question"].value as? String, "ア")
    XCTAssertTrue(app.staticTexts["review.prompt"].label.contains("Reading"))
    field.tap()
    field.typeText("a")
    app.buttons["review.submit"].tap()
    let next = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      app.staticTexts["review.question"].value as? String == "イ"
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 5), .completed)
    field.tap()
    field.typeText("i")
    let draft = field.value as? String
    app.buttons["review.settings"].tap()
    XCTAssertTrue(app.buttons["reviewSettings.done"].waitForExistence(timeout: 5))
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, draft)
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 5))
    app.navigationBars["Review Summary"].buttons["Done"].tap()
    XCTAssertTrue(app.buttons["practice.katakana"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testPracticeMenuPreservesAnkiReadingMode() {
    continueAfterFailure = false
    let app = launchPractice(anki: true)
    defer { clearFixture(app) }
    XCTAssertFalse(app.textFields["review.answer"].exists)
    XCTAssertFalse(app.buttons["review.voice"].exists)
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.correct"].waitForExistence(timeout: 5))
    app.buttons["review.correct"].tap()
    let next = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      app.staticTexts["review.question"].value as? String == "イ"
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 5), .completed)
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 5))
    app.navigationBars["Review Summary"].buttons["Done"].tap()
    XCTAssertTrue(app.buttons["practice.katakana"].waitForExistence(timeout: 5))
  }

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

  @MainActor
  func testQuickSettingsPreservesDraftAndAppliesExactMatch() {
    continueAfterFailure = false
    let app = launchSingleReview(extra: ["-exactMatch", "NO"])
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("personaly")
    app.buttons["review.settings"].tap()
    let exact = app.switches["reviewSettings.exactMatch"]
    XCTAssertTrue(exact.waitForExistence(timeout: 5))
    XCTAssertEqual(exact.value as? String, "0")
    exact.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    XCTAssertEqual(exact.value as? String, "1")
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "SwiftUI quick settings"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, "personaly")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["review.feedback"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["review.feedback"].label, "Use the exact meaning.")
    app.buttons["review.settings"].tap()
    XCTAssertTrue(exact.waitForExistence(timeout: 5))
    XCTAssertEqual(exact.value as? String, "1")
    exact.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    XCTAssertEqual(exact.value as? String, "0")
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, "personaly")
    app.buttons["review.submit"].tap()
    let reading = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      app.staticTexts["review.prompt"].label.contains("Reading")
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [reading], timeout: 5), .completed)
    field.tap()
    field.typeText("watashijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testWrapUpCanBeStoppedAndCompleted() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("personally")
    app.buttons["review.submit"].tap()
    app.buttons["review.close"].tap()
    let wrap = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wrap up ("))
      .firstMatch
    XCTAssertTrue(wrap.waitForExistence(timeout: 5))
    wrap.tap()
    XCTAssertTrue(app.staticTexts["Wrapping up"].waitForExistence(timeout: 5))
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.buttons["Stop wrapping up"].waitForExistence(timeout: 5))
    app.buttons["Stop wrapping up"].tap()
    XCTAssertFalse(app.staticTexts["Wrapping up"].exists)
    app.buttons["review.close"].tap()
    XCTAssertTrue(wrap.waitForExistence(timeout: 5))
    wrap.tap()
    field.tap()
    field.typeText("watashijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testFontLibraryReturnsToDraftAndUnstartedReviewCanClose() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("personally")
    app.buttons["review.settings"].tap()
    XCTAssertTrue(app.buttons["reviewSettings.fonts"].waitForExistence(timeout: 5))
    app.buttons["reviewSettings.fonts"].tap()
    let navigation = app.navigationBars["Select Fonts"]
    XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    navigation.buttons.firstMatch.tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "personally")
    app.buttons["review.close"].tap()
    let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 5))
  }

  @MainActor
  func testExplicitEndDiscardsOnlyTheUnfinishedSession() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("personally")
    app.buttons["review.submit"].tap()
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.buttons["End review session"].waitForExistence(timeout: 5))
    app.buttons["End review session"].tap()
    let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Session complete"].exists)
  }
}
