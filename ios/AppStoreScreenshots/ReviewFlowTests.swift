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
  func testCoverageStaysInlineAcrossChartTapsFiltersAndTabChanges() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "ShowStatistics", "ShowCoverage"]
    app.launch()
    defer { clearFixture(app) }
    let row = app.buttons["coverage.target.N5"]
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    if !row.isHittable { app.swipeUp() }
    let remaining = app.staticTexts["coverage.remaining.N5"]
    XCTAssertFalse(remaining.exists)
    let chart = app.descendants(matching: .any).matching(identifier: "coverage.chart").firstMatch
    XCTAssertTrue(chart.exists)
    chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.25)).tap()
    chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.75)).tap()
    XCTAssertFalse(remaining.exists)
    XCTAssertFalse(app.navigationBars["N5"].exists)
    row.tap()
    XCTAssertTrue(remaining.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Stats"].firstMatch.isHittable)
    XCTAssertFalse(app.buttons["Done"].exists)
    let expanded = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    expanded.name = "Inline offline curriculum coverage"
    expanded.lifetime = .keepAlways
    add(expanded)
    row.tap()
    XCTAssertFalse(remaining.exists)
    app.swipeDown()
    app.buttons["coverage.threshold"].tap()
    app.buttons["Burned"].tap()
    XCTAssertTrue(row.label.contains("at Burned"))
    app.buttons["coverage.system"].tap()
    app.buttons["School grades"].tap()
    XCTAssertTrue(app.buttons["coverage.target.grade1"].waitForExistence(timeout: 5))
    XCTAssertFalse(remaining.exists)
    app.buttons["Home"].firstMatch.tap()
    app.buttons["Stats"].firstMatch.tap()
    XCTAssertTrue(app.buttons["coverage.target.grade1"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Done"].exists)
    XCTAssertFalse(app.navigationBars["N5"].exists)
  }

  @MainActor
  func testUpcomingReviewsShowsStageAndSubjectCountsAndReturns() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES"]
    app.launch()
    defer { clearFixture(app) }
    let forecast = app.cells.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Upcoming reviews:")
    ).firstMatch
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
      let answer =
        app.staticTexts["review.prompt"].label.contains("Reading") ? "watashijishin" : "personally"
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
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews")).firstMatch
        .waitForExistence(timeout: 5))
  }

  @MainActor
  private func launchPractice(anki: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-FASTLANE_SNAPSHOT", "YES", "-ankiMode", anki ? "YES" : "NO",
      "-ankiModeTaskType", "2", "-autoSwitchKeyboard", "NO",
      "-playAudioAutomatically", "NO", "-allowSkippingReviews", "NO",
    ]
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
    let next = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
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
    let next = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
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
    startReviews(in: app)
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
    for _ in 0..<5 {
      let previousQuestion = question.value as? String ?? ""
      let previousPrompt = prompt.label
      let answer = previousPrompt.contains("Reading") ? "watashijishin" : meanings[previousQuestion]
      XCTAssertNotNil(answer, "Unexpected sample question: \(previousQuestion), \(previousPrompt)")
      field.tap()
      field.typeText(answer!)
      app.buttons["review.submit"].tap()
      let changed = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          summary.exists || (question.value as? String != previousQuestion)
            || prompt
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
    startReviews(in: app)
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
    let reading = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        prompt.exists && prompt.label.contains("Reading")
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [reading], timeout: 5), .completed)
    app.buttons["review.voice"].tap()
    XCTAssertTrue(app.buttons["voice.start"].waitForExistence(timeout: 5))
    app.buttons["voice.start"].tap()
    XCTAssertTrue(app.buttons["voice.stop"].waitForExistence(timeout: 5))
    app.buttons["voice.stop"].tap()
    XCTAssertTrue(app.buttons["voice.submit"].waitForExistence(timeout: 5))
    XCTAssertFalse(
      app.buttons["voice.submit"]
        .isEnabled)  // Kanji transcription is not a reading answer.
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
    app.launchArguments =
      [
        "-FASTLANE_SNAPSHOT", "YES", "SingleReviewFixture",
        "-groupMeaningReading", "YES", "-meaningFirst", "YES", "-ankiMode", "NO",
        "-autoSwitchKeyboard", "NO", "-playAudioAutomatically", "NO",
        "-allowSkippingReviews", "NO", "-showAnswerImmediately", "NO",
        "-enableCheats", "YES",
      ] + extra
    app.launch()
    startReviews(in: app)
    XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 10))
    return app
  }

  @MainActor
  private func startReviews(in app: XCUIApplication) {
    let table = app.tables.firstMatch
    XCTAssertTrue(table.waitForExistence(timeout: 10))
    let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    // A self-sizing home row can leave the control outside the visible table.
    // Xcode's automatic scroll-to-tap can lose its button snapshot on iOS 27.
    for _ in 0..<5 {
      if start.exists && start.isHittable { break }
      table.swipeDown()
    }
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertTrue(start.isHittable)
    start.tap()
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
    defer {
      XCUIDevice.shared.orientation = .portrait
      clearFixture(app)
    }
    XCUIDevice.shared.orientation = .landscapeLeft
    let rotated = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
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
    let reading = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
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

extension ReviewFlowTests {
  @MainActor
  private func launchLessonPicker() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-FASTLANE_SNAPSHOT", "YES", "LessonFlowFixture",
      "-groupMeaningReading", "YES", "-meaningFirst", "YES", "-ankiMode", "NO",
      "-autoSwitchKeyboard", "NO", "-playAudioAutomatically", "NO",
      "-allowSkippingReviews", "NO", "-showAnswerImmediately", "NO",
      "-enableCheats", "YES",
    ]
    app.launch()
    let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Choose lessons"))
      .firstMatch
    XCTAssertTrue(choose.waitForExistence(timeout: 10))
    choose.tap()
    XCTAssertTrue(app.buttons["lesson.startSelection"].waitForExistence(timeout: 5))
    return app
  }

  @MainActor
  private func expectLessonPage(_ label: String, in app: XCUIApplication) {
    let page = app.staticTexts["lesson.position"]
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS %@", label), object: page)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
  }

  @MainActor
  func testLessonPickerPreservesSelectionAndUnfinishedQuizDraft() {
    continueAfterFailure = false
    let app = launchLessonPicker()
    defer { clearFixture(app) }
    XCTAssertFalse(app.buttons["lesson.startSelection"].isEnabled)
    let radical = app.buttons["lesson.select.293"]
    radical.tap()
    XCTAssertEqual(radical.value as? String, "Selected")
    radical.tap()
    XCTAssertEqual(radical.value as? String, "Not selected")
    app.buttons["lesson.select.3864"].tap()
    XCTAssertEqual(app.staticTexts["lesson.selectionCount"].label, "1 selected")
    let picker = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    picker.name = "SwiftUI lesson picker"
    picker.lifetime = .keepAlways
    add(picker)
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    let teaching = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    teaching.name = "SwiftUI lesson navigation"
    teaching.lifetime = .keepAlways
    add(teaching)
    app.buttons["lesson.quiz"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("pers")
    app.buttons["lesson.page.0"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    app.buttons["lesson.quiz"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "pers")
    let quiz = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    quiz.name = "SwiftUI lessons retain quiz draft"
    quiz.lifetime = .keepAlways
    add(quiz)
    app.buttons["lesson.back"].tap()
    XCTAssertTrue(app.buttons["lesson.select.3864"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["lesson.selectionCount"].label, "1 selected")
  }

  @MainActor
  func testLessonQuizPreservesWrongAnswerRulesAndCompletesTheSelectedLesson() {
    continueAfterFailure = false
    let app = launchLessonPicker()
    defer { clearFixture(app) }
    app.buttons["lesson.select.3864"].tap()
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    app.buttons["lesson.quiz"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("banana")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    app.buttons["review.reveal"].tap()
    XCTAssertFalse(app.buttons["review.correct"].exists)
    app.buttons["review.submit"].tap()
    let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Choose lessons"))
      .firstMatch
    for _ in 0..<4 {
      if choose.exists { break }
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      let answer =
        app.staticTexts["review.prompt"].label.contains("Reading") ? "watashijishin" : "personally"
      field.tap()
      field.typeText(answer)
      app.buttons["review.submit"].tap()
    }
    XCTAssertTrue(choose.waitForExistence(timeout: 5))
    choose.tap()
    XCTAssertTrue(app.buttons["lesson.select.293"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["lesson.select.3864"].exists)
    XCTAssertFalse(app.buttons["lesson.startSelection"].isEnabled)
  }

  @MainActor
  func testLessonNavigationSupportsPagesSwipesAndReturningFromQuiz() {
    continueAfterFailure = false
    let app = launchLessonPicker()
    defer { clearFixture(app) }
    for id in [293, 743, 3864] { app.buttons["lesson.select.\(id)"].tap() }
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 3", in: app)
    XCTAssertEqual(app.buttons["lesson.page.0"].value as? String, "Selected")
    app.buttons["lesson.page.1"].tap()
    expectLessonPage("Lesson 2 of 3", in: app)
    app.buttons["lesson.page.0"].tap()
    expectLessonPage("Lesson 1 of 3", in: app)
    app.buttons["lesson.page.2"].tap()
    expectLessonPage("Lesson 3 of 3", in: app)
    app.swipeRight()
    expectLessonPage("Lesson 2 of 3", in: app)
    app.buttons["lesson.quiz"].tap()
    expectLessonPage("Quiz", in: app)
    XCTAssertEqual(app.buttons["lesson.quiz"].value as? String, "Selected")
    app.buttons["lesson.page.2"].tap()
    expectLessonPage("Lesson 3 of 3", in: app)
    app.buttons["lesson.back"].tap()
    XCTAssertTrue(app.buttons["lesson.startSelection"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["lesson.selectionCount"].label, "3 selected")
  }
}

extension ReviewFlowTests {
  @MainActor
  private func revealIncorrectMeaning(in app: XCUIApplication) {
    XCTAssertTrue(app.staticTexts["review.prompt"].label.contains("Meaning"))
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("banana")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    app.buttons["review.reveal"].tap()
  }

  @MainActor
  private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
    let keyboardDone = app.buttons["material.keyboardDone"]
    if keyboardDone.exists && keyboardDone.isHittable { keyboardDone.tap() }
    for _ in 0..<16 {
      if element.exists && element.isHittable { return }
      let details = app.scrollViews["subject.scroll"]
      let form = app.descendants(matching: .any).matching(identifier: "material.form").firstMatch
      if form.exists && form.isHittable {
        if element.exists && element.frame.midY < form.frame.minY {
          form.swipeDown(velocity: .slow)
        } else {
          form.swipeUp(velocity: .slow)
        }
      } else if details.exists && details.isHittable {
        if towardTop || element.exists && element.frame.midY < details.frame.minY {
          details.swipeDown(velocity: .slow)
        } else {
          details.swipeUp(velocity: .slow)
        }
      } else {
        app.swipeUp()
      }
    }
    let hierarchy = XCTAttachment(string: app.debugDescription)
    hierarchy.name = "Unreachable detail control"
    hierarchy.lifetime = .keepAlways
    add(hierarchy)
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Unreachable detail control screen"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    XCTAssertTrue(element.exists && element.isHittable)
  }

  @MainActor
  private func openMaterialEditor(in app: XCUIApplication) {
    let edit = app.buttons["subject.editMaterial"]
    scrollTo(edit, in: app, towardTop: true)
    edit.tap()
    XCTAssertTrue(app.buttons["material.save"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testLessonDetailsSaveNotesAndSynonymsUsedByTheQuiz() {
    continueAfterFailure = false
    let app = launchLessonPicker()
    defer { clearFixture(app) }
    app.buttons["lesson.select.3864"].tap()
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    openMaterialEditor(in: app)
    let note = app.textViews["material.meaningNote"]
    note.tap()
    note.typeText("My personal meaning note")
    let addSynonym = app.buttons["material.addSynonym"]
    scrollTo(addSynonym, in: app)
    addSynonym.tap()
    let synonym = app.descendants(matching: .any).matching(identifier: "material.synonym")
      .firstMatch
    scrollTo(synonym, in: app)
    synonym.tap()
    synonym.typeText("custompersonal")
    app.buttons["material.save"].tap()
    XCTAssertFalse(app.buttons["material.save"].waitForExistence(timeout: 2))
    openMaterialEditor(in: app)
    XCTAssertEqual(note.value as? String, "My personal meaning note")
    XCTAssertEqual(synonym.value as? String, "custompersonal")
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "Shared SwiftUI notes and synonyms editor"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["material.cancel"].tap()
    app.buttons["lesson.quiz"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("custompersonal")
    app.buttons["review.submit"].tap()
    let reading = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS %@", "Reading"),
      object: app.staticTexts["review.prompt"])
    XCTAssertEqual(XCTWaiter.wait(for: [reading], timeout: 5), .completed)
  }

  @MainActor
  func testReviewDetailsConcealUnansweredReadingAndBlurTranslations() {
    continueAfterFailure = false
    let app = launchSingleReview(extra: ["-blurContextSentences", "YES"])
    defer { clearFixture(app) }
    revealIncorrectMeaning(in: app)
    let reading = app.descendants(matching: .any).matching(identifier: "subject.readingExplanation")
      .firstMatch
    XCTAssertFalse(reading.exists)
    openMaterialEditor(in: app)
    XCTAssertFalse(app.textViews["material.readingNote"].exists)
    app.buttons["material.cancel"].tap()
    app.buttons["All information"].tap()
    XCTAssertTrue(reading.waitForExistence(timeout: 5))
    let translation = app.buttons["subject.translation.0"]
    scrollTo(translation, in: app)
    let english = app.staticTexts["Personally, I'm indifferent to the zoo's issues."]
    XCTAssertFalse(english.exists)
    translation.tap()
    XCTAssertTrue(english.waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "Shared SwiftUI review details and sentence translation"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testMaterialConflictRetainsDraftAndHiddenNoteUntilExplicitReplacement() {
    continueAfterFailure = false
    let app = launchSingleReview(extra: ["MaterialConflictFixture"])
    defer { clearFixture(app) }
    revealIncorrectMeaning(in: app)
    openMaterialEditor(in: app)
    let note = app.textViews["material.meaningNote"]
    note.tap()
    note.typeText("My draft survives")
    app.buttons["material.save"].tap()
    XCTAssertTrue(app.buttons["material.save"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["material.save"].isEnabled)
    XCTAssertEqual(note.value as? String, "My draft survives")
    XCTAssertFalse(app.textViews["material.readingNote"].exists)
    let replace = app.buttons["Replace saved version with my draft"]
    scrollTo(replace, in: app)
    replace.tap()
    XCTAssertTrue(app.buttons["Replace with my draft"].waitForExistence(timeout: 5))
    app.buttons["Replace with my draft"].tap()
    XCTAssertFalse(app.buttons["material.save"].waitForExistence(timeout: 2))
    app.buttons["All information"].tap()
    let hiddenNote = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Concurrent hidden reading note")
    ).firstMatch
    scrollTo(hiddenNote, in: app)
    XCTAssertTrue(hiddenNote.exists)
    openMaterialEditor(in: app)
    XCTAssertTrue(app.staticTexts["Excluded from lessons and reviews"].exists)
    XCTAssertEqual(note.value as? String, "My draft survives")
    XCTAssertEqual(
      app.textViews["material.readingNote"].value as? String, "Concurrent hidden reading note")
    app.buttons["material.cancel"].tap()
  }
}
