#if os(macOS)
  import AppKit
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
    func testCompletedReviewsUploadAutomaticallyAndLeaveTheHomeQueue() {
      let app = launch(["--anki-fixture", "--combined-anki-fixture"])
      defer { app.terminate() }
      app.buttons["home.reviews"].click()
      showAnswer(in: app)
      app.buttons["review.correct"].click()
      XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 5))
      app.buttons["Finish session"].click()
      let reviews = app.buttons["home.reviews"]
      XCTAssertTrue(reviews.waitForExistence(timeout: 5))
      let caughtUp = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "enabled == false AND label CONTAINS %@", "0 ready"),
        object: reviews)
      XCTAssertEqual(XCTWaiter.wait(for: [caughtUp], timeout: 10), .completed)
      app.buttons["home.savedWork"].click()
      XCTAssertTrue(
        app.staticTexts["No saved work waiting"].waitForExistence(timeout: 5), app.debugDescription)
    }
    func testUncertainReviewStaysPendingAndHasReadOnlyRecovery() {
      let app = launch(["--review-recovery-fixture"])
      defer { app.terminate() }
      app.buttons["home.savedWork"].click()
      let list = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      list.name = "Native uncertain-work list before expanding"
      list.lifetime = .keepAlways
      add(list)
      let answer = app.disclosureTriangles.firstMatch
      XCTAssertTrue(answer.waitForExistence(timeout: 5))
      // Grouped forms include leading space in the disclosure accessibility frame.
      answer.coordinate(withNormalizedOffset: CGVector(dx: 0.33, dy: 0.5)).click()
      let compare = app.buttons["savedWork.compareAnswer.1"]
      XCTAssertTrue(compare.waitForExistence(timeout: 5), app.debugDescription)
      if !compare.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 500) }
      compare.click()
      let archive = app.buttons["savedWork.archiveAnswer"]
      XCTAssertTrue(archive.waitForExistence(timeout: 5), app.debugDescription)
      let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      image.name = "Native uncertain review recovery remains explicit"
      image.lifetime = .keepAlways
      add(image)
      let stage = app.descendants(matching: .any).matching(
        identifier: "savedWork.field.Current stage"
      ).firstMatch
      XCTAssertTrue(stage.waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts["Current stage"].exists)
      XCTAssertEqual(stage.value as? String, "4", stage.debugDescription)
      app.sheets.firstMatch.buttons["Keep pending"].click()
      XCTAssertTrue(compare.waitForExistence(timeout: 5))
      XCTAssertFalse(app.staticTexts["No saved work waiting"].exists)
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
      let settings = app.buttons["settings.page.reviews"]
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
    func testSubjectDisplayChoicesReachSavedDetailsAndPersist() {
      let app = launch(["--subject-display-fixture"])
      defer { app.terminate() }
      app.buttons["app.settings"].click()
      app.buttons["settings.page.subjects"].click()
      setSubjectChoice("useKatakanaForOnyomi", true, in: app)
      setSubjectChoice("showAllReadings", true, in: app)
      setSubjectChoice("showStatsSection", false, in: app)
      app.buttons["Done"].click()
      openSubject("ichi", id: 1, in: app)
      let primary = app.staticTexts["subject.reading.0"]
      makeVisible(primary, in: app.scrollViews.firstMatch)
      XCTAssertEqual(primary.value as? String, "イチ · Primary")
      XCTAssertEqual(app.staticTexts["subject.reading.1"].value as? String, "ひと")
      XCTAssertFalse(
        app.descendants(matching: .any).matching(identifier: "subject.statistics").firstMatch.exists
      )
      app.toolbars.buttons["chevron.backward"].click()
      app.toolbars.buttons["chevron.backward"].click()
      app.buttons["app.settings"].click()
      app.buttons["settings.page.subjects"].click()
      setSubjectChoice("useKatakanaForOnyomi", true, in: app)
      setSubjectChoice("showAllReadings", true, in: app)
      setSubjectChoice("showStatsSection", true, in: app)
      setSubjectChoice("showArtwork", true, in: app)
      let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      screenshot.name = "Shared subject display choices"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      app.buttons["Done"].click()
      openSubject("ichi", id: 1, in: app)
      let stats = app.descendants(matching: .any).matching(identifier: "subject.statistics")
        .firstMatch
      makeVisible(stats, in: app.scrollViews.firstMatch)
      XCTAssertTrue(stats.exists)
      let artwork = app.descendants(matching: .any).matching(identifier: "subject.artwork")
        .firstMatch
      makeVisible(artwork, in: app.scrollViews.firstMatch)
      XCTAssertTrue(artwork.exists)
    }
    func testSubjectReadingPolicyAppliesToANewReview() {
      let app = launch([])
      defer { app.terminate() }
      app.buttons["app.settings"].click()
      app.buttons["settings.page.subjects"].click()
      setSubjectChoice("skipKanjiReadings", true, in: app)
      app.buttons["Done"].click()
      app.buttons["home.reviews"].click()
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      XCTAssertEqual(app.staticTexts["review.prompt"].value as? String, "Meaning")
      input.click()
      input.typeText("one")
      app.buttons["review.submit"].click()
      XCTAssertTrue(
        app.staticTexts["Review session saved"].waitForExistence(timeout: 5), app.debugDescription)
    }
    func testNativeContextTranslationsStartConcealedAndRespectTheSharedChoice() {
      let app = launch([])
      defer { app.terminate() }
      openSubject("hitotsu", id: 3, in: app)
      let reveal = app.buttons["subject.translation.0"]
      makeVisible(reveal, in: app.scrollViews.firstMatch)
      XCTAssertFalse(app.staticTexts["One, please."].firstMatch.exists)
      reveal.click()
      XCTAssertTrue(app.staticTexts["One, please."].firstMatch.waitForExistence(timeout: 5))
      app.toolbars.buttons["chevron.backward"].click()
      app.toolbars.buttons["chevron.backward"].click()
      app.buttons["app.settings"].click()
      app.buttons["settings.page.subjects"].click()
      setSubjectChoice("blurContextSentences", false, in: app)
      app.buttons["Done"].click()
      openSubject("hitotsu", id: 3, in: app)
      let translation = app.staticTexts["One, please."].firstMatch
      makeVisible(translation, in: app.scrollViews.firstMatch)
      XCTAssertTrue(translation.exists)
      XCTAssertFalse(reveal.exists)
    }
    private func openSubject(_ query: String, id: Int64, in app: XCUIApplication) {
      app.buttons["app.search"].click()
      let search = app.searchFields.firstMatch
      XCTAssertTrue(search.waitForExistence(timeout: 5))
      search.click()
      search.typeText(query)
      let subject = app.buttons["catalog.subject.\(id)"]
      XCTAssertTrue(subject.waitForExistence(timeout: 5), app.debugDescription)
      subject.click()
      XCTAssertTrue(app.staticTexts["subject.meanings"].waitForExistence(timeout: 5))
    }
    private func setSubjectChoice(_ id: String, _ value: Bool, in app: XCUIApplication) {
      let control = app.switches["settings.\(id)"]
      makeVisible(control, in: app.sheets.firstMatch.scrollViews.firstMatch)
      XCTAssertTrue(control.isHittable, control.debugDescription)
      if (control.value as? NSNumber)?.boolValue != value { control.click() }
      XCTAssertEqual((control.value as? NSNumber)?.boolValue, value)
    }
    private func makeVisible(_ element: XCUIElement, in scroll: XCUIElement) {
      for _ in 0..<10 {
        if element.exists {
          let viewport = scroll.frame
          if element.frame.midY > viewport.minY + 8
            && element.frame.midY < viewport.maxY - 8
          {
            return
          }
          scroll.scroll(byDeltaX: 0, deltaY: element.frame.midY < viewport.midY ? 180 : -180)
        } else {
          scroll.scroll(byDeltaX: 0, deltaY: -180)
        }
      }
      XCTAssertTrue(
        element.exists && scroll.frame.intersects(element.frame), element.debugDescription)
    }
    func testTypedAnswerSurvivesPauseAndClearsForTheNextQuestion() {
      let app = launch([])
      defer { app.terminate() }
      app.buttons["home.reviews"].click()
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      let prompt = app.staticTexts["review.prompt"]
      let first = prompt.value as? String
      XCTAssertTrue(first == "Meaning" || first == "Reading")
      let answer = first == "Reading" ? "ichi" : "one"
      input.click()
      input.typeText(answer)
      app.pauseStudyAndReturn()
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      XCTAssertEqual(input.value as? String, answer)
      XCTAssertEqual(prompt.value as? String, first)
      app.buttons["review.submit"].click()
      let changed = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value != %@", first!), object: prompt)
      XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
      XCTAssertEqual(input.value as? String, "")
      app.pauseStudyAndReturn()
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      XCTAssertEqual(input.value as? String, "")
      input.click()
      input.typeText(first == "Reading" ? "one" : "ichi")
      app.buttons["review.submit"].click()
      XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 5))
    }

    func testRetryKeepsItsDraftAndAnsweringStateWhenResumed() {
      let app = launch([])
      defer { app.terminate() }
      app.buttons["home.reviews"].click()
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      app.buttons["review.settings"].click()
      let autoreveal = app.switches["reviewSettings.autoreveal"]
      makeVisible(autoreveal, in: app.sheets.firstMatch.scrollViews.firstMatch)
      XCTAssertEqual((autoreveal.value as? NSNumber)?.boolValue, true)
      autoreveal.click()
      app.buttons["Done"].click()
      let reading = app.staticTexts["review.prompt"].value as? String == "Reading"
      input.click()
      input.typeText(reading ? "inu" : "wrong")
      app.buttons["review.submit"].click()
      let retry = app.buttons["Try again"]
      XCTAssertTrue(retry.waitForExistence(timeout: 5), app.debugDescription)
      retry.click()
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      input.click()
      let partial = reading ? "ic" : "on"
      input.typeText(partial)
      app.pauseStudyAndReturn()
      XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertEqual(input.value as? String, partial)
      XCTAssertFalse(app.buttons["Try again"].exists)
    }

    func testDiscardingTheSessionCannotRestoreItsDraftIntoANewSession() {
      let app = launch([])
      defer { app.terminate() }
      app.buttons["home.reviews"].click()
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      input.click()
      input.typeText("Unsubmitted text")
      app.buttons["review.end"].click()
      app.buttons["review.confirmEnd"].click()
      XCTAssertTrue(app.buttons["home.reviews"].waitForExistence(timeout: 5))
      app.buttons["home.reviews"].click()
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      XCTAssertEqual(input.value as? String, "")
      XCTAssertFalse(app.staticTexts["Review session saved"].exists)
    }

    private func deliverLink(_ text: String) async throws {
      let candidates = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.pedrexus.tsurukame.mac"
      ).filter {
        $0.bundleURL?.path.contains("/.build/") == true
      }
      XCTAssertEqual(candidates.count, 1, "URL tests require one running fixture build")
      let running = try XCTUnwrap(candidates.first)
      let application = try XCTUnwrap(running.bundleURL)
      let opened = try await NSWorkspace.shared.open(
        [try XCTUnwrap(URL(string: text))], withApplicationAt: application, configuration: .init())
      XCTAssertEqual(opened.processIdentifier, running.processIdentifier)
      XCTAssertEqual(
        XCUIApplication().windows.matching(
          NSPredicate(format: "identifier BEGINSWITH %@", "study-AppWindow-")
        ).count, 1, "Incoming links must reuse the study window")
    }
    func testIncomingSubjectLinksPreserveTheReviewAndItsOpenSettings() async throws {
      let app = launch([])
      defer { app.terminate() }
      app.buttons["home.reviews"].click()
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      input.click()
      input.typeText("Unsubmitted draft")
      app.buttons["review.settings"].click()
      try await deliverLink("usagiunagi://subject/1")
      let pending = app.buttons["applink.open"]
      XCTAssertTrue(pending.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(app.sheets.firstMatch.exists)
      pending.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).click()
      let keptSettings = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == false"), object: app.sheets.firstMatch)
      keptSettings.isInverted = true
      let sheetResult = await XCTWaiter.fulfillment(of: [keptSettings], timeout: 1)
      XCTAssertEqual(sheetResult, .completed)
      XCTAssertEqual(input.value as? String, "Unsubmitted draft")
      app.buttons["Done"].click()
      XCTAssertEqual(input.value as? String, "Unsubmitted draft")
      pending.click()
      XCTAssertTrue(app.staticTexts["subject.meanings"].waitForExistence(timeout: 5))
      app.toolbars.buttons["chevron.backward"].click()
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      XCTAssertEqual(input.value as? String, "Unsubmitted draft")
      try await deliverLink("tsurukame:///kanji/%E4%B8%80")
      XCTAssertTrue(pending.waitForExistence(timeout: 5))
      pending.click()
      XCTAssertTrue(app.staticTexts["subject.meanings"].waitForExistence(timeout: 5))
      app.toolbars.buttons["chevron.backward"].click()
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      XCTAssertEqual(input.value as? String, "Unsubmitted draft")
    }
    func testReviewLinkFromStatisticsReturnsToTheSameTab() async throws {
      let app = launch([])
      defer { app.terminate() }
      app.openStudyTab("Stats")
      XCTAssertTrue(app.scrollViews["StudyDashboard"].waitForExistence(timeout: 5))
      try await deliverLink("usagiunagi:///reviews")
      XCTAssertTrue(app.textFields["review.answer"].waitForExistence(timeout: 5))
      app.toolbars.buttons["chevron.backward"].click()
      XCTAssertTrue(app.scrollViews["StudyDashboard"].waitForExistence(timeout: 5))
    }
    func testLessonLinkFromStatisticsOpensTeachingAndReturns() async throws {
      let app = launch(["--lesson-fixture"])
      defer { app.terminate() }
      app.openStudyTab("Stats")
      XCTAssertTrue(app.scrollViews["StudyDashboard"].waitForExistence(timeout: 5))
      try await deliverLink("tsurukame:///lessons")
      XCTAssertTrue(app.buttons["lesson.quiz"].waitForExistence(timeout: 5), app.debugDescription)
      app.toolbars.buttons["chevron.backward"].click()
      XCTAssertTrue(app.scrollViews["StudyDashboard"].waitForExistence(timeout: 5))
    }
    func testWrapUpLinkUsesTheActiveReviewWithoutGradingAnAnswer() async throws {
      let app = launch([])
      defer { app.terminate() }
      app.buttons["home.reviews"].click()
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      let first = try XCTUnwrap(app.staticTexts["review.prompt"].value as? String)
      input.click()
      input.typeText(first == "Reading" ? "ichi" : "one")
      app.buttons["review.submit"].click()
      let changed = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value != %@", first),
        object: app.staticTexts["review.prompt"]
      )
      let verdict = await XCTWaiter.fulfillment(of: [changed], timeout: 5)
      XCTAssertEqual(verdict, .completed)
      try await deliverLink("usagiunagi://wrap-up")
      let open = app.buttons["applink.open"]
      XCTAssertTrue(open.waitForExistence(timeout: 5))
      open.click()
      XCTAssertTrue(
        app.buttons["Stop wrapping up"].waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertFalse(app.staticTexts["Review session saved"].exists)
      input.click()
      input.typeText(first == "Reading" ? "one" : "ichi")
      app.buttons["review.submit"].click()
      XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 5))
    }
    func testIncomingLinkWaitsForAnExplicitOpenDuringKanaPractice() async throws {
      let app = launch([])
      defer { app.terminate() }
      app.openStudyTab("Practice")
      try await deliverLink("usagiunagi:///reviews")
      let open = app.buttons["applink.open"]
      XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertFalse(app.textFields["review.answer"].exists)
      open.click()
      XCTAssertTrue(app.textFields["review.answer"].waitForExistence(timeout: 5))
    }
    func testColdStudyLinksWaitForTheSavedAccountAndUseOneWindow() throws {
      continueAfterFailure = false
      let app = XCUIApplication()
      defer { app.terminate() }
      for (url, lesson) in [
        ("usagiunagi:///subject/1", false), ("tsurukame:///reviews", false),
        ("usagiunagi:///lessons", true),
      ] {
        app.terminate()
        XCTAssertTrue(
          NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.pedrexus.tsurukame.mac"
          )
          .isEmpty)
        app.launchArguments =
          ["-ApplePersistenceIgnoreState", "YES", "--review-fixture"]
          + (lesson ? ["--lesson-fixture"] : [])
        app.open(try XCTUnwrap(URL(string: url)))
        app.activate()
        if lesson {
          XCTAssertTrue(
            app.buttons["lesson.quiz"].waitForExistence(timeout: 10), app.debugDescription)
        } else if url.contains("subject") {
          XCTAssertTrue(
            app.staticTexts["subject.meanings"].waitForExistence(timeout: 10), app.debugDescription)
        } else {
          XCTAssertTrue(
            app.textFields["review.answer"].waitForExistence(timeout: 10), app.debugDescription)
        }
        XCTAssertEqual(
          app.windows.matching(NSPredicate(format: "identifier BEGINSWITH %@", "study-AppWindow-"))
            .count, 1)
      }
    }
    func testMissingSubjectLinkDoesNotLeaveAnErrorOnTheNextValidLink() async throws {
      let app = launch([])
      defer { app.terminate() }
      try await deliverLink("usagiunagi:///subject/999999")
      let message = app.descendants(matching: .any).matching(identifier: "applink.message")
        .firstMatch
      XCTAssertTrue(message.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertFalse(app.textFields["review.answer"].exists)
      try await deliverLink("usagiunagi:///subject/1")
      XCTAssertTrue(app.staticTexts["subject.meanings"].waitForExistence(timeout: 5))
      XCTAssertFalse(message.exists)
    }
    func testLessonLinkResumesTheExistingReviewAndExplainsWhy() async throws {
      let app = launch([])
      defer { app.terminate() }
      app.buttons["home.reviews"].click()
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      input.click()
      input.typeText("Existing review draft")
      try await deliverLink("usagiunagi:///lessons")
      let open = app.buttons["applink.open"]
      XCTAssertTrue(open.waitForExistence(timeout: 5))
      open.click()
      XCTAssertTrue(
        app.descendants(matching: .any).matching(identifier: "applink.message").firstMatch
          .waitForExistence(timeout: 5))
      XCTAssertEqual(input.value as? String, "Existing review draft")
      XCTAssertFalse(app.buttons["lesson.quiz"].exists)
    }
    func testInactiveWrapUpLinkDoesNotStartAReview() async throws {
      let app = launch([])
      defer { app.terminate() }
      try await deliverLink("usagiunagi:///wrap-up")
      XCTAssertTrue(
        app.descendants(matching: .any).matching(identifier: "applink.message").firstMatch
          .waitForExistence(timeout: 5)
      )
      XCTAssertFalse(app.textFields["review.answer"].exists)
      XCTAssertFalse(app.buttons["home.resume"].exists)
      XCTAssertTrue(app.buttons["home.reviews"].isHittable)
    }
    func testSharedTokenSignInErrorsHibernationAndSuccessKeepTheCurrentWindow() {
      let app = launch(["--light-fixture"])
      defer { app.terminate() }
      app.buttons["app.settings"].click()
      app.buttons["WaniKani account"].click()
      let token = app.secureTextFields["login.token"]
      XCTAssertTrue(token.waitForExistence(timeout: 5))
      XCTAssertFalse(app.buttons["login.submit"].isEnabled)
      XCTAssertFalse(app.secureTextFields["login.password"].exists)
      for candidate in ["rejected", "hibernating", "fixture"] {
        token.click()
        token.typeKey("a", modifierFlags: .command)
        token.typeText(candidate)
        app.buttons["login.submit"].click()
        if candidate == "fixture" {
          XCTAssertTrue(app.buttons["app.settings"].waitForExistence(timeout: 10))
          XCTAssertFalse(token.exists)
        } else {
          let error = app.staticTexts["login.error"]
          XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
          XCTAssertEqual(app.links["login.reactivate"].exists, candidate == "hibernating")
          XCTAssertTrue(app.buttons["login.submit"].isEnabled)
        }
      }
      app.buttons["app.settings"].click()
      app.buttons["WaniKani account"].click()
      app.buttons["Disconnect and remove local snapshot"].click()
      XCTAssertTrue(token.waitForExistence(timeout: 10))
      XCTAssertFalse(app.buttons["login.submit"].isEnabled)
      token.click()
      token.typeText("fixture\n")
      XCTAssertTrue(app.buttons["app.settings"].waitForExistence(timeout: 10))
      XCTAssertFalse(token.exists)
      XCTAssertEqual(
        app.windows.matching(NSPredicate(format: "identifier BEGINSWITH %@", "study-AppWindow-"))
          .count, 1)
    }
    func testSharedNotificationSettingsPersistAndKeepTheCurrentWindow() {
      let app = launch([])
      defer { app.terminate() }
      app.buttons["app.settings"].click()
      app.buttons["settings.page.appearance"].click()
      let style = app.popUpButtons["settings.interfaceStyle"]
      XCTAssertTrue(style.waitForExistence(timeout: 5))
      style.click()
      app.menuItems["Dark"].click()
      let email = app.textFields["settings.gravatarCustomEmail"]
      XCTAssertTrue(email.waitForExistence(timeout: 5))
      email.click()
      email.typeText("fixture@example.invalid")
      let choices = [
        ("settings.notificationsAllReviews", true),
        ("settings.notificationsBadging", false), ("settings.notificationSounds", true),
      ]
      for (id, enabled) in choices {
        let toggle = app.switches[id]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? NSNumber)?.boolValue != enabled { toggle.click() }
        XCTAssertEqual((toggle.value as? NSNumber)?.boolValue, enabled)
      }
      let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      screenshot.name = "Shared native appearance and notification settings"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      app.buttons["Done"].click()
      app.buttons["app.settings"].click()
      app.buttons["settings.page.appearance"].click()
      XCTAssertEqual(style.value as? String, "Dark")
      XCTAssertEqual(email.value as? String, "fixture@example.invalid")
      for (id, enabled) in choices {
        let toggle = app.switches[id]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual((toggle.value as? NSNumber)?.boolValue, enabled)
      }
      XCTAssertFalse(app.alerts.firstMatch.exists)
      XCTAssertEqual(
        app.windows.matching(NSPredicate(format: "identifier BEGINSWITH %@", "study-AppWindow-"))
          .count, 1)
    }
    func testHomeForecastAndSavedSubjectSearchOpenNativeScreens() {
      let app = launch(["--light-fixture"])
      defer { app.terminate() }
      let home = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      home.name = "Native Home"
      home.lifetime = .keepAlways
      add(home)
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
      app.buttons["settings.page.reviews"].click()
      let fonts = app.buttons["reviewSettings.fonts"]
      XCTAssertTrue(fonts.waitForExistence(timeout: 5))
      fonts.click()
      app.buttons["font.download.font-download.ttf"].click()
      XCTAssertTrue(
        app.descendants(matching: .any).matching(identifier: "font.progress.font-download.ttf")
          .firstMatch.waitForExistence(timeout: 5), app.debugDescription)
      let back = app.sheets.firstMatch.buttons["chevron.backward"]
      XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
      back.click()
      fonts.click()
      XCTAssertTrue(
        app.switches["font.selection.font-download.ttf"].waitForExistence(timeout: 12),
        app.debugDescription)
      let held = app.buttons["font.download.font-held.ttf"]
      XCTAssertTrue(held.waitForExistence(timeout: 5))
      held.click()
      app.buttons["font.cancel.font-held.ttf"].click()
      XCTAssertTrue(held.waitForExistence(timeout: 5))
      let failed = app.buttons["font.download.font-failed.ttf"]
      failed.click()
      XCTAssertTrue(app.staticTexts["font.error.font-failed.ttf"].waitForExistence(timeout: 5))
      XCTAssertEqual(failed.label, "Retry")
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
    func testNativeOfflineAudioSettingsKeepTheUnsubmittedReviewDraft() {
      let app = launch(["--audio-fixture"])
      defer { app.terminate() }
      app.buttons["home.reviews"].click()
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      input.click()
      input.typeText("one thing")
      app.buttons["review.settings"].click()
      app.buttons["reviewSettings.offlineAudio"].click()
      let enabled = app.switches["offlineAudio.enabled"]
      XCTAssertTrue(enabled.waitForExistence(timeout: 5), app.debugDescription)
      enabled.click()
      let voice = app.switches["offlineAudio.voice.1"]
      XCTAssertTrue(voice.waitForExistence(timeout: 5))
      XCTAssertEqual((voice.value as? NSNumber)?.intValue, 1)
      let complete = app.staticTexts["offlineAudio.status"]
      let finished = XCTNSPredicateExpectation(
        predicate: NSPredicate(
          format: "value CONTAINS %@ OR label CONTAINS %@", "Up to date", "Up to date"),
        object: complete)
      XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15), .completed, app.debugDescription)
      let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      image.name = "Shared native offline audio"
      image.lifetime = .keepAlways
      add(image)
      app.sheets.firstMatch.buttons["chevron.backward"].click()
      app.buttons["reviewSettings.done"].click()
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      XCTAssertEqual(input.value as? String, "one thing")
    }
    func testNativeReadingAutoplayRetainsAStopControlAfterTheFinalAnswer() {
      let app = launch(["--audio-fixture"])
      defer { app.terminate() }
      app.buttons["app.settings"].click()
      app.buttons["settings.page.reviews"].click()
      let paired = app.switches["reviewSettings.groupMeaningReading"]
      XCTAssertTrue(paired.waitForExistence(timeout: 5))
      paired.click()
      XCTAssertEqual((paired.value as? NSNumber)?.intValue, 1)
      let autoplay = app.switches["reviewSettings.autoplay"]
      XCTAssertTrue(autoplay.waitForExistence(timeout: 5))
      autoplay.click()
      app.buttons["Done"].click()
      app.buttons["home.reviews"].click()
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      XCTAssertEqual(app.staticTexts["review.prompt"].value as? String, "Meaning")
      input.click()
      input.typeText("one thing")
      app.buttons["review.submit"].click()
      XCTAssertFalse(app.buttons["review.stopAudio"].exists)
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      input.click()
      input.typeText("hitotsu")
      app.buttons["review.submit"].click()
      XCTAssertTrue(
        app.staticTexts["Review session saved"].waitForExistence(timeout: 5), app.debugDescription)
      let stop = app.buttons["review.stopAudio"]
      XCTAssertTrue(stop.waitForExistence(timeout: 5), app.debugDescription)
      stop.click()
      XCTAssertFalse(stop.exists)
    }
    func testTypedReviewMenuExcludesWithoutCreditingTheSubject() {
      let app = launch(["--audio-fixture"])
      defer { app.terminate() }
      app.buttons["home.reviews"].click()
      let input = app.textFields["review.answer"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      input.click()
      let reading = app.staticTexts["review.prompt"].value as? String == "Reading"
      input.typeText(reading ? "bananatsu" : "banana")
      app.buttons["review.submit"].click()
      XCTAssertTrue(
        app.menuButtons["review.corrections"].waitForExistence(timeout: 5), app.debugDescription)
      excludeCurrentReview(in: app)
    }
    func testAnkiReviewMenuExcludesWithTypedCorrectionsDisabled() {
      let app = launch(["--audio-fixture", "--anki-fixture", "--combined-anki-fixture"])
      defer { app.terminate() }
      app.buttons["app.settings"].click()
      app.buttons["settings.page.reviews"].click()
      app.sheets.firstMatch.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300)
      let corrections = app.switches["reviewSettings.corrections"]
      XCTAssertTrue(corrections.waitForExistence(timeout: 5))
      corrections.click()
      XCTAssertEqual((corrections.value as? NSNumber)?.intValue, 0)
      app.buttons["Done"].click()
      app.buttons["home.reviews"].click()
      showAnswer(in: app)
      excludeCurrentReview(in: app)
    }
    func testAnkiLessonMenuExcludesWithoutStartingTheLesson() {
      let app = launch([
        "--audio-fixture", "--lesson-fixture", "--anki-fixture", "--combined-anki-fixture",
      ])
      defer { app.terminate() }
      app.buttons["home.lessons"].click()
      XCTAssertTrue(app.buttons["lesson.quiz"].waitForExistence(timeout: 5))
      app.buttons["lesson.quiz"].click()
      showAnswer(in: app)
      excludeCurrentReview(in: app, lesson: true)
    }
    private func excludeCurrentReview(in app: XCUIApplication, lesson: Bool = false) {
      app.menuButtons["review.corrections"].click()
      app.menuItems["Exclude this item"].click()
      XCTAssertTrue(
        app.staticTexts["Session complete"].waitForExistence(timeout: 5), app.debugDescription)
      let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      image.name = "Native review-menu exclusion"
      image.lifetime = .keepAlways
      add(image)
      app.buttons["Finish session"].click()
      let start = app.buttons[lesson ? "home.lessons" : "home.reviews"]
      XCTAssertTrue(start.waitForExistence(timeout: 5))
      XCTAssertFalse(start.isEnabled)
      XCTAssertTrue(app.buttons["home.extra.excluded"].exists, app.debugDescription)
    }
    func testNativeVocabularyExclusionUpdatesHomeAndCanBeReversed() {
      let app = launch(["--audio-fixture"])
      defer { app.terminate() }
      openAudioSubject(in: app)
      let excluded = app.checkBoxes["subject.excluded"]
      XCTAssertTrue(excluded.waitForExistence(timeout: 5), app.debugDescription)
      if !excluded.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -600) }
      excluded.click()
      let saved = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == 1"), object: excluded)
      XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed, app.debugDescription)
      let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      image.name = "Native vocabulary exclusion"
      image.lifetime = .keepAlways
      add(image)
      app.toolbars.buttons["chevron.backward"].click()
      app.toolbars.buttons["chevron.backward"].click()
      let reviews = app.buttons["home.reviews"]
      XCTAssertTrue(reviews.waitForExistence(timeout: 5))
      XCTAssertFalse(reviews.isEnabled)
      setExclusionControls(false, in: app)
      app.buttons["home.extra.excluded"].click()
      app.buttons["catalog.subject.1"].click()
      XCTAssertTrue(app.staticTexts["subject.meanings"].waitForExistence(timeout: 5))
      XCTAssertFalse(excluded.exists)
      app.toolbars.buttons["chevron.backward"].click()
      app.toolbars.buttons["chevron.backward"].click()
      XCTAssertFalse(reviews.isEnabled)
      setExclusionControls(true, in: app)
      app.buttons["home.extra.excluded"].click()
      let item = app.buttons["catalog.subject.1"]
      XCTAssertTrue(item.waitForExistence(timeout: 5))
      item.click()
      XCTAssertTrue(excluded.waitForExistence(timeout: 5))
      if !excluded.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -600) }
      excluded.click()
      let included = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == 0"), object: excluded)
      XCTAssertEqual(XCTWaiter.wait(for: [included], timeout: 5), .completed, app.debugDescription)
      app.toolbars.buttons["chevron.backward"].click()
      app.toolbars.buttons["chevron.backward"].click()
      XCTAssertTrue(reviews.waitForExistence(timeout: 5))
      XCTAssertTrue(reviews.isEnabled)
    }
    private func setExclusionControls(_ enabled: Bool, in app: XCUIApplication) {
      app.buttons["app.settings"].click()
      app.buttons["settings.page.lessons"].click()
      let control = app.switches["settings.allowExcludeItems"]
      XCTAssertTrue(control.waitForExistence(timeout: 5), app.debugDescription)
      if !control.isHittable {
        app.sheets.firstMatch.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500)
      }
      if (control.value as? NSNumber)?.boolValue != enabled { control.click() }
      XCTAssertEqual((control.value as? NSNumber)?.boolValue, enabled)
      app.buttons["Done"].click()
    }
    private func openAudioSubject(in app: XCUIApplication) {
      app.buttons["app.search"].click()
      let field = app.searchFields.firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      field.click()
      field.typeText("hitotsu")
      let subject = app.buttons["catalog.subject.1"]
      XCTAssertTrue(subject.waitForExistence(timeout: 5), app.debugDescription)
      subject.click()
      XCTAssertTrue(app.buttons["subject.audio"].waitForExistence(timeout: 5), app.debugDescription)
    }
    func testNativePronunciationFailureStaysInline() {
      let app = launch(["--audio-fixture", "--audio-failure-fixture"])
      defer { app.terminate() }
      openAudioSubject(in: app)
      app.buttons["subject.audio"].click()
      XCTAssertTrue(
        app.staticTexts["subject.audioError"].waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(app.alerts.allElementsBoundByIndex.isEmpty)
      XCTAssertTrue(app.buttons["subject.audio"].isEnabled)
    }
    func testNativePronunciationLoadingCanBeCancelled() {
      let app = launch(["--audio-fixture", "--audio-loading-fixture"])
      defer { app.terminate() }
      openAudioSubject(in: app)
      let audio = app.buttons["subject.audio"]
      app.typeKey("j", modifierFlags: [])
      XCTAssertEqual(audio.label, "Cancel loading")
      XCTAssertTrue(audio.isEnabled)
      audio.click()
      XCTAssertEqual(audio.label, "Play reading")
      XCTAssertFalse(app.staticTexts["subject.audioError"].exists)
    }

    func testCombinedAnkiAutoplayWaitsForTheCorrectAssessment() {
      let app = launch(["--audio-fixture", "--anki-fixture", "--combined-anki-fixture"])
      defer { app.terminate() }
      app.buttons["app.settings"].click()
      app.buttons["settings.page.reviews"].click()
      let autoplay = app.switches["reviewSettings.autoplay"]
      XCTAssertTrue(autoplay.waitForExistence(timeout: 5))
      autoplay.click()
      app.buttons["Done"].click()
      app.buttons["home.reviews"].click()
      showAnswer(in: app)
      XCTAssertFalse(app.buttons["review.stopAudio"].exists)
      app.buttons["review.incorrect"].click()
      showAnswer(in: app)
      XCTAssertFalse(app.buttons["review.stopAudio"].exists)
      app.buttons["review.correct"].click()
      XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 5))
      XCTAssertTrue(
        app.buttons["review.stopAudio"].waitForExistence(timeout: 5), app.debugDescription)
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

#endif
