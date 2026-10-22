#if os(macOS)
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
      let choose = app.buttons["lesson.back"]
      XCTAssertEqual(choose.label, "Choose lessons")
      choose.click()
      XCTAssertTrue(subject.waitForExistence(timeout: 5))
      XCTAssertEqual(subject.value as? String, "Selected")
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
      input.typeText(prompt.hasSuffix("Reading") ? "ichi" : "one")
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
      let input = app.textFields["review.answer"]
      let draft = initialPrompt.hasSuffix("Reading") ? "one" : "ichi"
      input.click()
      input.typeText(draft)
      app.buttons["lesson.back"].click()
      app.pauseStudyAndReturn()
      XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertNotEqual(app.staticTexts["review.prompt"].value as? String, initialPrompt)
      XCTAssertEqual(input.value as? String, draft)
      app.buttons["review.submit"].click()
      XCTAssertTrue(
        app.staticTexts["Lesson quiz saved"].waitForExistence(timeout: 5), app.debugDescription)
      app.buttons["review.finish"].click()
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

    private func launchLessonSettings(limit: Bool = false) -> XCUIApplication {
      continueAfterFailure = false
      let app = XCUIApplication()
      app.launchArguments =
        [
          "-ApplePersistenceIgnoreState", "YES", "--review-fixture", "--lesson-fixture",
          "--lesson-settings-fixture",
        ] + (limit ? ["--lesson-limit-fixture"] : [])
      app.launch()
      app.activate()
      XCTAssertTrue(app.buttons["home.lessons"].waitForExistence(timeout: 10), app.debugDescription)
      app.buttons["app.settings"].click()
      app.buttons["settings.page.lessons"].click()
      XCTAssertTrue(
        app.popUpButtons["settings.lessonBatchSize"].waitForExistence(timeout: 5),
        app.debugDescription)
      return app
    }
    func testNativeLessonChoicesReorderAndTeachTheConfiguredBatch() {
      let app = launchLessonSettings()
      defer { app.terminate() }
      app.popUpButtons["settings.lessonBatchSize"].click()
      app.menuItems["2 lessons"].click()
      let form = app.sheets.firstMatch.scrollViews.firstMatch
      let kana = app.switches["settings.showKanaOnlyVocab"]
      if !kana.isHittable { form.scroll(byDeltaX: 0, deltaY: -250) }
      kana.click()
      let order = app.buttons["settings.lessonOrderLink"]
      form.scroll(byDeltaX: 0, deltaY: 300)
      order.click()
      let move = app.buttons["settings.lessonOrder.up.vocabulary"]
      XCTAssertTrue(move.waitForExistence(timeout: 5), app.debugDescription)
      move.click()
      move.click()
      app.sheets.firstMatch.buttons["chevron.backward"].click()
      app.buttons["Done"].click()
      let start = app.buttons["home.lessons"]
      XCTAssertTrue(start.waitForExistence(timeout: 5))
      XCTAssertTrue(start.label.contains("5 available"), app.debugDescription)
      start.click()
      XCTAssertTrue(app.staticTexts["subject.characters"].waitForExistence(timeout: 5))
      XCTAssertEqual(app.staticTexts["subject.characters"].value as? String, "一つ")
      XCTAssertTrue(app.staticTexts["lesson.position"].value as? String == "Lesson 1 of 2")
      let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      image.name = "Native configured lesson batch"
      image.lifetime = .keepAlways
      add(image)
      app.buttons["lesson.page.1"].click()
      XCTAssertEqual(app.staticTexts["subject.characters"].value as? String, "人")
    }
    func testNativeApprenticeLimitDisablesOnlyNewLessonsAndCanBeChanged() {
      let app = launchLessonSettings(limit: true)
      defer { app.terminate() }
      let limit = app.popUpButtons["settings.apprenticeLessonsLimit"]
      limit.click()
      app.menuItems["25"].click()
      app.buttons["Done"].click()
      let lessons = app.buttons["home.lessons"]
      XCTAssertTrue(lessons.waitForExistence(timeout: 5))
      XCTAssertFalse(lessons.isEnabled)
      XCTAssertTrue(app.staticTexts["Apprentice limit reached"].exists, app.debugDescription)
      app.buttons["app.settings"].click()
      app.buttons["settings.page.lessons"].click()
      limit.click()
      app.menuItems["No limit"].click()
      app.buttons["Done"].click()
      XCTAssertTrue(lessons.isEnabled, app.debugDescription)
    }

  }

#endif
