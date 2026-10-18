import XCTest

@MainActor
final class MacReviewModeTests: XCTestCase {
  private func launch(_ arguments: [String]) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--review-fixture"] + arguments
    app.launch()
    app.activate()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "home.reviews").firstMatch
        .waitForExistence(timeout: 10), app.debugDescription)
    return app
  }
  private func showAnswer(in app: XCUIApplication) {
    let show = app.buttons["review.submit"]
    XCTAssertTrue(show.waitForExistence(timeout: 5), app.debugDescription)
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS %@", "Show answer"), object: show)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    XCTAssertFalse(app.textFields["review.answer"].exists)
    show.click()
    XCTAssertTrue(app.buttons["review.correct"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["review.incorrect"].exists)
  }
  func testCombinedAnkiPreservesTheRevealedCardAcrossNavigationAndCompletesBothSides() {
    let app = launch(["--anki-fixture", "--combined-anki-fixture"])
    defer { app.terminate() }
    app.descendants(matching: .any).matching(identifier: "home.reviews").firstMatch.click()
    showAnswer(in: app)
    XCTAssertTrue(app.staticTexts["subject.meanings"].exists)
    app.pauseStudyAndReturn()
    let correct = app.buttons["review.correct"]
    XCTAssertTrue(correct.waitForExistence(timeout: 5))
    correct.click()
    XCTAssertTrue(
      app.staticTexts["Review session saved"].waitForExistence(timeout: 5), app.debugDescription)
  }
  func testReadingOnlyAnkiLeavesMeaningTyped() {
    let app = launch(["--anki-fixture", "--reading-anki-fixture"])
    defer { app.terminate() }
    app.descendants(matching: .any).matching(identifier: "home.reviews").firstMatch.click()
    let input = app.textFields["review.answer"]
    XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(app.staticTexts["review.prompt"].value as? String, "Meaning")
    input.click()
    input.typeText("one")
    app.buttons["review.submit"].click()
    showAnswer(in: app)
    app.buttons["review.correct"].click()
    XCTAssertTrue(
      app.staticTexts["Review session saved"].waitForExistence(timeout: 5), app.debugDescription)
  }
  func testIncorrectCombinedAnkiRequiresAnotherAssessment() {
    let app = launch(["--anki-fixture", "--combined-anki-fixture"])
    defer { app.terminate() }
    app.descendants(matching: .any).matching(identifier: "home.reviews").firstMatch.click()
    showAnswer(in: app)
    app.buttons["review.incorrect"].click()
    showAnswer(in: app)
    app.buttons["review.correct"].click()
    XCTAssertTrue(
      app.staticTexts["Review session saved"].waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(
          format: "label CONTAINS %@ OR value CONTAINS %@", "66% accuracy", "66% accuracy")
      ).firstMatch
        .exists)
  }
  func testSessionModeCanBeConfiguredBeforeOpeningReviews() {
    let app = launch([])
    defer { app.terminate() }
    app.buttons["app.settings"].click()
    let settings = app.buttons["Review settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.click()
    let mode = app.popUpButtons["reviewSettings.answerMode"]
    XCTAssertTrue(mode.waitForExistence(timeout: 5), app.debugDescription)
    mode.click()
    app.menuItems["Anki: meaning and reading"].click()
    let combine = app.switches["reviewSettings.combineAnki"]
    XCTAssertTrue(combine.waitForExistence(timeout: 5))
    combine.click()
    XCTAssertEqual((combine.value as? NSNumber)?.intValue, 1)
    app.buttons["Done"].click()
    app.descendants(matching: .any).matching(identifier: "home.reviews").firstMatch.click()
    showAnswer(in: app)
    app.buttons["review.correct"].click()
    XCTAssertTrue(
      app.staticTexts["Review session saved"].waitForExistence(timeout: 5), app.debugDescription)
  }
  func testExtraStudyCompletesWithoutChangingScheduledReviews() throws {
    let app = launch([])
    defer { app.terminate() }
    let practice = app.buttons["home.extra.recentLessons"]
    XCTAssertTrue(practice.waitForExistence(timeout: 5))
    practice.click()
    for _ in 0..<2 {
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
      let prompt = try XCTUnwrap(app.staticTexts["review.prompt"].value as? String)
      input.click()
      input.typeText(prompt == "Reading" ? "ichi" : "one")
      app.buttons["review.submit"].click()
    }
    XCTAssertTrue(app.staticTexts["Practice complete"].waitForExistence(timeout: 5))
    app.buttons["Finish session"].click()
    let reviews = app.buttons["home.reviews"]
    XCTAssertTrue(reviews.waitForExistence(timeout: 5))
    XCTAssertTrue(reviews.isEnabled && reviews.label.contains("1 ready"))
    XCTAssertFalse(app.staticTexts["home.notice"].exists)
  }
  func testHomeForecastAndSavedSubjectSearchOpenNativeScreens() {
    let app = launch([])
    defer { app.terminate() }
    app.buttons["home.forecast"].click()
    let hour = app.descendants(matching: .any).matching(identifier: "schedule.hour.0").firstMatch
    XCTAssertTrue(hour.waitForExistence(timeout: 5), app.debugDescription)
    app.toolbars.buttons["chevron.backward"].click()
    XCTAssertTrue(app.buttons["app.search"].waitForExistence(timeout: 5))
    app.buttons["app.search"].click()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.click()
    search.typeText("ichi")
    let subject = app.buttons["catalog.subject.1"]
    XCTAssertTrue(subject.waitForExistence(timeout: 5), app.debugDescription)
    subject.click()
    XCTAssertTrue(app.staticTexts["subject.meanings"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = "Native saved subject reached from Home"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
  func testFontSelectionAndDownloadsPreserveTheReviewDraft() {
    let app = launch([])
    defer { app.terminate() }
    app.buttons["home.reviews"].click()
    let input = app.textFields["review.answer"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.click()
    input.typeText("one")
    app.buttons["review.settings"].click()
    let fonts = app.buttons["reviewSettings.fonts"]
    XCTAssertTrue(fonts.waitForExistence(timeout: 5))
    fonts.click()
    let download = app.buttons["font.download.font-download.ttf"]
    XCTAssertTrue(download.waitForExistence(timeout: 5))
    download.click()
    let selection = app.switches["font.selection.font-download.ttf"]
    XCTAssertTrue(selection.waitForExistence(timeout: 12), app.debugDescription)
    XCTAssertEqual((selection.value as? NSNumber)?.intValue, 1)
    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = "Shared native font picker"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    let back = app.sheets.firstMatch.buttons["chevron.backward"]
    XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
    back.click()
    app.buttons["reviewSettings.done"].click()
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, "one")
    app.buttons["review.settings"].click()
    app.buttons["reviewSettings.fonts"].click()
    XCTAssertTrue(selection.waitForExistence(timeout: 5))
    XCTAssertEqual((selection.value as? NSNumber)?.intValue, 1)
  }
  func testFontFailuresCancelAndDeleteAreNativeAndRecoverable() {
    let app = launch([])
    defer { app.terminate() }
    app.buttons["app.settings"].click()
    app.buttons["Review settings"].click()
    let fonts = app.buttons["reviewSettings.fonts"]
    XCTAssertTrue(fonts.waitForExistence(timeout: 5))
    fonts.click()
    let held = app.buttons["font.download.font-held.ttf"]
    XCTAssertTrue(held.waitForExistence(timeout: 5))
    held.click()
    app.buttons["font.cancel.font-held.ttf"].click()
    XCTAssertTrue(held.waitForExistence(timeout: 5))
    let failed = app.buttons["font.download.font-failed.ttf"]
    failed.click()
    XCTAssertTrue(app.staticTexts["font.error.font-failed.ttf"].waitForExistence(timeout: 5))
    XCTAssertEqual(failed.label, "Retry")
    app.buttons["font.download.font-download.ttf"].click()
    let back = app.sheets.firstMatch.buttons["chevron.backward"]
    XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
    back.click()
    fonts.click()
    XCTAssertTrue(app.switches["font.selection.font-download.ttf"].waitForExistence(timeout: 12))
    let picker = app.sheets.firstMatch.scrollViews.firstMatch
    let delete = app.buttons["fonts.deleteAll"]
    for _ in 0..<5 {
      if delete.isHittable { break }
      picker.scroll(byDeltaX: 0, deltaY: -300)
    }
    delete.click()
    app.windows.firstMatch.buttons["Delete downloaded fonts"].click()
    XCTAssertTrue(app.buttons["font.download.font-download.ttf"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.switches["font.selection.font-download.ttf"].exists)
  }

}

extension XCUIApplication {
  func pauseStudyAndReturn() {
    let back = toolbars.buttons["chevron.backward"]
    XCTAssertTrue(back.waitForExistence(timeout: 5), debugDescription)
    back.click()
    XCTAssertTrue(buttons["home.resume"].waitForExistence(timeout: 5), debugDescription)
    openStudyTab("Stats")
    XCTAssertTrue(scrollViews["StudyDashboard"].waitForExistence(timeout: 5), debugDescription)
    openStudyTab("Home")
    let resume = buttons["home.resume"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    resume.click()
  }
  func openStudyTab(_ title: String) {

    let identifier = title == "Stats" ? "navigation.Statistics" : "navigation.\(title)"
    let tab = descendants(matching: .any).matching(identifier: identifier).firstMatch
    if tab.exists {
      tab.click()
    } else {
      let item = staticTexts.matching(NSPredicate(format: "value == %@", title)).firstMatch
      XCTAssertTrue(item.waitForExistence(timeout: 5), debugDescription)
      item.click()
    }
  }
}
