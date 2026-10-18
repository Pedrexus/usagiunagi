import XCTest

@MainActor
final class MacLessonTests: XCTestCase {
  private func launchQuiz() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--review-fixture", "--lesson-fixture"]
    app.launch()
    app.activate()
    let lessons = app.descendants(matching: .any).matching(identifier: "navigation.Lessons")
      .firstMatch
    XCTAssertTrue(lessons.waitForExistence(timeout: 10))
    lessons.click()
    let subject = app.buttons["lesson.select.1"]
    XCTAssertTrue(subject.waitForExistence(timeout: 5))
    subject.click()
    app.buttons["lesson.startSelection"].click()
    XCTAssertTrue(app.staticTexts["subject.meanings"].waitForExistence(timeout: 5))
    let teaching = XCTAttachment(screenshot: app.screenshot())
    teaching.name = "Native Mac lesson teaching"
    teaching.lifetime = .keepAlways
    add(teaching)
    app.buttons["lesson.quiz"].click()
    XCTAssertTrue(app.textFields["review.answer"].waitForExistence(timeout: 5))
    return app
  }
  private func answer(in app: XCUIApplication) throws {
    let prompt = try XCTUnwrap(app.staticTexts["review.prompt"].value as? String)
    let input = app.textFields["review.answer"]
    input.click()
    input.typeText(prompt == "Reading" ? "ichi" : "one")
    app.buttons["review.submit"].click()
  }
  func testTeachingQuizPauseResumeAndFinish() throws {
    let app = launchQuiz()
    defer { app.terminate() }
    let initialPrompt = try XCTUnwrap(app.staticTexts["review.prompt"].value as? String)
    try answer(in: app)
    let changed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value != %@", initialPrompt),
      object: app.staticTexts["review.prompt"])
    XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    app.descendants(matching: .any).matching(identifier: "navigation.Statistics").firstMatch.click()
    app.descendants(matching: .any).matching(identifier: "navigation.Lessons").firstMatch.click()
    let resume = app.buttons["Resume lesson quiz"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    resume.click()
    XCTAssertTrue(app.textFields["review.answer"].waitForExistence(timeout: 5))
    XCTAssertNotEqual(app.staticTexts["review.prompt"].value as? String, initialPrompt)
    try answer(in: app)
    XCTAssertTrue(app.staticTexts["Lesson quiz saved"].waitForExistence(timeout: 5))
    app.buttons["Finish session"].click()
    XCTAssertTrue(app.staticTexts["No lessons available"].waitForExistence(timeout: 5))
  }
  func testReviewEntryPreservesThePausedLessonQuiz() {
    let app = launchQuiz()
    defer { app.terminate() }
    app.descendants(matching: .any).matching(identifier: "navigation.Reviews").firstMatch.click()
    let warning = app.staticTexts.matching(
      NSPredicate(
        format: "label CONTAINS %@ OR value CONTAINS %@", "saved lesson quiz", "saved lesson quiz")
    ).firstMatch
    XCTAssertTrue(warning.waitForExistence(timeout: 5))
    app.descendants(matching: .any).matching(identifier: "navigation.Lessons").firstMatch.click()
    let resume = app.buttons["Resume lesson quiz"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    resume.click()
    XCTAssertTrue(app.textFields["review.answer"].waitForExistence(timeout: 5))
  }
}
