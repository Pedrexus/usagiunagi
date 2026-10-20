// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import XCTest

final class ReviewFlowTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    await MainActor.run { XCUIDevice.shared.orientation = .portrait }
  }

  override func tearDown() async throws {
    await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    try await super.tearDown()
  }

  @MainActor private func launchAccountFixture(_ extra: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "ReauthFlowFixture"] + extra
    addTeardownBlock { await MainActor.run { self.clearFixture(app) } }
    app.launch()
    return app
  }
  @MainActor func testAccountExpiryUsesNativeReauthenticationAndPreservesForcedEmail() {
    continueAfterFailure = false
    let app = launchAccountFixture([])
    let warning = app.alerts["Logged out"]
    XCTAssertTrue(warning.waitForExistence(timeout: 10))
    XCTAssertTrue(warning.buttons["Manage tokens on WaniKani"].exists)
    warning.buttons["OK"].tap()
    XCTAssertTrue(app.secureTextFields["login.token"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["login.account"].label.contains("dummy"))
    XCTAssertFalse(app.buttons["login.method"].exists)
    let token = app.secureTextFields["login.token"]
    token.tap()
    token.typeText("other-account-token")
    app.buttons["login.submit"].tap()
    let mismatch = app.staticTexts["login.error"]
    XCTAssertTrue(mismatch.waitForExistence(timeout: 5))
    XCTAssertTrue(mismatch.label.contains("does not match the saved WaniKani account"))
    XCTAssertTrue(app.staticTexts["login.account"].exists)
    token.tap()
    token.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
    token.typeText("fixture-token")
    app.buttons["login.submit"].tap()
    XCTAssertTrue(app.collectionViews["home.dashboard"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.alerts.firstMatch.exists)
    XCUIDevice.shared.press(.home)
    app.activate()
    let settings = app.buttons["app.settings"]
    let foregroundReady = expectation(
      for: NSPredicate(format: "hittable == true"), evaluatedWith: settings)
    wait(for: [foregroundReady], timeout: 5)
    settings.tap()
    XCTAssertTrue(app.buttons["settings.back"].waitForExistence(timeout: 5))
    app.buttons["settings.back"].tap()
    XCTAssertFalse(app.alerts.firstMatch.exists)
  }

  @MainActor func testHibernationWarningStaysDismissedAcrossNativeTabChanges() {
    continueAfterFailure = false
    let app = launchAccountFixture(["HibernationFixture"])
    let warning = app.alerts["Account is Hibernating"]
    XCTAssertTrue(warning.waitForExistence(timeout: 10))
    XCTAssertTrue(warning.buttons["Open WaniKani Website"].exists)
    warning.buttons["OK"].tap()
    for _ in 0..<2 {
      app.buttons["Stats"].firstMatch.tap()
      XCTAssertTrue(app.buttons["coverage.system"].exists || app.buttons["Coverage"].exists)
      app.buttons["Home"].firstMatch.tap()
      XCTAssertTrue(app.collectionViews["home.dashboard"].exists)
      XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    attachHomeScreenshot("SwiftUI tabs after hibernation warning dismissal")
  }

  @MainActor func testAccountWarningWaitsForReviewCloseAndKeepsTheAnswerDraft() {
    continueAfterFailure = false
    let app = launchAccountFixture([
      "DeferredAccountIssue", "-autoSwitchKeyboard", "NO", "-playAudioAutomatically", "NO",
    ])
    let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    start.tap()
    let answer = app.textFields["review.answer"]
    XCTAssertTrue(answer.waitForExistence(timeout: 5))
    answer.tap()
    answer.typeText("hold")
    let draft = answer.value as? String
    XCTAssertFalse((draft ?? "").isEmpty)
    let interrupting = expectation(
      for: NSPredicate(format: "exists == true"), evaluatedWith: app.alerts["Logged out"])
    interrupting.isInverted = true
    wait(for: [interrupting], timeout: 10)
    XCTAssertEqual(answer.value as? String, draft)
    XCTAssertTrue(app.buttons["review.submit"].exists)
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.alerts["Logged out"].waitForExistence(timeout: 5))
    app.alerts["Logged out"].buttons["OK"].tap()
    XCTAssertTrue(app.secureTextFields["login.token"].waitForExistence(timeout: 5))
  }

  @MainActor func testNativeLoginTokenFailuresHibernationAndHomeNavigation() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "LoginFlowFixture"]
    defer { clearFixture(app) }
    for token in ["invalid", "hibernating", "fixture-token"] {
      app.terminate()
      app.launch()
      let field = app.secureTextFields["login.token"]
      XCTAssertTrue(field.waitForExistence(timeout: 10))
      XCTAssertFalse(app.buttons["login.submit"].isEnabled)
      XCTAssertTrue(app.buttons["login.paste"].exists)
      XCTAssertTrue(app.links["login.createToken"].exists)
      field.tap()
      field.typeText(token)
      XCTAssertTrue(app.buttons["login.submit"].isEnabled)
      app.buttons["login.submit"].tap()
      if token == "fixture-token" {
        XCTAssertTrue(app.collectionViews["home.dashboard"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["app.settings"].isHittable)
        XCTAssertFalse(app.secureTextFields["login.token"].exists)
        app.buttons["app.settings"].tap()
        let logout = app.buttons["settings.logout"]
        scrollTo(logout, in: app)
        logout.tap()
        XCTAssertTrue(app.alerts["Log out?"].waitForExistence(timeout: 5))
        app.alerts["Log out?"].buttons["Log out"].tap()
        XCTAssertTrue(app.secureTextFields["login.token"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["login.submit"].isEnabled)
        XCTAssertFalse(app.collectionViews["home.dashboard"].exists)

      } else {
        XCTAssertTrue(app.staticTexts["login.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["login.submit"].isEnabled)
        XCTAssertEqual(app.links["login.reactivate"].exists, token == "hibernating")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        if token == "hibernating" { attachHomeScreenshot("Native login hibernation guidance") }
      }
    }
  }

  @MainActor func testNativeLoginUsesOnlyTheTokenAndSubmitsFromKeyboard() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "LoginFlowFixture"]
    app.launch()
    defer { clearFixture(app) }
    let token = app.secureTextFields["login.token"]
    XCTAssertTrue(token.waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["login.method"].exists)
    XCTAssertFalse(app.secureTextFields["login.password"].exists)
    XCTAssertFalse(app.textFields["login.email"].exists)
    token.tap()
    token.typeText("fixture-token\n")
    XCTAssertTrue(app.collectionViews["home.dashboard"].waitForExistence(timeout: 10))
  }

  @MainActor private func launchNativeHome(_ arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--review-fixture"] + arguments
    app.launch()
    XCTAssertTrue(app.buttons["app.settings"].waitForExistence(timeout: 15), app.debugDescription)
    XCTAssertTrue(
      app.collectionViews["home.dashboard"].waitForExistence(timeout: 15), app.debugDescription)
    XCTAssertFalse(app.otherElements["startup.failure"].exists)
    return app
  }
  @MainActor private func navigateNativeBack(in app: XCUIApplication) {
    let back = app.navigationBars.buttons.firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
    back.tap()
  }
  @MainActor private func closeNativeStudy(_ app: XCUIApplication) {
    if app.buttons["lesson.back"].exists {
      app.buttons["lesson.back"].tap()
    } else {
      app.navigationBars.buttons.firstMatch.tap()
    }
    XCTAssertTrue(app.buttons["app.settings"].waitForExistence(timeout: 5), app.debugDescription)
  }
  @MainActor private func requestNativeLink(_ route: String) throws {
    try requestNativeURL(URL(string: "usagiunagi:///" + route)!)
  }
  @MainActor private func requestNativeURL(_ url: URL) throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent(
      "usagi-warm-link.json")
    let request = ["id": UUID().uuidString, "url": url.absoluteString]
    try JSONSerialization.data(withJSONObject: request).write(to: marker, options: .atomic)
    let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
      .firstMatch
    if open.waitForExistence(timeout: 5) { open.tap() }
  }
  @MainActor func testNativeTabsPreserveWarmStudyLinksAndReturnToStatistics() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    defer { app.terminate() }
    for route in ["reviews", "lessons", "subject/1"] {
      app.terminate()
      app.launchArguments =
        ["--review-fixture", "--light-fixture"]
        + (route == "lessons" ? ["--lesson-fixture"] : [])
      app.launch()
      let stats = app.buttons["Stats"].firstMatch
      XCTAssertTrue(stats.waitForExistence(timeout: 10))
      stats.tap()
      XCTAssertTrue(app.buttons["Coverage"].waitForExistence(timeout: 5))
      try requestNativeLink(route)
      switch route {
      case "reviews":
        XCTAssertTrue(
          app.textFields["review.answer"].waitForExistence(timeout: 10), app.debugDescription)
      case "lessons":
        XCTAssertTrue(
          app.buttons["lesson.quiz"].waitForExistence(timeout: 10), app.debugDescription)
      default:
        XCTAssertTrue(
          app.staticTexts["subject.characters"].waitForExistence(timeout: 10), app.debugDescription)
      }
      if route == "reviews" {
        let field = app.textFields["review.answer"]
        field.tap()
        field.typeText("hold")
        let draft = field.value as? String
        XCTAssertFalse((draft ?? "").isEmpty)
        app.buttons["review.settings"].tap()
        XCTAssertTrue(app.buttons["reviewSettings.done"].waitForExistence(timeout: 5))
        try requestNativeLink("subject/1")
        XCTAssertTrue(app.buttons["reviewSettings.done"].isHittable, app.debugDescription)
        app.buttons["reviewSettings.done"].tap()
        XCTAssertEqual(field.value as? String, draft)
        XCTAssertTrue(
          app.buttons["applink.open"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["applink.open"].tap()
        XCTAssertTrue(app.staticTexts["subject.characters"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(field.value as? String, draft)
      }
      closeNativeStudy(app)
      XCTAssertTrue(app.buttons["Coverage"].waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertFalse(app.alerts.firstMatch.exists)
    }
  }

  @MainActor func testColdStudyLinkWaitsForSignInBeforeOpeningTheReview() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-FASTLANE_SNAPSHOT", "YES", "LoginFlowFixture", "SingleReviewFixture",
      "-playAudioAutomatically", "NO", "-autoSwitchKeyboard", "NO",
    ]
    defer { clearFixture(app) }
    app.open(URL(string: "usagiunagi:///reviews")!)
    let token = app.secureTextFields["login.token"]
    XCTAssertTrue(token.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertFalse(app.textFields["review.answer"].exists)
    token.tap()
    token.typeText("fixture-token")
    app.buttons["login.submit"].tap()
    XCTAssertTrue(
      app.textFields["review.answer"].waitForExistence(timeout: 10), app.debugDescription)
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.collectionViews["home.dashboard"].waitForExistence(timeout: 5))
  }
  @MainActor func testShellColdReviewLessonAndSubjectLinksReturnToHome() {
    continueAfterFailure = false
    let app = XCUIApplication()
    defer { app.terminate() }
    for scheme in ["usagiunagi", "tsurukame"] {
      for route in ["reviews", "lessons", "subject/1"] {
        app.terminate()
        app.launchArguments =
          ["--review-fixture", "--light-fixture"]
          + (route == "lessons" ? ["--lesson-fixture"] : [])
        app.open(URL(string: scheme + ":///" + route)!)
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
        closeNativeStudy(app)
        XCTAssertTrue(
          app.collectionViews["home.dashboard"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.otherElements["startup.failure"].exists)
      }
    }
  }

  @MainActor func testShellFullRefreshUpdatesProgressAndKeepsBlockingAfterForeground() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "ShellFlowFixture"]
    app.launch()
    defer { clearFixture(app) }
    let home = app.collectionViews["home.dashboard"]
    XCTAssertTrue(home.waitForExistence(timeout: 10))
    XCTAssertEqual(app.staticTexts["app.username"].label, "Fred")
    XCTAssertTrue(app.staticTexts["app.level"].label.contains("Level 24"))
    XCTAssertTrue(app.staticTexts["app.level"].label.contains("864"))
    let pullStart = home.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2))
    let pullEnd = home.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.85))
    pullStart.press(forDuration: 0.05, thenDragTo: pullEnd)
    attachHomeScreenshot("Home after pull to refresh")
    let overlay = app.descendants(matching: .any).matching(identifier: "app.fullRefresh").firstMatch
    XCTAssertTrue(overlay.waitForExistence(timeout: 5))
    let indicator = app.progressIndicators["app.refreshProgress"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 5))
    let advancing = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in (indicator.value as? String)?.contains("25") == true },
      object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 7), .completed)
    attachHomeScreenshot("Native full refresh progress")
    XCTAssertFalse(app.buttons["app.settings"].isEnabled)
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(overlay.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["app.settings"].isEnabled)
    let completed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: overlay)
    XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 20), .completed)
    XCTAssertTrue(app.buttons["app.settings"].isEnabled)
    XCTAssertEqual(app.staticTexts["app.username"].label, "Fred")
    app.buttons["app.settings"].tap()
    XCTAssertTrue(app.buttons["settings.back"].waitForExistence(timeout: 5))
    app.buttons["settings.back"].tap()
    XCTAssertTrue(home.waitForExistence(timeout: 5))
  }

  @MainActor private func attachHomeScreenshot(_ title: String) {
    let attachment = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    attachment.name = title
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  @MainActor func testHomeProgressCountsChartsAndRefreshSurviveRotation() {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    addTeardownBlock { await MainActor.run { XCUIDevice.shared.orientation = .portrait } }
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "-showPreviousLevelGraph", "NO"]
    app.launch()
    defer { clearFixture(app) }
    let home = app.descendants(matching: .any).matching(identifier: "home.dashboard").firstMatch
    XCTAssertTrue(home.waitForExistence(timeout: 10))
    attachHomeScreenshot("SwiftUI Home study actions and forecast")
    let forecast = app.descendants(matching: .any).matching(identifier: "home.forecast").firstMatch
    scrollTo(forecast, in: app)
    XCTAssertTrue(forecast.exists)
    XCTAssertFalse(app.buttons["Done"].exists)
    let kanji = app.descendants(matching: .any).matching(identifier: "home.level.24.kanji")
      .firstMatch
    scrollTo(kanji, in: app)
    XCTAssertEqual(kanji.label, "Kanji: 1 of 25 at Guru, 12 in Apprentice, 4 in lessons, 8 locked")
    attachHomeScreenshot("SwiftUI Home level progress")
    let burned = app.buttons["home.stage.4"]
    scrollTo(burned, in: app)
    XCTAssertTrue(burned.label.contains("2,056"))
    scrollTo(app.buttons["home.burned"], in: app)
    XCTAssertTrue(app.buttons["home.burned"].exists)
    attachHomeScreenshot("SwiftUI Home SRS distribution")
    XCUIDevice.shared.orientation = .landscapeLeft
    let rotated = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
    scrollTo(burned, in: app)
    XCTAssertTrue(burned.isHittable)
    attachHomeScreenshot("SwiftUI Home landscape SRS distribution")
    XCUIDevice.shared.orientation = .portrait
    let reviews = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    scrollTo(reviews, in: app, towardTop: true)
    let availability = reviews.label
    home.swipeDown(velocity: .slow)
    XCTAssertTrue(reviews.waitForExistence(timeout: 5))
    XCTAssertEqual(reviews.label, availability)
    XCTAssertFalse(app.alerts.firstMatch.exists)
  }

  @MainActor func testHomeDisablesEmptyStudyQueuesAndHidesVacationActions() {
    continueAfterFailure = false
    for fixture in ["HomeEmptyFixture", "HomeLimitFixture", "HomeVacationFixture"] {
      let app = XCUIApplication()
      app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", fixture]
      app.launch()
      defer { clearFixture(app) }
      XCTAssertTrue(
        app.descendants(matching: .any).matching(identifier: "home.dashboard").firstMatch
          .waitForExistence(timeout: 10))
      let reviews = app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH %@", "Start reviews")
      ).firstMatch
      let lessons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Lessons"))
        .firstMatch
      let choose = app.buttons["Choose lessons"]
      if fixture == "HomeVacationFixture" {
        XCTAssertTrue(
          app.descendants(matching: .any).matching(identifier: "app.vacation").firstMatch.exists)
        XCTAssertFalse(reviews.exists)
        XCTAssertFalse(lessons.exists)
        XCTAssertFalse(choose.exists)
        XCTAssertFalse(
          app.descendants(matching: .any).matching(identifier: "home.forecast").firstMatch.exists)
        let progress = app.descendants(matching: .any).matching(identifier: "home.level.24.kanji")
          .firstMatch
        scrollTo(progress, in: app)
        XCTAssertTrue(progress.isHittable)
      } else {
        XCTAssertFalse(lessons.isEnabled)
        XCTAssertFalse(choose.isEnabled)
        XCTAssertEqual(reviews.isEnabled, fixture != "HomeEmptyFixture")
        if fixture == "HomeLimitFixture" {
          XCTAssertTrue(lessons.label.contains("Apprentice limit reached"))
        }
      }
    }
  }

  @MainActor private func launchDeveloperOptions() -> XCUIApplication {
    let app = launchSettings(extra: ["DeveloperFlowFixture", "AudioFlowFixture"])
    let developer = app.buttons["settings.developer"]
    scrollTo(developer, in: app)
    developer.tap()
    XCTAssertTrue(app.navigationBars["Developer options"].waitForExistence(timeout: 5))
    return app
  }

  @MainActor private func editDeveloperEndpoint(
    _ value: String, in app: XCUIApplication, action: String
  ) {
    app.buttons["developer.endpoint"].tap()
    let alert = app.alerts["API base URL"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    let field = alert.textFields.firstMatch
    let current = field.value as? String ?? ""
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
    XCTAssertEqual(field.value as? String, value)
    alert.buttons[action].tap()
    XCTAssertFalse(alert.exists)
  }

  @MainActor func testDeveloperEndpointCancelValidationPersistenceAndReset() {
    continueAfterFailure = false
    let app = launchDeveloperOptions()
    defer { clearFixture(app) }
    let endpoint = app.buttons["developer.endpoint"]
    let standard = "https://api.wanikani.com/v2"
    XCTAssertTrue(endpoint.label.contains(standard))
    editDeveloperEndpoint("http://localhost:8080/cancelled", in: app, action: "Cancel")
    XCTAssertTrue(endpoint.label.contains(standard))
    editDeveloperEndpoint("not-a-url", in: app, action: "Save")
    XCTAssertTrue(app.staticTexts["developer.endpoint.error"].waitForExistence(timeout: 5))
    XCTAssertTrue(endpoint.label.contains(standard))
    editDeveloperEndpoint("http://localhost:8080/api///", in: app, action: "Save")
    XCTAssertTrue(endpoint.label.contains("http://localhost:8080/api"))
    XCTAssertFalse(endpoint.label.contains("api///"))
    XCTAssertFalse(app.staticTexts["developer.endpoint.error"].exists)
    app.navigationBars["Developer options"].buttons.firstMatch.tap()
    let developer = app.buttons["settings.developer"]
    scrollTo(developer, in: app)
    developer.tap()
    XCTAssertTrue(endpoint.waitForExistence(timeout: 5))
    XCTAssertTrue(endpoint.label.contains("http://localhost:8080/api"))
    endpoint.tap()
    app.alerts["API base URL"].buttons["Reset to default"].tap()
    XCTAssertTrue(endpoint.label.contains(standard))
  }

  @MainActor func testDeveloperCacheFeedbackAndNativeDatabaseSharing() {
    continueAfterFailure = false
    let app = launchDeveloperOptions()
    defer { clearFixture(app) }
    app.buttons["developer.clearAvatarCache"].tap()
    let confirmation = app.alerts["Image cache cleared"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
    confirmation.buttons["OK"].tap()
    XCTAssertFalse(confirmation.exists)
    let screenshot = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    screenshot.name = "Native developer options and diagnostics"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["developer.export"].tap()
    let save = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "Save to Files")
    ).firstMatch
    XCTAssertTrue(save.waitForExistence(timeout: 10))
    let close = app.buttons["Close"].firstMatch
    let cancel = app.buttons["Cancel"].firstMatch
    if close.exists {
      close.tap()
    } else if cancel.exists {
      cancel.tap()
    } else {
      let popup = app.popovers.firstMatch
      XCTAssertTrue(popup.exists)
      app.otherElements["PopoverDismissRegion"].coordinate(
        withNormalizedOffset: CGVector(dx: popup.frame.midX < app.frame.midX ? 0.95 : 0.05, dy: 0.5)
      ).tap()
    }
    XCTAssertFalse(save.exists)
    XCTAssertTrue(app.navigationBars["Developer options"].exists)
  }

  @MainActor private func launchOfflineAudio(extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--review-fixture", "--audio-fixture", "--light-fixture"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["app.settings"].waitForExistence(timeout: 10), app.debugDescription)
    app.buttons["app.settings"].tap()
    XCTAssertTrue(app.buttons["settings.page.reviews"].waitForExistence(timeout: 5))
    app.buttons["settings.page.reviews"].tap()
    let audio = app.buttons["reviewSettings.offlineAudio"]
    scrollTo(audio, in: app)
    audio.tap()
    XCTAssertTrue(app.navigationBars["Offline Audio"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.switches["offlineAudio.voice.1"].waitForExistence(timeout: 5))
    return app
  }

  @MainActor func testOfflineAudioVoiceChoicesAndCellularSettingPersist() {
    continueAfterFailure = false
    let app = launchOfflineAudio(extra: ["AudioHeldFixture"])
    defer { app.terminate() }
    let enabled = app.switches["offlineAudio.enabled"]
    let cellular = app.switches["offlineAudio.cellular"]
    let first = app.switches["offlineAudio.voice.1"]
    let second = app.switches["offlineAudio.voice.2"]
    XCTAssertFalse(cellular.isEnabled)
    XCTAssertFalse(first.isEnabled)
    setSettingsSwitch(enabled, on: true, in: app)
    XCTAssertEqual(first.value as? String, "1")
    XCTAssertEqual(second.value as? String, "1")
    setSettingsSwitch(first, on: false, in: app)
    XCTAssertEqual(second.value as? String, "1")
    setSettingsSwitch(cellular, on: true, in: app)
    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = "SwiftUI offline audio with selected voices"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.navigationBars["Offline Audio"].buttons.firstMatch.tap()
    let audio = app.buttons["reviewSettings.offlineAudio"]
    scrollTo(audio, in: app)
    audio.tap()
    XCTAssertTrue(enabled.waitForExistence(timeout: 5))
    XCTAssertEqual(first.value as? String, "0")
    XCTAssertEqual(second.value as? String, "1")
    XCTAssertEqual(cellular.value as? String, "1")
    setSettingsSwitch(enabled, on: false, in: app)
    app.alerts["Delete offline audio?"].buttons["Keep"].tap()
    XCTAssertFalse(cellular.isEnabled)
    XCTAssertTrue(app.staticTexts["Downloads disabled"].exists)
    XCTAssertFalse(app.alerts["Delete offline audio?"].exists)
  }

  @MainActor func testOfflineAudioDownloadsKeepAndExplicitDeletion() {
    continueAfterFailure = false
    let app = launchOfflineAudio()
    defer { app.terminate() }
    let enabled = app.switches["offlineAudio.enabled"]
    setSettingsSwitch(enabled, on: true, in: app)
    let status = app.staticTexts["Up to date"]
    XCTAssertTrue(status.waitForExistence(timeout: 15))
    let cache = app.descendants(matching: .any).matching(identifier: "offlineAudio.cacheSize")
      .firstMatch
    let saved = settingsPickerText(cache)
    setSettingsSwitch(enabled, on: false, in: app)
    app.alerts["Delete offline audio?"].buttons["Keep"].tap()
    XCTAssertEqual(settingsPickerText(cache), saved)
    let deletion = app.buttons["offlineAudio.delete"]
    scrollTo(deletion, in: app)
    deletion.tap()
    app.alerts["Delete offline audio?"].buttons["Delete"].tap()
    XCTAssertFalse(app.alerts["Delete offline audio?"].exists)
    XCTAssertNotEqual(settingsPickerText(cache), saved)
    XCTAssertEqual(enabled.value as? String, "0")
    XCTAssertEqual(app.switches["offlineAudio.voice.1"].value as? String, "1")
    XCTAssertEqual(app.switches["offlineAudio.voice.2"].value as? String, "1")
    XCTAssertFalse(app.staticTexts["offlineAudio.error"].exists)
  }

  @MainActor func testOfflineAudioFailuresRemainVisibleAndCanRetry() {
    continueAfterFailure = false
    let app = launchOfflineAudio(extra: ["AudioFailedFixture"])
    defer { app.terminate() }
    let enabled = app.switches["offlineAudio.enabled"]
    setSettingsSwitch(enabled, on: true, in: app)
    let error = app.staticTexts["offlineAudio.error"]
    XCTAssertTrue(error.waitForExistence(timeout: 15))
    XCTAssertFalse(app.staticTexts["Up to date"].exists)
    let retry = app.buttons["offlineAudio.retry"]
    scrollTo(retry, in: app)
    retry.tap()
    XCTAssertTrue(error.waitForExistence(timeout: 15))
    XCTAssertEqual(enabled.value as? String, "1")
    setSettingsSwitch(enabled, on: false, in: app)
    app.alerts["Delete offline audio?"].buttons["Keep"].tap()
    XCTAssertTrue(app.navigationBars["Offline Audio"].exists)
  }

  @MainActor private func launchFontLibrary(extra: [String] = []) -> XCUIApplication {
    let app = launchNativeReview(extra: extra)
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("personally")
    app.buttons["review.settings"].tap()
    app.buttons["reviewSettings.fonts"].tap()
    XCTAssertTrue(app.navigationBars["Select Fonts"].waitForExistence(timeout: 5))
    return app
  }

  @MainActor func testFontSelectionPersistsWhenReturningToAnUnchangedReviewDraft() {
    continueAfterFailure = false
    let app = launchFontLibrary()
    defer { clearFixture(app) }
    let selection = app.switches["font.selection.font-ready.ttf"]
    XCTAssertTrue(selection.waitForExistence(timeout: 5))
    XCTAssertEqual(selection.value as? String, "0")
    setSettingsSwitch(selection, on: true, in: app)
    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = "SwiftUI font library selection"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.navigationBars["Select Fonts"].buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Quick settings"].waitForExistence(timeout: 5))
    app.buttons["reviewSettings.done"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "personally")
    app.buttons["review.settings"].tap()
    app.buttons["reviewSettings.fonts"].tap()
    XCTAssertTrue(selection.waitForExistence(timeout: 5))
    XCTAssertEqual(selection.value as? String, "1")
  }

  @MainActor func testFontDownloadsCanBeCancelledRetriedAndDeletionCancelled() {
    continueAfterFailure = false
    let app = launchFontLibrary()
    defer { clearFixture(app) }
    let held = app.buttons["font.download.font-held.ttf"]
    scrollTo(held, in: app)
    held.tap()
    let cancel = app.buttons["font.cancel.font-held.ttf"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    cancel.tap()
    XCTAssertTrue(held.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["font.error.font-held.ttf"].exists)
    let failed = app.buttons["font.download.font-failed.ttf"]
    scrollTo(failed, in: app, towardTop: true)
    failed.tap()
    let error = app.staticTexts["font.error.font-failed.ttf"]
    XCTAssertTrue(error.waitForExistence(timeout: 5))
    XCTAssertTrue(error.label.contains("503"))
    XCTAssertTrue(failed.label.contains("Retry"))
    failed.tap()
    XCTAssertTrue(error.waitForExistence(timeout: 5))
    let deletion = app.buttons["fonts.deleteAll"]
    scrollTo(deletion, in: app)
    deletion.tap()
    let confirmation = app.buttons["Delete downloaded fonts"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
    let dismiss = app.buttons["Cancel"].firstMatch
    if dismiss.exists {
      dismiss.tap()
    } else {
      let popup = app.popovers.firstMatch
      XCTAssertTrue(popup.exists)
      app.navigationBars["Select Fonts"].coordinate(
        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
      ).tap()
    }
    XCTAssertFalse(confirmation.exists)
    XCTAssertTrue(deletion.isHittable)
    XCTAssertTrue(app.navigationBars["Select Fonts"].exists)
  }

  @MainActor func testFontDownloadContinuesAfterLeavingThePicker() {
    continueAfterFailure = false
    let app = launchFontLibrary()
    defer { clearFixture(app) }
    let download = app.buttons["font.download.font-download.ttf"]
    scrollTo(download, in: app)
    download.tap()
    let progress = app.descendants(matching: .any).matching(
      identifier: "font.progress.font-download.ttf"
    ).firstMatch
    XCTAssertTrue(progress.waitForExistence(timeout: 5))
    app.buttons["reviewSettings.done"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "personally")
    app.buttons["review.settings"].tap()
    app.buttons["reviewSettings.fonts"].tap()
    let selected = app.switches["font.selection.font-download.ttf"]
    XCTAssertTrue(selected.waitForExistence(timeout: 15))
    XCTAssertEqual(selected.value as? String, "1")
  }

  @MainActor
  func testReviewFeedbackSettingsApplyIndependentlyAndPreserveDraft() {
    continueAfterFailure = false
    let app = launchNativeReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("one thing")
    app.buttons["review.submit"].tap()
    let feedback = app.descendants(matching: .any).matching(identifier: "review.success").firstMatch
    XCTAssertTrue(feedback.waitForExistence(timeout: 5))
    XCTAssertTrue(feedback.label.contains("Previous answer correct"))
    XCTAssertFalse(feedback.label.contains("+1"))
    XCTAssertFalse(feedback.label.contains("Estimated SRS"))
    field.tap()
    field.typeText("hito")
    XCTAssertEqual(field.value as? String, "ひと")
    app.buttons["review.settings"].tap()
    let correct = app.switches["reviewSettings.correctAnswerFeedback"]
    scrollTo(correct, in: app)
    setSettingsSwitch(correct, on: false, in: app)
    XCTAssertEqual(app.switches["reviewSettings.completedItemFeedback"].value as? String, "1")
    XCTAssertEqual(app.switches["reviewSettings.srsMilestoneFeedback"].value as? String, "1")
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, "ひと")
    let correctFeedback = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier == %@ AND label CONTAINS %@", "review.success",
        "Previous answer correct"))
    XCTAssertEqual(correctFeedback.count, 0)
    app.buttons["review.settings"].tap()
    scrollTo(correct, in: app)
    XCTAssertEqual(correct.value as? String, "0")
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, "ひと")
    field.typeText("tsu")
    XCTAssertEqual(field.value as? String, "ひとつ")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testCompletionAndMilestoneFeedbackRemainReadableWithReducedMotion() {
    continueAfterFailure = false
    changeReduceMotion(to: true, restoreAfterTest: true)
    let app = launchNativeReview(extra: [
      "--review-feedback-fixture", "--anki-fixture", "--combined-anki-fixture",
    ])
    defer { clearFixture(app) }
    app.buttons["review.submit"].tap()
    app.buttons["review.correct"].tap()
    let feedback = app.descendants(matching: .any).matching(identifier: "review.success").firstMatch
    XCTAssertTrue(feedback.waitForExistence(timeout: 5))
    XCTAssertTrue(feedback.label.contains("Previous answer correct"))
    XCTAssertTrue(feedback.label.contains("+1 completed"))
    XCTAssertTrue(feedback.label.contains("Estimated SRS stage: Guru"))
    XCTAssertTrue(app.staticTexts["review.progress"].label.contains("1 completed"))
    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = "Native review feedback with Reduce Motion"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["review.settings"].tap()
    let completed = app.switches["reviewSettings.completedItemFeedback"]
    scrollTo(completed, in: app)
    setSettingsSwitch(completed, on: false, in: app)
    app.buttons["reviewSettings.done"].tap()
    XCTAssertFalse(feedback.label.contains("+1 completed"))
    XCTAssertTrue(feedback.label.contains("Estimated SRS stage: Guru"))
    app.buttons["review.settings"].tap()
    let milestone = app.switches["reviewSettings.srsMilestoneFeedback"]
    scrollTo(milestone, in: app)
    setSettingsSwitch(milestone, on: false, in: app)
    app.buttons["reviewSettings.done"].tap()
    XCTAssertFalse(feedback.label.contains("Estimated SRS"))
    XCTAssertTrue(feedback.label.contains("Previous answer correct"))
    app.buttons["review.submit"].tap()
    app.buttons["review.correct"].tap()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 10))
  }

  @MainActor private func changeReduceMotion(to enabled: Bool, restoreAfterTest: Bool = false) {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    defer { settings.terminate() }
    let control = settings.switches["Reduce Motion"]
    if !control.exists {
      for title in ["Accessibility", "Settings"] {
        let back = settings.navigationBars.buttons[title].firstMatch
        if back.exists { back.tap() }
      }
      let sidebar = settings.collectionViews["com.apple.settings.sidebar.collectionView"]
      let navigation = sidebar.exists ? sidebar : settings
      navigation.swipeDown(velocity: .fast)
      navigation.swipeDown(velocity: .fast)
      let accessibility = settings.buttons["Accessibility"]
      for _ in 0..<8 {
        if accessibility.exists && accessibility.isHittable { break }
        navigation.swipeUp()
      }
      XCTAssertTrue(accessibility.waitForExistence(timeout: 5))
      accessibility.tap()
      let motion = settings.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@", "Motion")
      ).firstMatch
      for _ in 0..<8 {
        if motion.exists && motion.isHittable { break }
        settings.swipeUp()
      }
      XCTAssertTrue(motion.waitForExistence(timeout: 5))
      motion.tap()
    }
    XCTAssertTrue(control.waitForExistence(timeout: 5))
    let previous = control.value as? String == "1"
    if restoreAfterTest {
      addTeardownBlock { [self] in
        await MainActor.run { changeReduceMotion(to: previous) }
      }
    }
    setSettingsSwitch(control, on: enabled, in: settings)
  }

  @MainActor
  func testCoverageStaysInlineAcrossChartTapsFiltersAndTabChanges() {
    continueAfterFailure = false
    let app = launchNativeHome(["--statistics-fixture", "--light-fixture"])
    defer { app.terminate() }
    app.buttons["Stats"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Coverage"].waitForExistence(timeout: 5))
    app.buttons["Coverage"].tap()
    let row = app.buttons["coverage.target.N5"]
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    if !row.isHittable { app.swipeUp() }
    let remaining = app.staticTexts["coverage.remaining.N5"]
    XCTAssertFalse(remaining.exists)
    let chart = app.descendants(matching: .any).matching(identifier: "coverage.chart").firstMatch
    XCTAssertTrue(chart.exists)
    chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.25)).tap()
    chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.75)).tap()
    XCTAssertFalse(remaining.exists)
    XCTAssertFalse(app.navigationBars["N5"].exists)
    row.tap()
    XCTAssertTrue(remaining.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Stats"].firstMatch.isHittable)
    XCTAssertFalse(app.buttons["Done"].exists)
    let expanded = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    expanded.name = "Inline offline curriculum coverage"
    expanded.lifetime = .keepAlways
    add(expanded)
    row.tap()
    XCTAssertFalse(remaining.exists)
    app.swipeDown()
    app.buttons["coverage.threshold"].tap()
    app.buttons["Burned"].tap()
    XCTAssertTrue(row.label.contains("at Burned"))
    app.buttons["coverage.system"].tap()
    app.buttons["School grades"].tap()
    XCTAssertTrue(app.buttons["coverage.target.grade1"].waitForExistence(timeout: 5))
    XCTAssertFalse(remaining.exists)
    app.buttons["Home"].firstMatch.tap()
    app.buttons["Stats"].firstMatch.tap()
    XCTAssertTrue(app.buttons["coverage.target.grade1"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Done"].exists)
    XCTAssertFalse(app.navigationBars["N5"].exists)
    let sources = app.buttons["statistics.sources"]
    for _ in 0..<8 where !sources.isHittable { app.swipeUp() }
    XCTAssertTrue(sources.isHittable)
    sources.tap()
    XCTAssertTrue(app.staticTexts["sources.coverage"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Done"].exists)
    XCTAssertTrue(app.buttons["Home"].firstMatch.isHittable)
    app.buttons["Home"].firstMatch.tap()
    app.buttons["Stats"].firstMatch.tap()
    for _ in 0..<8 where !sources.isHittable { app.swipeUp() }
    XCTAssertTrue(sources.isHittable)
    sources.tap()
    XCTAssertFalse(app.staticTexts["sources.coverage"].exists)
    XCTAssertFalse(app.buttons["Done"].exists)
  }

  @MainActor
  func testUpcomingReviewsShowsStageAndSubjectCountsAndReturns() throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let app = launchNativeHome(["--light-fixture"])
    defer { app.terminate() }
    let forecast = app.descendants(matching: .any).matching(identifier: "home.forecast").firstMatch
    scrollTo(forecast, in: app)
    XCTAssertTrue(forecast.waitForExistence(timeout: 10))
    let due = try XCTUnwrap(forecast.label.split(separator: ":").last?.split(separator: " ").first)
    forecast.tap()
    XCTAssertTrue(app.navigationBars["Upcoming reviews"].waitForExistence(timeout: 5))
    let hour = app.descendants(matching: .any).matching(identifier: "schedule.hour.0").firstMatch
    XCTAssertTrue(hour.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["\(due) reviews · +\(due) this hour"].exists)
    hour.tap()
    XCTAssertTrue(app.staticTexts["Apprentice"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Guru"].exists)
    XCTAssertTrue(app.staticTexts["Radicals"].exists)
    let attachment = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    attachment.name = "SwiftUI upcoming review breakdown"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.navigationBars["Upcoming reviews"].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(forecast.waitForExistence(timeout: 5))
  }

  @MainActor
  func testSummaryShowsMissedMeaningAndOpensSubjectDetails() {
    continueAfterFailure = false
    let app = launchNativeReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("banana")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    app.buttons["review.reveal"].tap()
    app.buttons["review.submit"].tap()
    let complete = app.staticTexts["Review session saved"]
    for _ in 0..<3 {
      if complete.exists { break }
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      let answer =
        app.staticTexts["review.prompt"].label.contains("Reading") ? "hitotsu" : "one thing"
      field.tap()
      field.typeText(answer)
      app.buttons["review.submit"].tap()
    }
    XCTAssertTrue(complete.waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts[
        "Completed answers are saved on this device and sync automatically when online."
      ].isHittable)
    XCTAssertTrue(app.staticTexts["Missed · level 1"].exists)
    let missed = app.buttons["summary.subject.0"]
    XCTAssertTrue(missed.waitForExistence(timeout: 5))
    XCTAssertTrue(missed.label.contains("Meaning missed"))
    XCTAssertFalse(missed.label.contains("Reading missed"))
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = "SwiftUI missed-subject summary"
    attachment.lifetime = .keepAlways
    add(attachment)
    missed.tap()
    XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(missed.waitForExistence(timeout: 5))
    app.buttons["review.finish"].tap()
    XCTAssertTrue(
      app.buttons["app.settings"]
        .waitForExistence(timeout: 5))
  }

  @MainActor
  private func launchPractice(anki: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-FASTLANE_SNAPSHOT", "YES", "-ankiMode", anki ? "YES" : "NO",
      "-ankiModeTaskType", "2", "-autoSwitchKeyboard", "NO",
      "-playAudioAutomatically", "NO", "-allowSkippingReviews", "NO",
    ]
    app.launch()
    let tab = app.buttons["Practice"].firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: 10))
    tab.tap()
    XCTAssertTrue(app.buttons["practice.katakana"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    attachment.name = "Native SwiftUI practice menu"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["practice.katakana"].tap()
    XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 10))
    return app
  }

  @MainActor
  func testPracticeMenuPreservesTypedReviewsAndReturns() {
    continueAfterFailure = false
    let app = launchPractice()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["review.question"].value as? String, "ア")
    XCTAssertTrue(app.staticTexts["review.prompt"].label.contains("Reading"))
    field.tap()
    field.typeText("a")
    app.buttons["review.submit"].tap()
    let next = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.staticTexts["review.question"].value as? String == "イ"
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 5), .completed)
    field.tap()
    field.typeText("i")
    let draft = field.value as? String
    app.buttons["review.settings"].tap()
    XCTAssertTrue(app.buttons["reviewSettings.done"].waitForExistence(timeout: 5))
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, draft)
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 5))
    app.navigationBars["Review Summary"].buttons["Done"].tap()
    XCTAssertTrue(app.buttons["practice.katakana"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testPracticeMenuPreservesAnkiReadingMode() {
    continueAfterFailure = false
    let app = launchPractice(anki: true)
    defer { clearFixture(app) }
    XCTAssertFalse(app.textFields["review.answer"].exists)
    XCTAssertFalse(app.buttons["review.voice"].exists)
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.correct"].waitForExistence(timeout: 5))
    app.buttons["review.correct"].tap()
    let next = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.staticTexts["review.question"].value as? String == "イ"
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 5), .completed)
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 5))
    app.navigationBars["Review Summary"].buttons["Done"].tap()
    XCTAssertTrue(app.buttons["practice.katakana"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testCompleteSampleReviewsThroughTypedAnswers() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-FASTLANE_SNAPSHOT",
      "YES",
      "-groupMeaningReading",
      "YES",
      "-meaningFirst",
      "YES",
      "-ankiMode",
      "NO",
      "-autoSwitchKeyboard",
      "NO",
      "-playAudioAutomatically",
      "NO",
      "-reviewItemsLimitEnabled",
      "NO",
      "-skipKanjiReadings",
      "NO",
      "-allowSkippingReviews",
      "NO",
    ]
    app.launch()
    defer {
      app.terminate()
      app.launchArguments.append("ResetUserDefaults")
      app.launch()
      app.terminate()
    }
    startReviews(in: app)
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    let question = app.staticTexts["review.question"]
    let prompt = app.staticTexts["review.prompt"]
    let initial = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    initial.name = "SwiftUI review question"
    initial.lifetime = .keepAlways
    add(initial)
    let summary = app.staticTexts["Session complete"]
    let meanings = ["私自身": "personally", "私": "i", "自": "self", "身": "somebody"]
    for _ in 0..<5 {
      let previousQuestion = question.value as? String ?? ""
      let previousPrompt = prompt.label
      let answer = previousPrompt.contains("Reading") ? "watashijishin" : meanings[previousQuestion]
      XCTAssertNotNil(answer, "Unexpected sample question: \(previousQuestion), \(previousPrompt)")
      field.tap()
      field.typeText(answer!)
      app.buttons["review.submit"].tap()
      let changed = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          summary.exists || (question.value as? String != previousQuestion)
            || prompt
              .label != previousPrompt
        }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
      if summary.exists { break }
    }
    XCTAssertTrue(summary.waitForExistence(timeout: 10))
    let attachment = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    attachment.name = "Completed sample review session"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testVoiceTranscriptUsesNormalGradingAndKanaFallback() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-FASTLANE_SNAPSHOT",
      "YES",
      "VoiceReviewFixture",
      "-groupMeaningReading",
      "YES",
      "-meaningFirst",
      "YES",
      "-ankiMode",
      "NO",
      "-autoSwitchKeyboard",
      "NO",
      "-playAudioAutomatically",
      "NO",
      "-allowSkippingReviews",
      "NO",
    ]
    app.launch()
    defer {
      app.terminate()
      app.launchArguments.append("ResetUserDefaults")
      app.launch()
      app.terminate()
    }
    startReviews(in: app)
    XCTAssertTrue(app.buttons["review.voice"].waitForExistence(timeout: 10))
    app.buttons["review.voice"].tap()
    XCTAssertTrue(app.buttons["voice.start"].waitForExistence(timeout: 5))
    app.buttons["voice.start"].tap()
    XCTAssertTrue(app.buttons["voice.stop"].waitForExistence(timeout: 5))
    app.buttons["voice.stop"].tap()
    XCTAssertTrue(app.buttons["voice.submit"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["voice.submit"].isEnabled)
    app.buttons["voice.submit"].tap()
    let prompt = app.staticTexts["review.prompt"]
    let reading = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        prompt.exists && prompt.label.contains("Reading")
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [reading], timeout: 5), .completed)
    app.buttons["review.voice"].tap()
    XCTAssertTrue(app.buttons["voice.start"].waitForExistence(timeout: 5))
    app.buttons["voice.start"].tap()
    XCTAssertTrue(app.buttons["voice.stop"].waitForExistence(timeout: 5))
    app.buttons["voice.stop"].tap()
    XCTAssertTrue(app.buttons["voice.submit"].waitForExistence(timeout: 5))
    XCTAssertFalse(
      app.buttons["voice.submit"]
        .isEnabled)  // Kanji transcription is not a reading answer.
    let attachment = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    attachment.name = "Voice reading correction"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["voice.keyboard"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("watashijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor private func launchNativeReview(extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      ["--review-fixture", "--manual-review-fixture", "--audio-fixture", "--light-fixture"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["home.reviews"].waitForExistence(timeout: 10), app.debugDescription)
    app.buttons["home.reviews"].tap()
    XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 10), app.debugDescription)
    return app
  }

  @MainActor
  private func startReviews(in app: XCUIApplication) {
    let table = app.descendants(matching: .any).matching(identifier: "home.dashboard").firstMatch
    XCTAssertTrue(table.waitForExistence(timeout: 10))
    let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    // A self-sizing home row can leave the control outside the visible table.
    // Xcode's automatic scroll-to-tap can lose its button snapshot on iOS 27.
    for _ in 0..<5 {
      if start.exists && start.isHittable { break }
      table.swipeDown()
    }
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertTrue(start.isHittable)
    start.tap()
  }

  @MainActor
  private func clearFixture(_ app: XCUIApplication) {
    app.terminate()
    guard !app.launchArguments.contains("--review-fixture") else { return }
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "ResetUserDefaults"]
    app.launch()
    app.terminate()
  }

  @MainActor
  func testIncorrectAnswerRevealAndOverride() {
    continueAfterFailure = false
    let app = launchNativeReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("banana")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    app.buttons["review.reveal"].tap()
    XCTAssertTrue(app.buttons["review.corrections"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = "SwiftUI incorrect answer details"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["review.corrections"].tap()
    app.buttons["My answer was correct"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("hitotsu")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testCombinedAnkiIncorrectThenCorrectCompletesOneSubject() {
    continueAfterFailure = false
    let app = launchNativeReview(extra: [
      "--anki-fixture", "--combined-anki-fixture",
    ])
    defer { clearFixture(app) }
    XCTAssertFalse(app.buttons["review.voice"].exists)
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.incorrect"].waitForExistence(timeout: 5))
    app.buttons["review.incorrect"].tap()
    XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 5))
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.correct"].waitForExistence(timeout: 5))
    app.buttons["review.correct"].tap()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testLandscapeReviewKeepsAnswerControlsAccessible() {
    continueAfterFailure = false
    let app = launchNativeReview()
    defer {
      XCUIDevice.shared.orientation = .portrait
      clearFixture(app)
    }
    XCUIDevice.shared.orientation = .landscapeLeft
    let rotated = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("one thing")
    XCTAssertTrue(app.buttons["review.submit"].isHittable)
    XCTAssertTrue(app.staticTexts["review.prompt"].isHittable)
    XCTAssertTrue(app.staticTexts["Level 1"].isHittable)
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = "SwiftUI landscape review"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["review.submit"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("hitotsu")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testQuickSettingsPreservesDraftAndAppliesExactMatch() {
    continueAfterFailure = false
    let app = launchNativeReview(extra: ["-exactMatch", "NO"])
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("one thng")
    app.buttons["review.settings"].tap()
    let exact = app.switches["reviewSettings.exactMatch"]
    XCTAssertTrue(exact.waitForExistence(timeout: 5))
    XCTAssertEqual(exact.value as? String, "0")
    exact.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    XCTAssertEqual(exact.value as? String, "1")
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = "SwiftUI quick settings"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, "one thng")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["review.feedback"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["review.feedback"].label, "Use the exact meaning.")
    app.buttons["review.settings"].tap()
    XCTAssertTrue(exact.waitForExistence(timeout: 5))
    XCTAssertEqual(exact.value as? String, "1")
    exact.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    XCTAssertEqual(exact.value as? String, "0")
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, "one thng")
    app.buttons["review.submit"].tap()
    let reading = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.staticTexts["review.prompt"].label.contains("Reading")
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [reading], timeout: 5), .completed)
    field.tap()
    field.typeText("hitotsu")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testWrapUpCanBeStoppedAndCompleted() {
    continueAfterFailure = false
    let app = launchNativeReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("one thing")
    app.buttons["review.submit"].tap()
    app.buttons["review.close"].tap()
    let wrap = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wrap up ("))
      .firstMatch
    XCTAssertTrue(wrap.waitForExistence(timeout: 5))
    wrap.tap()
    XCTAssertTrue(app.staticTexts["Wrapping up"].waitForExistence(timeout: 5))
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.buttons["Stop wrapping up"].waitForExistence(timeout: 5))
    app.buttons["Stop wrapping up"].tap()
    let stopped = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Wrapping up"])
    XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 5), .completed, app.debugDescription)
    app.buttons["review.close"].tap()
    XCTAssertTrue(wrap.waitForExistence(timeout: 5))
    wrap.tap()
    field.tap()
    field.typeText("hitotsu")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Review session saved"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testFontLibraryReturnsToDraftAndUnstartedReviewCanClose() {
    continueAfterFailure = false
    let app = launchNativeReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("one thing")
    app.buttons["review.settings"].tap()
    XCTAssertTrue(app.buttons["reviewSettings.fonts"].waitForExistence(timeout: 5))
    app.buttons["reviewSettings.fonts"].tap()
    let navigation = app.navigationBars["Select Fonts"]
    XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    app.buttons["reviewSettings.done"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "one thing")
    app.buttons["review.close"].tap()
    let start = app.buttons["home.reviews"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
  }

  @MainActor
  func testExplicitEndDiscardsOnlyTheUnfinishedSession() {
    continueAfterFailure = false
    let app = launchNativeReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("one thing")
    app.buttons["review.submit"].tap()
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.buttons["End review session"].waitForExistence(timeout: 5))
    app.buttons["End review session"].tap()
    let start = app.buttons["home.reviews"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Review session saved"].exists)
  }
}

extension ReviewFlowTests {
  @MainActor
  private func launchLessonPicker() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "--review-fixture", "--lesson-fixture", "--lesson-settings-fixture", "--light-fixture",
    ]
    app.launch()
    let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Choose lessons"))
      .firstMatch
    XCTAssertTrue(choose.waitForExistence(timeout: 10))
    choose.tap()
    XCTAssertTrue(app.buttons["lesson.startSelection"].waitForExistence(timeout: 5))
    return app
  }

  @MainActor
  private func expectLessonPage(_ label: String, in app: XCUIApplication) {
    let page = app.staticTexts["lesson.position"]
    XCTAssertTrue(page.waitForExistence(timeout: 5))
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS %@", label), object: page)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
  }

  @MainActor
  func testLessonPickerPreservesSelectionAndUnfinishedQuizDraft() {
    continueAfterFailure = false
    let app = launchLessonPicker()
    defer { app.terminate() }
    XCTAssertFalse(app.buttons["lesson.startSelection"].isEnabled)
    let radical = app.buttons["lesson.select.10"]
    radical.tap()
    XCTAssertEqual(radical.value as? String, "Selected")
    radical.tap()
    XCTAssertEqual(radical.value as? String, "Not selected")
    app.buttons["lesson.select.1"].tap()
    XCTAssertEqual(app.staticTexts["lesson.selectionCount"].label, "1 selected")
    let picker = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    picker.name = "SwiftUI lesson picker"
    picker.lifetime = .keepAlways
    add(picker)
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    let teaching = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    teaching.name = "SwiftUI lesson navigation"
    teaching.lifetime = .keepAlways
    add(teaching)
    app.buttons["lesson.quiz"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("custom")
    app.buttons["lesson.page.0"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    app.buttons["lesson.quiz"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "custom")
    let quiz = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    quiz.name = "SwiftUI lessons retain quiz draft"
    quiz.lifetime = .keepAlways
    add(quiz)
    app.buttons["lesson.back"].tap()
    XCTAssertTrue(app.buttons["lesson.select.1"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["lesson.selectionCount"].label, "1 selected")
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    app.buttons["lesson.quiz"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "custom")
  }

  @MainActor
  func testLessonQuizPreservesWrongAnswerRulesAndCompletesTheSelectedLesson() {
    continueAfterFailure = false
    let app = launchLessonPicker()
    defer { app.terminate() }
    app.buttons["lesson.select.1"].tap()
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    app.buttons["lesson.quiz"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("banana")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    app.buttons["review.reveal"].tap()
    XCTAssertFalse(app.buttons["review.correct"].exists)
    app.buttons["review.submit"].tap()
    let saved = app.staticTexts["Lesson quiz saved"]
    for _ in 0..<4 {
      if saved.exists { break }
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      field.tap()
      field.typeText(app.staticTexts["review.prompt"].label.contains("Reading") ? "ichi" : "one")
      app.buttons["review.submit"].tap()
    }
    XCTAssertTrue(saved.waitForExistence(timeout: 5), app.debugDescription)
    app.buttons["review.finish"].tap()
    let choose = app.buttons["home.chooseLessons"]
    XCTAssertTrue(choose.waitForExistence(timeout: 5))
    choose.tap()
    XCTAssertTrue(app.buttons["lesson.select.10"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["lesson.select.1"].exists)
    XCTAssertFalse(app.buttons["lesson.startSelection"].isEnabled)
  }

  @MainActor
  func testLessonNavigationSupportsPagesSwipesAndReturningFromQuiz() {
    continueAfterFailure = false
    let app = launchLessonPicker()
    defer { app.terminate() }
    for id in [10, 1, 13] { app.buttons["lesson.select.\(id)"].tap() }
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 3", in: app)
    XCTAssertEqual(app.buttons["lesson.page.0"].value as? String, "Selected")
    app.buttons["lesson.page.1"].tap()
    expectLessonPage("Lesson 2 of 3", in: app)
    app.buttons["lesson.page.0"].tap()
    expectLessonPage("Lesson 1 of 3", in: app)
    app.buttons["lesson.page.2"].tap()
    expectLessonPage("Lesson 3 of 3", in: app)
    app.swipeRight()
    expectLessonPage("Lesson 2 of 3", in: app)
    app.buttons["lesson.quiz"].tap()
    expectLessonPage("Quiz", in: app)
    XCTAssertEqual(app.buttons["lesson.quiz"].value as? String, "Selected")
    app.buttons["lesson.page.2"].tap()
    expectLessonPage("Lesson 3 of 3", in: app)
    app.buttons["lesson.back"].tap()
    XCTAssertTrue(app.buttons["lesson.startSelection"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["lesson.selectionCount"].label, "3 selected")
  }
}

extension ReviewFlowTests {
  @MainActor
  private func revealIncorrectMeaning(in app: XCUIApplication) {
    XCTAssertTrue(app.staticTexts["review.prompt"].label.contains("Meaning"))
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("banana")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    app.buttons["review.reveal"].tap()
  }

  @MainActor
  private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
    let keyboardDone = app.buttons["material.keyboardDone"]
    if keyboardDone.exists && keyboardDone.isHittable { keyboardDone.tap() }
    for _ in 0..<16 {
      if element.exists && element.isHittable { return }
      let details = app.scrollViews["subject.scroll"]
      let catalog = app.collectionViews["catalog.list"]
      let form = app.descendants(matching: .any).matching(identifier: "material.form").firstMatch
      let home = app.collectionViews["home.dashboard"]
      if form.exists && form.isHittable {
        if element.exists && element.frame.midY < form.frame.minY {
          form.swipeDown(velocity: .slow)
        } else {
          form.swipeUp(velocity: .slow)
        }
      } else if details.exists && details.isHittable || catalog.exists && catalog.isHittable {
        let content = details.exists && details.isHittable ? details : catalog
        let down = towardTop || element.exists && element.frame.midY < content.frame.minY
        let start = content.coordinate(
          withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.3 : 0.7))
        let end = content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.6 : 0.4))
        start.press(
          forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
      } else if home.exists && home.isHittable {
        // Keep drags clear of the floating tab bar, which covers the center in landscape.
        let down = towardTop || element.exists && element.frame.midY < home.frame.minY
        let start = home.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: down ? 0.25 : 0.7))
        let end = home.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: down ? 0.7 : 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
      } else if towardTop {
        app.swipeDown()
      } else {
        app.swipeUp()
      }
    }
    let hierarchy = XCTAttachment(string: app.debugDescription)
    hierarchy.name = "Unreachable detail control"
    hierarchy.lifetime = .keepAlways
    add(hierarchy)
    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = "Unreachable detail control screen"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    XCTAssertTrue(element.exists && element.isHittable)
  }

  @MainActor
  private func openMaterialEditor(in app: XCUIApplication) {
    let edit = app.buttons["subject.editMaterial"]
    scrollTo(edit, in: app, towardTop: true)
    edit.tap()
    XCTAssertTrue(app.buttons["material.save"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testLessonDetailsSaveNotesAndSynonymsUsedByTheQuiz() {
    continueAfterFailure = false
    let app = launchLessonPicker()
    defer { app.terminate() }
    app.buttons["lesson.select.1"].tap()
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    openMaterialEditor(in: app)
    let note = app.textViews["material.meaningNote"]
    note.tap()
    note.typeText("My personal meaning note")
    let addSynonym = app.buttons["material.addSynonym"]
    scrollTo(addSynonym, in: app)
    addSynonym.tap()
    let synonym = app.textFields.matching(identifier: "material.synonym").element(boundBy: 1)
    scrollTo(synonym, in: app)
    synonym.tap()
    synonym.typeText("custompersonal")
    app.buttons["material.save"].tap()
    XCTAssertFalse(app.buttons["material.save"].waitForExistence(timeout: 2))
    openMaterialEditor(in: app)
    XCTAssertEqual(note.value as? String, "My personal meaning note")
    XCTAssertEqual(synonym.value as? String, "custompersonal")
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = "Shared SwiftUI notes and synonyms editor"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["material.cancel"].tap()
    app.buttons["lesson.quiz"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("custompersonal")
    app.buttons["review.submit"].tap()
    let reading = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS %@", "Reading"),
      object: app.staticTexts["review.prompt"])
    XCTAssertEqual(XCTWaiter.wait(for: [reading], timeout: 5), .completed)
  }

  @MainActor
  func testReviewDetailsConcealUnansweredReadingAndBlurTranslations() {
    continueAfterFailure = false
    let app = launchNativeReview()
    defer { clearFixture(app) }
    revealIncorrectMeaning(in: app)
    let reading = app.descendants(matching: .any).matching(identifier: "subject.readingExplanation")
      .firstMatch
    XCTAssertFalse(reading.exists)
    openMaterialEditor(in: app)
    XCTAssertFalse(app.textViews["material.readingNote"].exists)
    app.buttons["material.cancel"].tap()
    app.buttons["All information"].tap()
    XCTAssertTrue(reading.waitForExistence(timeout: 5))
    let translation = app.buttons["subject.translation.0"]
    scrollTo(translation, in: app)
    let english = app.staticTexts["One, please."]
    XCTAssertFalse(english.exists)
    translation.tap()
    XCTAssertTrue(english.waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = "Shared SwiftUI review details and sentence translation"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testMaterialConflictRetainsDraftAndHiddenNoteUntilExplicitReplacement() throws {
    continueAfterFailure = false
    let token = "00000000-0000-4000-8000-000000000001"
    let app = launchNativeReview(extra: [
      "--material-conflict-fixture", "--fixture-event-token", token,
    ])
    defer { clearFixture(app) }
    revealIncorrectMeaning(in: app)
    openMaterialEditor(in: app)
    let note = app.textViews["material.meaningNote"]
    note.tap()
    note.typeText("My draft survives")
    XCTAssertFalse(app.textViews["material.readingNote"].exists)
    try requestNativeURL(URL(string: "usagiunagi:///fixture/material-conflict/\(token)")!)
    let status = app.descendants(matching: .any).matching(identifier: "fixture.eventStatus")
      .firstMatch
    let committed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == %@", "Concurrent material change committed"),
      object: status)
    XCTAssertEqual(XCTWaiter.wait(for: [committed], timeout: 5), .completed)
    XCTAssertEqual(note.value as? String, "My draft survives")
    XCTAssertFalse(app.textViews["material.readingNote"].exists)
    app.buttons["material.save"].tap()
    XCTAssertTrue(app.buttons["material.save"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["material.save"].isEnabled)
    XCTAssertEqual(note.value as? String, "My draft survives")
    XCTAssertFalse(app.textViews["material.readingNote"].exists)
    let replace = app.buttons["Replace saved version with my draft"]
    scrollTo(replace, in: app)
    replace.tap()
    XCTAssertTrue(app.buttons["Replace with my draft"].waitForExistence(timeout: 5))
    app.buttons["Replace with my draft"].tap()
    XCTAssertFalse(app.buttons["material.save"].waitForExistence(timeout: 2))
    app.buttons["All information"].tap()
    let hiddenNote = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Concurrent hidden reading note")
    ).firstMatch
    scrollTo(hiddenNote, in: app)
    XCTAssertTrue(hiddenNote.exists)
    openMaterialEditor(in: app)
    XCTAssertTrue(app.staticTexts["Excluded from lessons and reviews"].exists)
    XCTAssertEqual(note.value as? String, "My draft survives")
    XCTAssertEqual(
      app.textViews["material.readingNote"].value as? String, "Concurrent hidden reading note")
    app.buttons["material.cancel"].tap()
  }
  @MainActor
  func testMaterialConflictFixtureRejectsUnarmedAndMismatchedEvents() throws {
    continueAfterFailure = false
    let token = "00000000-0000-4000-8000-000000000002"
    let cases: [(name: String, arguments: [String], route: String)] = [
      ("unarmed", ["--fixture-event-token", token], "material-conflict/\(token)"),
      ("missing token", ["--material-conflict-fixture"], "material-conflict/\(token)"),
      (
        "wrong token", ["--material-conflict-fixture", "--fixture-event-token", token],
        "material-conflict/00000000-0000-4000-8000-000000000003"
      ),
      (
        "wrong path", ["--material-conflict-fixture", "--fixture-event-token", token],
        "unknown-event/\(token)"
      ),
    ]
    for fixture in cases {
      try XCTContext.runActivity(named: fixture.name) { _ in
        let app = launchNativeReview(extra: fixture.arguments)
        defer { clearFixture(app) }
        revealIncorrectMeaning(in: app)
        openMaterialEditor(in: app)
        let note = app.textViews["material.meaningNote"]
        note.tap()
        note.typeText("Only my local draft")
        try requestNativeURL(URL(string: "usagiunagi:///fixture/\(fixture.route)")!)
        let event = app.descendants(matching: .any).matching(
          NSPredicate(
            format: "identifier == %@ AND label != %@", "fixture.eventStatus", "")
        ).firstMatch
        XCTAssertFalse(event.waitForExistence(timeout: 1))
        XCTAssertEqual(note.value as? String, "Only my local draft")
        XCTAssertFalse(app.textViews["material.readingNote"].exists)
        app.buttons["material.save"].tap()
        XCTAssertFalse(app.buttons["material.save"].waitForExistence(timeout: 2))
        app.buttons["All information"].tap()
        openMaterialEditor(in: app)
        XCTAssertEqual(note.value as? String, "Only my local draft")
        XCTAssertEqual(app.textViews["material.readingNote"].value as? String, "")
        XCTAssertFalse(app.staticTexts["Excluded from lessons and reviews"].exists)
        app.buttons["material.cancel"].tap()
      }
    }
  }

  @MainActor
  func testMaterialConflictFixtureDoesNotAcknowledgeRejectedCommit() throws {
    continueAfterFailure = false
    let token = "00000000-0000-4000-8000-000000000004"
    let app = launchNativeReview(extra: [
      "--material-conflict-fixture", "--fixture-event-token", token,
      "--material-conflict-failure-fixture",
    ])
    defer { clearFixture(app) }
    revealIncorrectMeaning(in: app)
    openMaterialEditor(in: app)
    let note = app.textViews["material.meaningNote"]
    note.tap()
    note.typeText("Draft after rejected event")
    try requestNativeURL(URL(string: "usagiunagi:///fixture/material-conflict/\(token)")!)
    let status = app.descendants(matching: .any).matching(identifier: "fixture.eventStatus")
      .firstMatch
    let failed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label BEGINSWITH %@", "Fixture event failed: "),
      object: status)
    XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 5), .completed)
    XCTAssertNotEqual(status.label, "Concurrent material change committed")
    XCTAssertEqual(note.value as? String, "Draft after rejected event")
    XCTAssertFalse(app.textViews["material.readingNote"].exists)
    app.buttons["material.save"].tap()
    XCTAssertFalse(app.buttons["material.save"].waitForExistence(timeout: 2))
    app.buttons["All information"].tap()
    openMaterialEditor(in: app)
    XCTAssertEqual(note.value as? String, "Draft after rejected event")
    XCTAssertEqual(app.textViews["material.readingNote"].value as? String, "")
    XCTAssertFalse(app.staticTexts["Excluded from lessons and reviews"].exists)
    app.buttons["material.cancel"].tap()
  }

}

extension ReviewFlowTests {
  @MainActor private func launchSettings(extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      [
        "-FASTLANE_SNAPSHOT", "YES", "CatalogFlowFixture", "SettingsFlowFixture",
        "-reviewItemsLimitEnabled", "NO", "-groupMeaningReading", "NO", "-meaningFirst", "YES",
        "-ankiMode", "NO", "-ankiModeCombineReadingMeaning", "NO", "-ankiModeTaskType", "1",
        "-showAllReadings", "NO", "-skipKanjiReadings", "NO", "-showFullAnswer", "NO",
        "-lessonBatchSize", "5", "-interfaceStyle", "1", "-gravatarCustomEmail", "",
      ] + extra
    app.launch()
    XCTAssertTrue(app.buttons["app.settings"].waitForExistence(timeout: 10))
    app.buttons["app.settings"].tap()
    XCTAssertTrue(app.buttons["settings.page.lessons"].waitForExistence(timeout: 5))
    return app
  }
  @MainActor private func setSettingsSwitch(
    _ control: XCUIElement, on: Bool, in app: XCUIApplication
  ) {
    scrollTo(control, in: app)
    if control.frame.maxY > app.frame.maxY - 60 { app.swipeUp(velocity: .slow) }
    if control.value as? String == (on ? "1" : "0") { return }
    let thumb = control.switches.firstMatch
    if thumb.exists {
      thumb.tap()
    } else {
      control.coordinate(withNormalizedOffset: .zero).withOffset(
        CGVector(dx: control.frame.width - 26, dy: control.frame.height / 2)
      ).tap()
    }
    let state = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", on ? "1" : "0"), object: control)
    XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 3), .completed)
  }
  @MainActor private func settingsPickerText(_ control: XCUIElement) -> String {
    ([control.label, control.value as? String ?? ""]
      + control.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
  }

  @MainActor func testSettingsLessonChoicesAndReorderingPersistWhenReopened() {
    continueAfterFailure = false
    let app = launchSettings()
    defer { clearFixture(app) }
    app.buttons["settings.page.lessons"].tap()
    let batch = app.buttons["settings.lessonBatchSize"]
    XCTAssertTrue(batch.waitForExistence(timeout: 5))
    batch.tap()
    app.buttons["2 lessons"].tap()
    app.buttons["settings.apprenticeLessonsLimit"].tap()
    app.buttons["50"].tap()
    app.buttons["settings.lessonOrderLink"].tap()
    let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'"))
    XCTAssertEqual(handles.count, 3)
    let nextFirst = handles.element(boundBy: 1).label
    handles.element(boundBy: 0).press(forDuration: 1, thenDragTo: handles.element(boundBy: 2))
    let reordered = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == %@", nextFirst), object: handles.firstMatch)
    XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 5), .completed)
    XCTAssertEqual(handles.firstMatch.label, nextFirst)
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["settings.lessonOrderLink"].tap()
    XCTAssertEqual(handles.firstMatch.label, nextFirst)
    app.navigationBars.buttons.firstMatch.tap()
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["settings.page.lessons"].tap()
    XCTAssertTrue(batch.waitForExistence(timeout: 5))
    XCTAssertTrue(settingsPickerText(batch).contains("2"), batch.debugDescription)
    let limit = app.buttons["settings.apprenticeLessonsLimit"]
    XCTAssertTrue(settingsPickerText(limit).contains("50"), limit.debugDescription)
    let image = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    image.name = "Native SwiftUI lesson settings"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor func testSettingsReviewDependenciesAndDownloadNavigation() {
    continueAfterFailure = false
    let app = launchSettings(extra: ["AudioFlowFixture"])
    defer { clearFixture(app) }
    app.buttons["settings.page.reviews"].tap()
    let limit = app.buttons["settings.reviewItemsLimit"]
    XCTAssertFalse(limit.exists)
    setSettingsSwitch(app.switches["settings.reviewItemsLimitEnabled"], on: true, in: app)
    XCTAssertTrue(limit.waitForExistence(timeout: 5))
    limit.tap()
    app.buttons["10 reviews"].tap()
    setSettingsSwitch(app.switches["reviewSettings.groupMeaningReading"], on: true, in: app)
    XCTAssertTrue(app.buttons["reviewSettings.meaningFirst"].exists)
    XCTAssertFalse(app.buttons["reviewSettings.batchSize"].exists)
    setSettingsSwitch(app.switches["reviewSettings.groupMeaningReading"], on: false, in: app)
    XCTAssertTrue(app.buttons["reviewSettings.batchSize"].exists)
    XCTAssertFalse(app.buttons["reviewSettings.meaningFirst"].exists)
    let tasks = app.buttons["reviewSettings.answerMode"]
    scrollTo(tasks, in: app, towardTop: true)
    tasks.tap()
    app.buttons["Anki: meaning and reading"].tap()
    let combined = app.switches["reviewSettings.combineAnki"]
    setSettingsSwitch(combined, on: true, in: app)
    tasks.tap()
    app.buttons["Anki: reading only"].tap()
    XCTAssertFalse(combined.exists)
    tasks.tap()
    app.buttons["Anki: meaning and reading"].tap()
    XCTAssertTrue(combined.waitForExistence(timeout: 5))
    XCTAssertEqual(combined.value as? String, "0")
    tasks.tap()
    app.buttons["Typed answers"].tap()
    XCTAssertFalse(combined.exists)
    let fonts = app.buttons["reviewSettings.fonts"]
    scrollTo(fonts, in: app)
    fonts.tap()
    XCTAssertTrue(app.navigationBars["Select Fonts"].waitForExistence(timeout: 5))
    app.navigationBars["Select Fonts"].buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Reviews"].waitForExistence(timeout: 5))
    let audio = app.buttons["reviewSettings.offlineAudio"]
    scrollTo(audio, in: app)
    audio.tap()
    XCTAssertTrue(app.navigationBars["Offline Audio"].waitForExistence(timeout: 5))
    app.navigationBars["Offline Audio"].buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Reviews"].waitForExistence(timeout: 5))
  }

  @MainActor func testSharedNotificationSettingsPersistWithoutSystemPrompts() {
    continueAfterFailure = false
    let app = launchSettings()
    defer { clearFixture(app) }
    app.buttons["settings.page.appearance"].tap()
    let choices = [
      ("settings.notificationsAllReviews", true),
      ("settings.notificationsBadging", false), ("settings.notificationSounds", true),
    ]
    for (id, enabled) in choices { setSettingsSwitch(app.switches[id], on: enabled, in: app) }
    XCTAssertFalse(app.alerts.firstMatch.exists)
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["settings.page.appearance"].tap()
    for (id, enabled) in choices {
      let toggle = app.switches[id]
      scrollTo(toggle, in: app)
      XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0")
    }
    XCTAssertFalse(app.alerts.firstMatch.exists)
  }
  @MainActor func testSettingsAppearanceEmailSubjectsAndSafeLogoutCancellation() {
    continueAfterFailure = false
    let app = launchSettings()
    defer { clearFixture(app) }
    app.buttons["settings.page.appearance"].tap()
    let style = app.buttons["settings.interfaceStyle"]
    XCTAssertTrue(style.waitForExistence(timeout: 5))
    style.tap()
    app.buttons["Dark"].tap()
    let email = app.textFields["settings.gravatarCustomEmail"]
    email.tap()
    email.typeText("fixture@example.invalid")
    if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
    XCTAssertTrue(app.switches["settings.notificationsAllReviews"].exists)
    XCTAssertTrue(app.switches["settings.notificationsBadging"].exists)
    XCTAssertTrue(app.switches["settings.notificationSounds"].exists)
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["settings.page.appearance"].tap()
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    XCTAssertEqual(email.value as? String, "fixture@example.invalid")
    XCTAssertTrue(settingsPickerText(style).contains("Dark"), style.debugDescription)
    let image = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    image.name = "Native SwiftUI appearance and notification settings"
    image.lifetime = .keepAlways
    add(image)
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["settings.page.subjects"].tap()
    let readings = app.switches["settings.showAllReadings"]
    setSettingsSwitch(readings, on: true, in: app)
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["settings.page.subjects"].tap()
    XCTAssertTrue(readings.waitForExistence(timeout: 5))
    XCTAssertEqual(readings.value as? String, "1")
    app.navigationBars.buttons.firstMatch.tap()
    let developer = app.buttons["settings.developer"]
    scrollTo(developer, in: app)
    developer.tap()
    XCTAssertTrue(app.navigationBars["Developer options"].waitForExistence(timeout: 5))
    app.navigationBars["Developer options"].buttons.firstMatch.tap()
    let logout = app.buttons["settings.logout"]
    scrollTo(logout, in: app)
    logout.tap()
    XCTAssertTrue(app.alerts["Log out?"].waitForExistence(timeout: 5))
    app.alerts["Log out?"].buttons["Cancel"].tap()
    XCTAssertFalse(app.alerts.firstMatch.exists)
    app.buttons["settings.back"].tap()
    XCTAssertTrue(app.buttons["app.settings"].waitForExistence(timeout: 5))
  }

  @MainActor private func launchCatalog() -> XCUIApplication {
    launchNativeHome(["--catalog-fixture", "--light-fixture"])
  }
  @MainActor private func openHomeRow(_ prefix: String, in app: XCUIApplication) {
    let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    scrollTo(row, in: app)
    row.tap()
  }

  @MainActor func testCatalogLevelPagingHidesAnswersAndStageNavigation() {
    continueAfterFailure = false
    let app = launchCatalog()
    defer { app.terminate() }
    openHomeRow("Show all", in: app)
    let first = app.buttons["catalog.subject.743"]
    XCTAssertFalse(app.buttons["catalog.previousLevel"].isEnabled)
    scrollTo(first, in: app)
    XCTAssertTrue(first.isHittable)
    let answers = app.buttons["catalog.answers"]
    if answers.label == "Hide answers" { answers.tap() }
    XCTAssertTrue(first.label.contains("Answers hidden"))
    XCTAssertFalse(first.label.contains("Alcohol"))
    scrollTo(app.buttons["catalog.nextLevel"], in: app, towardTop: true)
    app.buttons["catalog.nextLevel"].tap()
    let second = app.buttons["catalog.subject.923"]
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    XCTAssertTrue(second.label.contains("Answers hidden"))
    app.buttons["catalog.nextLevel"].tap()
    XCTAssertTrue(app.staticTexts["No matching subjects"].waitForExistence(timeout: 5))
    app.buttons["catalog.previousLevel"].tap()
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    app.buttons["catalog.subject.294"].swipeRight()
    scrollTo(first, in: app)
    XCTAssertTrue(first.isHittable)
    scrollTo(app.buttons["catalog.previousLevel"], in: app, towardTop: true)
    XCTAssertFalse(app.buttons["catalog.previousLevel"].isEnabled)
    let last = app.buttons["catalog.subject.8790"]
    scrollTo(last, in: app)
    XCTAssertTrue(last.isHittable)
    scrollTo(app.buttons["catalog.level"], in: app, towardTop: true)
    XCTAssertTrue(app.buttons["catalog.level"].isHittable)
    let screenshot = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    screenshot.name = "SwiftUI level catalog with hidden answers"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    navigateNativeBack(in: app)
    openHomeRow("Guru", in: app)
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    XCTAssertTrue(second.label.contains("Guru I"))
    XCTAssertFalse(app.buttons["catalog.filters"].exists)
    XCTAssertTrue(second.label.contains("Answers hidden"))
    XCTAssertFalse(app.buttons["catalog.subject.743"].exists)
    app.buttons["catalog.answers"].tap()
    XCTAssertFalse(second.label.contains("Answers hidden"))
    navigateNativeBack(in: app)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "home.dashboard").firstMatch.exists)
  }

  @MainActor func testCatalogSearchClearsKanaQueryAndOpensDetails() {
    continueAfterFailure = false
    let app = launchCatalog()
    defer { app.terminate() }
    app.buttons["Search"].tap()
    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("watashijishin")
    let result = app.buttons["catalog.subject.3864"]
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    XCTAssertTrue(result.label.contains("Personally"))
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "watashijishin".count))
    XCTAssertTrue(app.staticTexts["Search saved subjects"].waitForExistence(timeout: 5))
    XCTAssertFalse(result.exists)
    navigateNativeBack(in: app)
    let dismissed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: field)
    let dismissal = XCTWaiter.wait(for: [dismissed], timeout: 5)
    if dismissal != .completed {
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "Search cancellation hierarchy"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
    }
    XCTAssertEqual(dismissal, .completed)
    app.buttons["Search"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("personally")
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    screenshot.name = "SwiftUI catalog search"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    result.tap()
    XCTAssertTrue(app.buttons["subject.editMaterial"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["Subject"].buttons.firstMatch.isHittable)
    XCTAssertFalse(field.exists)
    navigateNativeBack(in: app)
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "personally")
    XCTAssertTrue(result.exists)
    navigateNativeBack(in: app)
    XCTAssertFalse(field.exists)
    XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 5))
  }

  @MainActor func testCatalogRemainingExplainsReadinessAndKeepsDueItemsFirst() {
    continueAfterFailure = false
    let app = launchCatalog()
    defer { app.terminate() }
    openHomeRow("Show remaining", in: app)
    let due = app.buttons["catalog.subject.743"]
    let lesson = app.buttons["catalog.subject.578"]
    let locked = app.buttons["catalog.subject.8790"]
    scrollTo(locked, in: app)
    XCTAssertTrue(locked.label.contains("Locked"))
    scrollTo(due, in: app)
    scrollTo(lesson, in: app)
    XCTAssertTrue(due.isHittable && lesson.isHittable)
    XCTAssertTrue(due.label.contains("Review now"))
    XCTAssertTrue(lesson.label.contains("Available now"))
    XCTAssertLessThan(due.frame.minY, lesson.frame.minY)
    XCTAssertFalse(app.buttons["catalog.subject.689"].exists)
    let screenshot = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    screenshot.name = "SwiftUI remaining items and next actions"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    navigateNativeBack(in: app)
  }

  @MainActor func testCatalogExclusionUpdatesAfterReturningFromDetails() {
    continueAfterFailure = false
    let app = launchCatalog()
    defer { app.terminate() }
    openHomeRow("Excluded items", in: app)
    let row = app.buttons["catalog.subject.3864"]
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.tap()
    let excluded = app.switches["subject.excluded"]
    scrollTo(excluded, in: app)
    XCTAssertEqual(excluded.value as? String, "1")
    excluded.coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: excluded.frame.width - 26, dy: excluded.frame.height / 2)
    ).tap()
    let off = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "0"), object: excluded)
    XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 3), .completed)
    navigateNativeBack(in: app)
    XCTAssertTrue(app.staticTexts["No matching subjects"].waitForExistence(timeout: 5))
    XCTAssertFalse(row.exists)
    navigateNativeBack(in: app)
  }
}
