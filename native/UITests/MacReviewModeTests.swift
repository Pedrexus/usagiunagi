import XCTest

@MainActor
final class MacReviewModeTests: XCTestCase {
  private func launch(_ arguments: [String]) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["ReviewFixture"] + arguments
    app.launch()
    XCTAssertTrue(app.staticTexts["Reviews"].firstMatch.waitForExistence(timeout: 10))
    return app
  }
  private func showAnswer(in app: XCUIApplication) {
    let show = app.buttons["review.submit"]
    XCTAssertTrue(show.waitForExistence(timeout: 5))
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS %@", "Show answer"), object: show)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    XCTAssertFalse(app.textFields["review.answer"].exists)
    show.click()
    XCTAssertTrue(app.buttons["review.correct"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["review.incorrect"].exists)
  }
  func testCombinedAnkiPreservesTheRevealedCardAcrossNavigationAndCompletesBothSides() {
    let app = launch(["AnkiFixture", "CombinedAnkiFixture"])
    defer { app.terminate() }
    app.staticTexts["Reviews"].firstMatch.click()
    showAnswer(in: app)
    XCTAssertTrue(app.staticTexts["subject.meanings"].exists)
    app.staticTexts["Statistics"].firstMatch.click()
    app.staticTexts["Reviews"].firstMatch.click()
    let correct = app.buttons["review.correct"]
    XCTAssertTrue(correct.waitForExistence(timeout: 5))
    correct.click()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 5))
  }
  func testReadingOnlyAnkiLeavesMeaningTyped() {
    let app = launch(["AnkiFixture", "ReadingAnkiFixture"])
    defer { app.terminate() }
    app.staticTexts["Reviews"].firstMatch.click()
    let input = app.textFields["review.answer"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["review.prompt"].label, "Meaning")
    input.click()
    input.typeText("one")
    app.buttons["review.submit"].click()
    showAnswer(in: app)
    app.buttons["review.correct"].click()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 5))
  }
  func testIncorrectCombinedAnkiRequiresAnotherAssessment() {
    let app = launch(["AnkiFixture", "CombinedAnkiFixture"])
    defer { app.terminate() }
    app.staticTexts["Reviews"].firstMatch.click()
    showAnswer(in: app)
    app.buttons["review.incorrect"].click()
    showAnswer(in: app)
    app.buttons["review.correct"].click()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "66% accuracy")).firstMatch
        .exists)
  }
  func testSessionModeCanBeConfiguredBeforeOpeningReviews() {
    let app = launch([])
    defer { app.terminate() }
    app.staticTexts["Review settings"].firstMatch.click()
    let mode = app.popUpButtons["reviewSettings.answerMode"]
    XCTAssertTrue(mode.waitForExistence(timeout: 5))
    mode.click()
    app.menuItems["Anki: meaning and reading"].click()
    let combine = app.checkBoxes["reviewSettings.combineAnki"]
    XCTAssertTrue(combine.waitForExistence(timeout: 5))
    combine.click()
    app.staticTexts["Reviews"].firstMatch.click()
    showAnswer(in: app)
    app.buttons["review.correct"].click()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 5))
  }
}
