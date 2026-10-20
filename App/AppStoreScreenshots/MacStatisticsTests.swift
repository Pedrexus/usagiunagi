#if os(macOS)
  import XCTest

  @MainActor
  final class MacStatisticsTests: XCTestCase {
    func testPastPaceChartExpandsWithoutOpeningASheet() throws {
      continueAfterFailure = false
      let app = XCUIApplication()
      app.launchArguments = [
        "-ApplePersistenceIgnoreState", "YES", "--review-fixture", "--statistics-fixture",
      ]
      app.launch()
      app.activate()
      defer { app.terminate() }
      app.openStudyTab("Stats")
      let dashboard = app.scrollViews["StudyDashboard"]
      XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
      let summary = app.staticTexts["statistics.pace.validationSummary"]
      for _ in 0..<8 {
        if summary.isHittable { break }
        dashboard.scroll(byDeltaX: 0, deltaY: -450)
      }
      XCTAssertTrue(summary.isHittable)
      let value = try XCTUnwrap(summary.value as? String)
      XCTAssertTrue(value.contains("Past average error: 1.8 days across 5 levels."), value)
      let comparison = app.disclosureTriangles["Compare past estimates"]
      XCTAssertTrue(comparison.exists)
      comparison.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).click()
      let chart = app.descendants(matching: .any)
        .matching(identifier: "statistics.pace.validationChart").firstMatch
      let opened = chart.waitForExistence(timeout: 5)
      if !opened {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screen = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screen.lifetime = .keepAlways
        add(screen)
      }
      XCTAssertTrue(opened)
      let note = app.staticTexts["statistics.pace.validationNote"]
      for _ in 0..<4 {
        if note.isHittable { break }
        dashboard.scroll(byDeltaX: 0, deltaY: -300)
      }
      XCTAssertTrue(note.isHittable)
      XCTAssertFalse(app.sheets.firstMatch.exists)
      let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      attachment.name = "Native Mac past pace estimates"
      attachment.lifetime = .keepAlways
      add(attachment)
      comparison.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).click()
      XCTAssertFalse(chart.exists)
      XCTAssertFalse(app.sheets.firstMatch.exists)
    }
  }

#endif

#if os(macOS)
  import XCTest

  @MainActor
  final class MacCatalogTests: XCTestCase {
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
      continueAfterFailure = false
      let app = XCUIApplication()
      app.launchArguments =
        [
          "-ApplePersistenceIgnoreState", "YES", "--review-fixture", "--catalog-fixture",
          "--light-fixture",
        ] + arguments
      app.launch()
      app.activate()
      XCTAssertTrue(app.buttons["home.reviews"].waitForExistence(timeout: 10), app.debugDescription)
      return app
    }

    func testCatalogLevelPagingHidesAnswersAndStageNavigation() {
      let app = launch()
      defer { app.terminate() }
      openHomeRow("Show all", in: app)
      let list = catalogList(in: app)
      let first = app.buttons["catalog.subject.743"]
      reveal(first, in: list, app: app)
      let answers = app.buttons["catalog.answers"]
      XCTAssertTrue(answers.waitForExistence(timeout: 5))
      if answers.label == "Hide answers" { answers.click() }
      XCTAssertTrue(first.label.contains("Answers hidden"))
      XCTAssertFalse(first.label.contains("Alcohol"))
      let previous = app.buttons["catalog.previousLevel"]
      reveal(app.popUpButtons["catalog.level"], in: list, app: app, towardTop: true)
      XCTAssertTrue(previous.exists)
      XCTAssertFalse(previous.isEnabled)
      let next = app.buttons["catalog.nextLevel"]
      next.click()
      let second = app.buttons["catalog.subject.923"]
      reveal(second, in: list, app: app)
      XCTAssertTrue(second.label.contains("Answers hidden"))
      reveal(next, in: list, app: app, towardTop: true)
      next.click()
      XCTAssertTrue(app.staticTexts["No matching subjects"].waitForExistence(timeout: 5))
      previous.click()
      reveal(second, in: list, app: app)
      XCTAssertTrue(second.label.contains("Answers hidden"))
      reveal(previous, in: list, app: app, towardTop: true)
      previous.click()
      reveal(first, in: list, app: app)
      XCTAssertTrue(first.label.contains("Answers hidden"))
      reveal(app.popUpButtons["catalog.level"], in: list, app: app, towardTop: true)
      XCTAssertTrue(previous.exists)
      XCTAssertFalse(previous.isEnabled)
      let imageRadical = app.buttons["catalog.subject.8790"]
      reveal(imageRadical, in: list, app: app)
      XCTAssertTrue(imageRadical.isHittable)
      reveal(app.popUpButtons["catalog.level"], in: list, app: app, towardTop: true)
      capture("Native Mac level catalog with hidden answers", in: app)
      navigateBack(in: app)
      openHomeRow("Guru", in: app)
      reveal(second, in: catalogList(in: app), app: app)
      XCTAssertTrue(second.label.contains("Guru I"))
      XCTAssertTrue(second.label.contains("Answers hidden"))
      XCTAssertFalse(app.buttons["catalog.filters"].exists)
      XCTAssertFalse(app.buttons["catalog.subject.743"].exists)
      answers.click()
      XCTAssertFalse(second.label.contains("Answers hidden"))
      navigateBack(in: app)
      XCTAssertTrue(home(in: app).exists)
    }

    func testCatalogSearchClearsKanaQueryAndOpensDetails() {
      let app = launch()
      defer { app.terminate() }
      app.buttons["app.search"].click()
      let field = app.searchFields.firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      field.click()
      field.typeText("watashijishin")
      let result = app.buttons["catalog.subject.3864"]
      XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(result.label.contains("Personally"))
      clearSearch(field)
      XCTAssertTrue(app.staticTexts["Search saved subjects"].waitForExistence(timeout: 5))
      XCTAssertFalse(result.exists)
      navigateBack(in: app)
      waitUntilAbsent(field, in: app)
      app.buttons["app.search"].click()
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      field.click()
      field.typeText("personally")
      XCTAssertTrue(result.waitForExistence(timeout: 5))
      capture("Native Mac catalog search", in: app)
      result.click()
      reveal(app.buttons["subject.editMaterial"], in: app.scrollViews["subject.scroll"], app: app)
      XCTAssertTrue(app.buttons["subject.editMaterial"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.toolbars.buttons["chevron.backward"].isHittable)
      XCTAssertFalse(field.exists)
      navigateBack(in: app)
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      XCTAssertEqual(field.value as? String, "personally")
      XCTAssertTrue(result.exists)
      navigateBack(in: app)
      waitUntilAbsent(field, in: app)
      XCTAssertTrue(app.buttons["app.search"].waitForExistence(timeout: 5))
    }

    func testCatalogRemainingExplainsReadinessAndKeepsDueItemsFirst() {
      let app = launch()
      defer { app.terminate() }
      openHomeRow("Show remaining", in: app)
      let list = catalogList(in: app)
      let due = app.buttons["catalog.subject.743"]
      let lesson = app.buttons["catalog.subject.578"]
      reveal(due, in: list, app: app)
      reveal(lesson, in: list, app: app)
      XCTAssertTrue(due.exists)
      XCTAssertTrue(due.label.contains("Review now"))
      XCTAssertTrue(lesson.label.contains("Available now"))
      XCTAssertLessThan(due.frame.minY, lesson.frame.minY)
      let locked = app.buttons["catalog.subject.8790"]
      reveal(locked, in: list, app: app, towardTop: true)
      XCTAssertTrue(locked.label.contains("Locked"))
      capture("Native Mac remaining items and next actions", in: app)
      let field = app.searchFields.firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      field.click()
      field.typeText("Somebody")
      XCTAssertTrue(app.staticTexts["No matching subjects"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.buttons["catalog.subject.689"].exists)
      clearSearch(field)
      reveal(due, in: list, app: app)
      XCTAssertTrue(due.label.contains("Review now"))
      navigateBack(in: app)
      XCTAssertTrue(home(in: app).exists)
    }

    func testCatalogExclusionUpdatesAfterReturningFromDetails() {
      let app = launch()
      defer { app.terminate() }
      openHomeRow("Excluded items", in: app)
      let row = app.buttons["catalog.subject.3864"]
      reveal(row, in: catalogList(in: app), app: app)
      row.click()
      let excluded = app.checkBoxes["subject.excluded"]
      reveal(excluded, in: app.scrollViews["subject.scroll"], app: app)
      XCTAssertEqual((excluded.value as? NSNumber)?.intValue, 1)
      excluded.click()
      let off = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == 0"), object: excluded)
      XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 5), .completed, app.debugDescription)
      XCTAssertFalse(app.staticTexts["subject.exclusionError"].exists)
      navigateBack(in: app)
      XCTAssertTrue(app.staticTexts["No matching subjects"].waitForExistence(timeout: 5))
      XCTAssertFalse(row.exists)
      navigateBack(in: app)
      XCTAssertTrue(home(in: app).exists)
    }

    func testCoverageStaysInlineAcrossChartTapsFiltersAndTabChanges() {
      let app = launch(["--statistics-fixture"])
      defer { app.terminate() }
      app.openStudyTab("Stats")
      let dashboard = app.scrollViews["StudyDashboard"]
      XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
      let coverage = app.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@ OR value == %@", "Coverage", "Coverage")
      ).firstMatch
      reveal(coverage, in: dashboard, app: app, towardTop: true)
      coverage.click()
      let row = app.buttons["coverage.target.N5"]
      XCTAssertTrue(row.waitForExistence(timeout: 5))
      let remaining = app.staticTexts["coverage.remaining.N5"]
      XCTAssertFalse(remaining.exists)
      let chart = app.descendants(matching: .any).matching(identifier: "coverage.chart").firstMatch
      reveal(chart, in: dashboard, app: app)
      chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.25)).click()
      chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.75)).click()
      XCTAssertFalse(remaining.exists)
      XCTAssertFalse(app.sheets.firstMatch.exists)
      reveal(row, in: dashboard, app: app)
      row.click()
      XCTAssertTrue(remaining.waitForExistence(timeout: 5))
      XCTAssertFalse(app.sheets.firstMatch.exists)
      XCTAssertFalse(app.buttons["Done"].exists)
      capture("Native Mac inline offline curriculum coverage", in: app)
      reveal(row, in: dashboard, app: app, towardTop: true)
      row.click()
      XCTAssertFalse(remaining.exists)
      let threshold = app.popUpButtons["coverage.threshold"]
      reveal(threshold, in: dashboard, app: app, towardTop: true)
      threshold.click()
      app.menuItems["Burned"].click()
      XCTAssertTrue(text(of: row).contains("at Burned"))
      let system = app.popUpButtons["coverage.system"]
      system.click()
      app.menuItems["School grades"].click()
      let grade = app.buttons["coverage.target.grade1"]
      XCTAssertTrue(grade.waitForExistence(timeout: 5))
      XCTAssertFalse(remaining.exists)
      app.openStudyTab("Home")
      app.openStudyTab("Stats")
      XCTAssertTrue(grade.waitForExistence(timeout: 5))
      XCTAssertFalse(app.sheets.firstMatch.exists)
      XCTAssertFalse(app.buttons["Done"].exists)
      let sources = app.disclosureTriangles["statistics.sources"]
      reveal(sources, in: dashboard, app: app)
      sources.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).click()
      XCTAssertTrue(app.staticTexts["sources.coverage"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.sheets.firstMatch.exists)
      app.openStudyTab("Home")
      app.openStudyTab("Stats")
      reveal(sources, in: dashboard, app: app)
      sources.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).click()
      XCTAssertFalse(app.staticTexts["sources.coverage"].exists)
      XCTAssertFalse(app.sheets.firstMatch.exists)
      XCTAssertFalse(app.buttons["Done"].exists)
    }

    func testUpcomingReviewsShowsStageAndSubjectCountsAndReturns() throws {
      let app = launch()
      defer { app.terminate() }
      let forecast = app.buttons["home.forecast"]
      reveal(forecast, in: home(in: app), app: app)
      let due = try XCTUnwrap(
        forecast.label.split(separator: ":").last?.split(separator: " ").first)
      forecast.click()
      let list = app.descendants(matching: .any).matching(identifier: "upcomingReviews").firstMatch
      XCTAssertTrue(list.waitForExistence(timeout: 5))
      let hour = app.descendants(matching: .any).matching(identifier: "schedule.hour.0").firstMatch
      XCTAssertTrue(hour.waitForExistence(timeout: 5))
      let expectedCount = "\(due) reviews · +\(due) this hour"
      let count = app.staticTexts.matching(
        NSPredicate(format: "label == %@ OR value == %@", expectedCount, expectedCount)
      ).firstMatch
      XCTAssertTrue(count.waitForExistence(timeout: 5))
      hour.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).click()
      XCTAssertTrue(app.staticTexts["Apprentice"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts["Guru"].exists)
      XCTAssertTrue(app.staticTexts["Radicals"].exists)
      capture("Native Mac upcoming review breakdown", in: app)
      navigateBack(in: app)
      XCTAssertTrue(forecast.waitForExistence(timeout: 5))
      XCTAssertEqual(
        forecast.label.split(separator: ":").last?.split(separator: " ").first, due)
    }

    private func home(in app: XCUIApplication) -> XCUIElement {
      app.descendants(matching: .any).matching(identifier: "home.dashboard").firstMatch
    }
    private func catalogList(in app: XCUIApplication) -> XCUIElement {
      let list = app.descendants(matching: .any).matching(identifier: "catalog.list").firstMatch
      XCTAssertTrue(list.waitForExistence(timeout: 5), app.debugDescription)
      return list
    }
    private func openHomeRow(_ prefix: String, in app: XCUIApplication) {
      let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
      reveal(row, in: home(in: app), app: app)
      row.click()
      XCTAssertTrue(catalogList(in: app).exists)
    }
    private func navigateBack(in app: XCUIApplication) {
      let explicit = app.buttons["catalog.back"]
      let back =
        explicit.exists && explicit.isHittable ? explicit : app.toolbars.buttons["chevron.backward"]
      XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
      back.click()
    }
    private func clearSearch(_ field: XCUIElement) {
      field.click()
      field.typeKey("a", modifierFlags: .command)
      field.typeText(XCUIKeyboardKey.delete.rawValue)
    }
    private func waitUntilAbsent(_ element: XCUIElement, in app: XCUIApplication) {
      let absent = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == false"), object: element)
      XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 5), .completed, app.debugDescription)
    }
    private func text(of element: XCUIElement) -> String {
      ([element.label, element.value as? String ?? ""]
        + element.staticTexts.allElementsBoundByIndex.flatMap {
          [$0.label, $0.value as? String ?? ""]
        }).joined(separator: " ")
    }
    private func reveal(
      _ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication,
      towardTop: Bool = false
    ) {
      XCTAssertTrue(scroll.waitForExistence(timeout: 5), app.debugDescription)
      for _ in 0..<40 {
        let viewport = scroll.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 0, dy: 8)
        if element.exists {
          let frame = element.frame
          let visible = viewport.contains(CGPoint(x: frame.midX, y: frame.midY))
          if visible && element.isHittable { return }
          scroll.scroll(byDeltaX: 0, deltaY: frame.minY < viewport.minY ? 180 : -180)
        } else {
          scroll.scroll(byDeltaX: 0, deltaY: towardTop ? 180 : -180)
        }
      }
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "Unreachable native Mac catalog control"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
      capture("Unreachable native Mac catalog control", in: app)
      XCTFail("Could not reveal native Mac control: \(element.debugDescription)")
    }
    private func capture(_ name: String, in app: XCUIApplication) {
      let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      image.name = name
      image.lifetime = .keepAlways
      add(image)
    }
  }
#endif
