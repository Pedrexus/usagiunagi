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
