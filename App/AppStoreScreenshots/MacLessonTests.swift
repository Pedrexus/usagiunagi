import XCTest

@MainActor
final class MacLessonTests: XCTestCase {
  private func launchQuiz() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "--review-fixture", "--lesson-fixture",
    ]
    app.launch()
    app.activate()
    let lessons = app.descendants(matching: .any).matching(identifier: "home.chooseLessons")
      .firstMatch
    XCTAssertTrue(lessons.waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["home.stage.1"].exists, app.debugDescription)
    let home = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    home.name = "Native WaniKani-inspired Home"
    home.lifetime = .keepAlways
    add(home)
    lessons.click()
    let subject = app.buttons["lesson.select.1"]
    XCTAssertTrue(subject.waitForExistence(timeout: 5))
    subject.click()
    app.buttons["lesson.startSelection"].click()
    XCTAssertTrue(app.staticTexts["subject.meanings"].waitForExistence(timeout: 5))
    let teaching = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    teaching.name = "Native Mac lesson teaching"
    teaching.lifetime = .keepAlways
    add(teaching)
    app.buttons["lesson.quiz"].click()
    XCTAssertTrue(
      app.textFields["review.answer"].waitForExistence(timeout: 5), app.debugDescription)
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
    app.pauseStudyAndReturn()
    XCTAssertTrue(
      app.textFields["review.answer"].waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertNotEqual(app.staticTexts["review.prompt"].value as? String, initialPrompt)
    try answer(in: app)
    XCTAssertTrue(
      app.staticTexts["Lesson quiz saved"].waitForExistence(timeout: 5), app.debugDescription)
    app.buttons["Finish session"].click()
    let lessons = app.buttons["home.lessons"]
    XCTAssertTrue(lessons.waitForExistence(timeout: 5))
    XCTAssertFalse(lessons.isEnabled)
  }
  func testPrimaryLessonActionOpensTeachingWithoutThePicker() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "--review-fixture", "--lesson-fixture",
    ]
    app.launch()
    app.activate()
    defer { app.terminate() }
    let lessons = app.buttons["home.lessons"]
    XCTAssertTrue(lessons.waitForExistence(timeout: 10))
    lessons.click()
    XCTAssertTrue(app.staticTexts["subject.meanings"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["lesson.startSelection"].exists)
    app.buttons["lesson.quiz"].click()
    XCTAssertTrue(
      app.textFields["review.answer"].waitForExistence(timeout: 5), app.debugDescription)
  }

}
