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
    @MainActor private func answerOneSubject(
      _ app: XCUIApplication, complete title: String, questions: Int = 2
    ) {
      for question in 0..<questions {
        let field = app.textFields["review.answer"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        let prompt = app.staticTexts["review.prompt"]
        let before = prompt.label.isEmpty ? String(describing: prompt.value ?? "") : prompt.label
        field.tap()
        field.typeText(before.contains("Reading") ? "ichi" : "one")
        app.buttons["review.submit"].tap()
        if question < questions - 1 {
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
      app.buttons["review.finish"].tap()
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
      XCUIDevice.shared.press(.home)
      XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
      app.activate()
      XCTAssertTrue(field.waitForExistence(timeout: 10))
      XCTAssertEqual(field.value as? String, "いち")
      XCTAssertTrue(app.staticTexts["review.prompt"].label.contains("Reading"))
      app.openReviewSettings()
      XCTAssertTrue(app.buttons["reviewSettings.done"].waitForExistence(timeout: 5))
      XCUIDevice.shared.press(.home)
      XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
      app.activate()
      XCTAssertTrue(app.buttons["reviewSettings.done"].waitForExistence(timeout: 10))
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
      let field = app.textFields["review.answer"]
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      field.tap()
      field.typeText("one")
      app.buttons["lesson.back"].tap()
      XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 5), app.debugDescription)
      app.buttons["home.resume"].tap()
      XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertEqual(field.value as? String, "one")
      app.buttons["review.submit"].tap()
      let reading = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "label CONTAINS %@", "Reading"),
        object: app.staticTexts["review.prompt"])
      XCTAssertEqual(XCTWaiter.wait(for: [reading], timeout: 5), .completed)
      answerOneSubject(app, complete: "Lesson quiz saved", questions: 1)
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
      app.navigationBars.buttons["BackButton"].firstMatch.tap()
      app.buttons["settings.page.reviews"].tap()
      scrollTo(timing, in: app)
      XCTAssertEqual(timing.value as? String, "1")
      app.navigationBars.buttons["BackButton"].firstMatch.tap()
      scrollTo(app.buttons["settings.developer"], in: app)
      app.buttons["settings.developer"].tap()
      app.buttons["developer.endpoint"].tap()
      XCTAssertTrue(app.alerts["API base URL"].waitForExistence(timeout: 5))
      app.alerts.buttons["Cancel"].tap()
      XCTAssertFalse(app.alerts.firstMatch.exists)
      let export = app.buttons["developer.export"]
      scrollTo(export, in: app)
      XCTAssertEqual(export.label, "Export study diagnostics")
      let picture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      picture.name = "Native account-scoped study diagnostics"
      picture.lifetime = .keepAlways
      add(picture)
      export.tap()
      let save = app.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@", "Save to Files")
      ).firstMatch
      XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
      let close = app.buttons["Close"].firstMatch
      let cancel = app.buttons["Cancel"].firstMatch
      if close.exists {
        close.tap()
      } else if cancel.exists {
        cancel.tap()
      } else {
        let popup = app.popovers.firstMatch
        XCTAssertTrue(popup.exists, app.debugDescription)
        let regions = app.otherElements.matching(identifier: "PopoverDismissRegion")
        guard regions.count > 0 else {
          XCTFail(app.debugDescription)
          return
        }
        regions.element(boundBy: regions.count - 1).coordinate(
          withNormalizedOffset: CGVector(
            dx: popup.frame.midX < app.frame.midX ? 0.95 : 0.05, dy: 0.5)
        ).tap()
      }
      XCTAssertTrue(save.waitForNonExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(app.navigationBars["Developer options"].exists)
      XCTAssertTrue(export.exists)
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
      app.buttons["review.voice"].tap()
      XCTAssertTrue(app.buttons["voice.stop"].waitForExistence(timeout: 5), app.debugDescription)
      app.buttons["voice.keyboard"].tap()
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      XCTAssertEqual(field.value as? String, "あ")
      app.buttons["review.close"].tap()
      XCTAssertTrue(app.buttons["practice.katakana"].waitForExistence(timeout: 5))
      tab("Home", in: app)
      XCTAssertTrue(app.buttons["home.reviews"].label.contains("1 ready"))
      requireEmptyOutbox(app)
    }
    @MainActor func testNativeKatakanaAnkiMistakesStayLocalAndOpenReadingFromSummary() {
      let app = launch(["--anki-fixture", "--reading-anki-fixture"])
      defer { app.terminate() }
      tab("Practice", in: app)
      app.buttons["practice.katakana"].tap()
      XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 10))
      XCTAssertFalse(app.textFields["review.answer"].exists)
      XCTAssertFalse(app.buttons["review.voice"].exists)
      app.buttons["review.submit"].tap()
      XCTAssertTrue(app.buttons["review.incorrect"].waitForExistence(timeout: 5))
      app.buttons["review.incorrect"].tap()
      XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 5))
      XCTAssertEqual(app.staticTexts["review.question"].value as? String, "ア")
      app.buttons["review.submit"].tap()
      app.buttons["review.correct"].tap()
      app.buttons["review.close"].tap()
      XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 5))
      let missed = app.buttons["summary.subject.0"]
      XCTAssertTrue(missed.exists && missed.label.contains("Reading missed"))
      XCTAssertFalse(missed.label.contains("Meaning missed"))
      missed.tap()
      XCTAssertTrue(app.staticTexts["practice.reading"].waitForExistence(timeout: 5))
      XCTAssertEqual(app.staticTexts["practice.reading"].label, "あ")
      app.navigationBars.buttons.firstMatch.tap()
      app.buttons["review.finish"].tap()
      XCTAssertTrue(app.buttons["practice.katakana"].waitForExistence(timeout: 5))
      tab("Home", in: app)
      XCTAssertTrue(app.buttons["home.reviews"].label.contains("1 ready"))
      requireEmptyOutbox(app)
    }

    @MainActor func testPendingReviewCoverageShowsAwaitingSyncInsteadOfNotStarted() {
      let app = launch(["--statistics-fixture", "--review-recovery-fixture"])
      defer { app.terminate() }
      tab("Stats", in: app)
      XCTAssertTrue(app.segmentedControls.buttons["Coverage"].waitForExistence(timeout: 10))
      app.segmentedControls.buttons["Coverage"].tap()
      let target = app.buttons["coverage.target.N5"]
      scrollTo(target, in: app)
      XCTAssertTrue(target.label.contains("1 awaiting sync"), app.debugDescription)
      XCTAssertTrue(target.label.contains("0 / 79"), target.label)
      target.tap()
      let remaining = app.staticTexts["coverage.remaining.N5"]
      XCTAssertTrue(remaining.waitForExistence(timeout: 5))
      XCTAssertTrue(remaining.label.contains("79"), remaining.label)
      XCTAssertEqual(app.sheets.count, 0)
      let picture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      picture.name = "Pending kanji coverage with explicit awaiting-sync count"
      picture.lifetime = .keepAlways
      add(picture)
    }

    @MainActor func testStatisticsUpdatesDueCountWithoutRefreshingSnapshot() {
      let app = launch(["--statistics-fixture", "--statistics-clock-fixture"])
      defer { app.terminate() }
      tab("Stats", in: app)
      let initiallyDue = app.staticTexts["0 due now"]
      scrollTo(initiallyDue, in: app)
      XCTAssertTrue(initiallyDue.exists)
      let snapshot = app.staticTexts.matching(
        NSPredicate(format: "label BEGINSWITH %@", "Snapshot:")
      )
      .firstMatch
      XCTAssertTrue(snapshot.exists)
      let savedAt = snapshot.label
      let updated = app.staticTexts["1 due now"]
      XCTAssertTrue(updated.waitForExistence(timeout: 100), app.debugDescription)
      XCTAssertFalse(initiallyDue.exists)
      XCTAssertEqual(snapshot.label, savedAt)
      XCTAssertTrue(app.segmentedControls.buttons["Progress"].isSelected)
      XCTAssertEqual(app.sheets.count, 0)
      let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      image.name = "Statistics follows the clock without a refresh"
      image.lifetime = .keepAlways
      add(image)
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
