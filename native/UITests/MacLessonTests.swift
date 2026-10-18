import XCTest

@MainActor
final class MacLessonTests: XCTestCase {
  private func launchQuiz() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["ReviewFixture", "LessonFixture"]
    app.launch()
    let lessons = app.staticTexts["Lessons"].firstMatch
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
  private func answer(in app: XCUIApplication) {
    let prompt = app.staticTexts["review.prompt"].label
    let input = app.textFields["review.answer"]
    input.click()
    input.typeText(prompt == "Reading" ? "ichi" : "one")
    app.buttons["review.submit"].click()
  }
  func testTeachingQuizPauseResumeAndFinish() {
    let app = launchQuiz()
    defer { app.terminate() }
    let initialPrompt = app.staticTexts["review.prompt"].label
    answer(in: app)
    let changed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label != %@", initialPrompt),
      object: app.staticTexts["review.prompt"])
    XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    app.staticTexts["Statistics"].firstMatch.click()
    app.staticTexts["Lessons"].firstMatch.click()
    let resume = app.buttons["Resume lesson quiz"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    resume.click()
    XCTAssertTrue(app.textFields["review.answer"].waitForExistence(timeout: 5))
    XCTAssertNotEqual(app.staticTexts["review.prompt"].label, initialPrompt)
    answer(in: app)
    XCTAssertTrue(app.staticTexts["Lesson quiz saved"].waitForExistence(timeout: 5))
    app.buttons["Finish session"].click()
    XCTAssertTrue(app.staticTexts["No lessons available"].waitForExistence(timeout: 5))
  }
  func testReviewEntryPreservesThePausedLessonQuiz() {
    let app = launchQuiz()
    defer { app.terminate() }
    app.staticTexts["Reviews"].firstMatch.click()
    let warning = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "saved lesson quiz")
    ).firstMatch
    XCTAssertTrue(warning.waitForExistence(timeout: 5))
    app.staticTexts["Lessons"].firstMatch.click()
    let resume = app.buttons["Resume lesson quiz"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    resume.click()
    XCTAssertTrue(app.textFields["review.answer"].waitForExistence(timeout: 5))
  }
}
