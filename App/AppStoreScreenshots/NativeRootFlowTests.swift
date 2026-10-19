#if os(iOS)
  import XCTest

  /// Exercises the production SwiftUI scene with injected, memory-only account services.
  final class NativeRootFlowTests: XCTestCase {
    @MainActor private func launch(_ arguments: [String] = []) -> XCUIApplication {
      continueAfterFailure = false
      XCUIDevice.shared.orientation = .portrait
      let app = XCUIApplication()
      app.launchArguments = ["--review-fixture", "--light-fixture"] + arguments
      app.launch()
      XCTAssertTrue(app.buttons["app.settings"].waitForExistence(timeout: 15), app.debugDescription)
      XCTAssertFalse(app.otherElements["startup.failure"].exists)
      let picture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      picture.name = "Shared native SwiftUI Home"
      picture.lifetime = .keepAlways
      add(picture)
      return app
    }
    @MainActor private func tab(_ name: String, in app: XCUIApplication) {
      let button = app.tabBars.buttons[name].firstMatch
      if button.exists { button.tap() } else { app.buttons[name].firstMatch.tap() }
    }
    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
      for _ in 0..<12 {
        if element.exists && element.isHittable { return }
        app.swipeUp()
      }
      XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    @MainActor private func backToHome(_ app: XCUIApplication) {
      let home = app.navigationBars.buttons["Home"].firstMatch
      if home.exists { home.tap() } else { app.navigationBars.buttons["Back"].firstMatch.tap() }
      XCTAssertTrue(app.buttons["home.reviews"].waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func answerOneSubject(_ app: XCUIApplication, complete title: String) {
      for question in 0..<2 {
        let field = app.textFields["review.answer"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        let prompt = app.staticTexts["review.prompt"]
        let before = prompt.label.isEmpty ? String(describing: prompt.value ?? "") : prompt.label
        field.tap()
        field.typeText(before.contains("Reading") ? "ichi" : "one")
        app.buttons["review.submit"].tap()
        if question == 0 {
          let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
              let after =
                prompt.label.isEmpty ? String(describing: prompt.value ?? "") : prompt.label
              return after != before
            }, object: nil)
          XCTAssertEqual(
            XCTWaiter.wait(for: [changed], timeout: 10), .completed, app.debugDescription)
        }
      }
      XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), app.debugDescription)
      app.buttons["Finish session"].tap()
      XCTAssertTrue(app.buttons["home.reviews"].waitForExistence(timeout: 10))
    }
    @MainActor private func requireEmptyOutbox(_ app: XCUIApplication) {
      app.buttons["home.savedWork"].tap()
      let count = app.descendants(matching: .any).matching(identifier: "savedWork.answerCount")
        .firstMatch
      XCTAssertTrue(count.waitForExistence(timeout: 5), app.debugDescription)
      let drained = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          count.label.hasSuffix("0") || count.value as? String == "0"
        }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [drained], timeout: 10), .completed, app.debugDescription)
    }
    @MainActor func testNativeReviewConvertsRomajiAndPreservesDraftThroughSettingsAndPause() {
      let app = launch()
      defer { app.terminate() }
      app.buttons["home.reviews"].tap()
      let field = app.textFields["review.answer"]
      XCTAssertTrue(field.waitForExistence(timeout: 10))
      if !app.staticTexts["review.prompt"].label.contains("Reading") {
        field.tap()
        field.typeText("one")
        app.buttons["review.submit"].tap()
        let reading = XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "label CONTAINS %@", "Reading"),
          object: app.staticTexts["review.prompt"])
        XCTAssertEqual(XCTWaiter.wait(for: [reading], timeout: 5), .completed)
      }
      field.tap()
      field.typeText("ichi")
      XCTAssertEqual(field.value as? String, "いち")
      app.buttons["review.settings"].tap()
      XCTAssertTrue(app.buttons["reviewSettings.done"].waitForExistence(timeout: 5))
      app.buttons["reviewSettings.done"].tap()
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      XCTAssertEqual(field.value as? String, "いち")
      backToHome(app)
      app.buttons["home.resume"].tap()
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      XCTAssertEqual(field.value as? String, "いち")
    }
    @MainActor func testNativeTypedReviewCompletesAndUploadsWithoutAManualSync() {
      let app = launch()
      defer { app.terminate() }
      app.buttons["home.reviews"].tap()
      answerOneSubject(app, complete: "Review session saved")
      requireEmptyOutbox(app)
    }
    @MainActor func testNativeLessonsTeachQuizAndUploadWithoutAManualSync() {
      let app = launch(["--lesson-fixture"])
      defer { app.terminate() }
      app.buttons["home.lessons"].tap()
      XCTAssertTrue(app.buttons["lesson.quiz"].waitForExistence(timeout: 10), app.debugDescription)
      app.buttons["lesson.quiz"].tap()
      answerOneSubject(app, complete: "Lesson quiz saved")
      requireEmptyOutbox(app)
    }
    @MainActor func testNativeMainSettingsKeepTimingAndExposeKeyboardAndDiagnostics() {
      let app = launch()
      defer { app.terminate() }
      app.buttons["app.settings"].tap()
      app.buttons["settings.page.reviews"].tap()
      let timing = app.switches["settings.showMinutesForNextLevelUpReview"]
      scrollTo(timing, in: app)
      let thumb = timing.switches.firstMatch
      if thumb.exists {
        thumb.tap()
      } else {
        timing.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
      }
      XCTAssertEqual(timing.value as? String, "1")
      scrollTo(app.switches["settings.autoSwitchKeyboard"], in: app)
      app.navigationBars.buttons["Settings"].tap()
      app.buttons["settings.page.reviews"].tap()
      scrollTo(timing, in: app)
      XCTAssertEqual(timing.value as? String, "1")
      app.navigationBars.buttons["Settings"].tap()
      scrollTo(app.buttons["settings.developer"], in: app)
      app.buttons["settings.developer"].tap()
      app.buttons["developer.endpoint"].tap()
      XCTAssertTrue(app.alerts["API base URL"].waitForExistence(timeout: 5))
      app.alerts.buttons["Cancel"].tap()
      XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    @MainActor func testNativeLogoutCanBeCancelledAndReconnectsWithoutReopeningTheOldWriter() {
      let app = launch()
      defer { app.terminate() }
      app.buttons["app.settings"].tap()
      scrollTo(app.buttons["WaniKani account"], in: app)
      app.buttons["WaniKani account"].tap()
      scrollTo(app.buttons["Disconnect and remove local snapshot"], in: app)
      app.buttons["Disconnect and remove local snapshot"].tap()
      let disconnect = app.buttons["Disconnect"]
      XCTAssertTrue(disconnect.waitForExistence(timeout: 5), app.debugDescription)
      if app.buttons["Cancel"].exists {
        app.buttons["Cancel"].tap()
      } else {
        let regions = app.otherElements.matching(identifier: "PopoverDismissRegion")
        XCTAssertGreaterThan(regions.count, 0)
        regions.element(boundBy: regions.count - 1).tap()
      }
      XCTAssertFalse(disconnect.exists)
      XCTAssertTrue(app.buttons["Disconnect and remove local snapshot"].exists)
      scrollTo(app.buttons["Disconnect and remove local snapshot"], in: app)
      app.buttons["Disconnect and remove local snapshot"].tap()
      app.buttons["Disconnect"].tap()
      let token = app.secureTextFields["login.token"]
      XCTAssertTrue(token.waitForExistence(timeout: 10), app.debugDescription)
      token.tap()
      token.typeText("fixture\n")
      XCTAssertTrue(app.buttons["home.reviews"].waitForExistence(timeout: 10), app.debugDescription)
      XCTAssertFalse(token.exists)
    }
    @MainActor func testNativeCombinedAnkiFinishesOneSubject() {
      let app = launch(["--anki-fixture", "--combined-anki-fixture"])
      defer { app.terminate() }
      app.buttons["home.reviews"].tap()
      XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 10))
      XCTAssertFalse(app.textFields["review.answer"].exists)
      app.buttons["review.submit"].tap()
      XCTAssertTrue(app.buttons["review.correct"].waitForExistence(timeout: 5))
      app.buttons["review.correct"].tap()
      XCTAssertTrue(
        app.staticTexts["Review session saved"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor func testNativeKatakanaUsesTheSameInputAndDoesNotCreateUploads() {
      let app = launch()
      defer { app.terminate() }
      tab("Practice", in: app)
      app.buttons["practice.katakana"].tap()
      let field = app.textFields["review.answer"]
      XCTAssertTrue(field.waitForExistence(timeout: 10))
      field.tap()
      field.typeText("a")
      XCTAssertEqual(field.value as? String, "あ")
      app.buttons["practice.end"].tap()
      app.sheets.buttons["End practice"].tap()
      XCTAssertTrue(app.buttons["practice.katakana"].waitForExistence(timeout: 5))
      tab("Home", in: app)
      XCTAssertTrue(app.buttons["home.reviews"].label.contains("1 ready"))
      requireEmptyOutbox(app)
    }
    @MainActor func testNativeColdStudyLinksRouteFromTheSharedScene() {
      continueAfterFailure = false
      let app = XCUIApplication()
      defer { app.terminate() }
      for route in ["reviews", "lessons", "subject/1"] {
        app.terminate()
        app.launchArguments =
          ["--review-fixture", "--light-fixture"]
          + (route == "lessons" ? ["--lesson-fixture"] : [])
        app.open(URL(string: "usagiunagi:///" + route)!)
        switch route {
        case "reviews":
          XCTAssertTrue(
            app.textFields["review.answer"].waitForExistence(timeout: 15), app.debugDescription)
        case "lessons":
          XCTAssertTrue(
            app.buttons["lesson.quiz"].waitForExistence(timeout: 15), app.debugDescription)
        default:
          XCTAssertTrue(
            app.staticTexts["subject.characters"].waitForExistence(timeout: 15),
            app.debugDescription)
        }
        backToHome(app)
        XCTAssertFalse(app.otherElements["startup.failure"].exists)
      }
    }
    @MainActor func testNativeStatisticsCoverageStaysInline() {
      let app = launch(["--statistics-fixture"])
      defer { app.terminate() }
      tab("Stats", in: app)
      XCTAssertTrue(app.segmentedControls.buttons["Coverage"].waitForExistence(timeout: 10))
      app.segmentedControls.buttons["Coverage"].tap()
      XCTAssertTrue(
        app.descendants(matching: .any).matching(identifier: "coverage.chart").firstMatch
          .waitForExistence(timeout: 10))
      XCTAssertEqual(app.sheets.count, 0)
    }
  }
#endif
