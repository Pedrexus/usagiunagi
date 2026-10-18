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
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    let app = launchSettings(extra: ["AudioFlowFixture"] + extra)
    app.buttons["settings.page.reviews"].tap()
    let audio = app.buttons["settings.offlineAudio"]
    scrollTo(audio, in: app)
    audio.tap()
    XCTAssertTrue(app.navigationBars["Offline Audio"].waitForExistence(timeout: 5))
    return app
  }

  @MainActor func testOfflineAudioVoiceChoicesAndCellularSettingPersist() {
    continueAfterFailure = false
    let app = launchOfflineAudio(extra: ["AudioHeldFixture"])
    defer { clearFixture(app) }
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
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "SwiftUI offline audio with selected voices"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.navigationBars["Offline Audio"].buttons.firstMatch.tap()
    let audio = app.buttons["settings.offlineAudio"]
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
    defer { clearFixture(app) }
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
    defer { clearFixture(app) }
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
    let app = launchSingleReview(extra: ["FontFlowFixture"] + extra)
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
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "SwiftUI font library selection"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.navigationBars["Select Fonts"].buttons.firstMatch.tap()
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
      app.otherElements["PopoverDismissRegion"].coordinate(
        withNormalizedOffset: CGVector(dx: popup.frame.midX < app.frame.midX ? 0.95 : 0.05, dy: 0.5)
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
    app.navigationBars["Select Fonts"].buttons.firstMatch.tap()
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
    let app = launchSingleReview(extra: [
      "-animateParticleExplosion", "YES", "-animatePlusOne", "YES", "-animateLevelUpPopup", "YES",
    ])
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("personally")
    app.buttons["review.submit"].tap()
    let feedback = app.descendants(matching: .any).matching(identifier: "review.success").firstMatch
    XCTAssertTrue(feedback.waitForExistence(timeout: 5))
    XCTAssertTrue(feedback.label.contains("Previous answer correct"))
    XCTAssertFalse(feedback.label.contains("+1"))
    XCTAssertFalse(feedback.label.contains("Estimated SRS"))
    field.tap()
    field.typeText("wata")
    app.buttons["review.settings"].tap()
    let correct = app.switches["reviewSettings.correctAnswerFeedback"]
    scrollTo(correct, in: app)
    setSettingsSwitch(correct, on: false, in: app)
    XCTAssertEqual(app.switches["reviewSettings.completedItemFeedback"].value as? String, "1")
    XCTAssertEqual(app.switches["reviewSettings.srsMilestoneFeedback"].value as? String, "1")
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, "わた")
    XCTAssertFalse(feedback.label.contains("Previous answer correct"))
    app.buttons["review.settings"].tap()
    scrollTo(correct, in: app)
    XCTAssertEqual(correct.value as? String, "0")
    app.buttons["reviewSettings.done"].tap()
    app.typeText("shijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testCompletionAndMilestoneFeedbackRemainReadableWithReducedMotion() {
    continueAfterFailure = false
    changeReduceMotion(to: true, restoreAfterTest: true)
    let app = launchSingleReview(extra: [
      "ReviewFeedbackFixture", "-ankiMode", "YES",
      "-ankiModeCombineReadingMeaning", "YES", "-animateParticleExplosion", "YES",
      "-animatePlusOne", "YES", "-animateLevelUpPopup", "YES",
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
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
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
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "ShowStatistics", "ShowCoverage"]
    app.launch()
    defer { clearFixture(app) }
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
    let expanded = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    let app = XCUIApplication()
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES"]
    app.launch()
    defer { clearFixture(app) }
    let forecast = app.cells.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Upcoming reviews:")
    ).firstMatch
    XCTAssertTrue(forecast.waitForExistence(timeout: 10))
    let due = try XCTUnwrap(forecast.label.split(separator: ":").last?.split(separator: " ").first)
    forecast.tap()
    XCTAssertTrue(app.navigationBars["Upcoming Reviews"].waitForExistence(timeout: 5))
    let hour = app.descendants(matching: .any).matching(identifier: "schedule.hour.0").firstMatch
    XCTAssertTrue(hour.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["\(due) reviews · +\(due) this hour"].exists)
    hour.tap()
    XCTAssertTrue(app.staticTexts["Apprentice"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Guru"].exists)
    XCTAssertTrue(app.staticTexts["Radical"].exists)
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "SwiftUI upcoming review breakdown"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.navigationBars["Upcoming Reviews"].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(forecast.waitForExistence(timeout: 5))
  }

  @MainActor
  func testSummaryShowsMissedMeaningAndOpensSubjectDetails() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("banana")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    app.buttons["review.reveal"].tap()
    app.buttons["review.submit"].tap()
    let complete = app.staticTexts["Session complete"]
    for _ in 0..<3 {
      if complete.exists { break }
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      let answer =
        app.staticTexts["review.prompt"].label.contains("Reading") ? "watashijishin" : "personally"
      field.tap()
      field.typeText(answer)
      app.buttons["review.submit"].tap()
    }
    XCTAssertTrue(complete.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Missed items"].exists)
    let missed = app.buttons["summary.subject.0"]
    XCTAssertTrue(missed.waitForExistence(timeout: 5))
    XCTAssertTrue(missed.label.contains("Meaning missed"))
    XCTAssertFalse(missed.label.contains("Reading missed"))
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "SwiftUI missed-subject summary"
    attachment.lifetime = .keepAlways
    add(attachment)
    missed.tap()
    XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
    app.buttons["Back"].tap()
    XCTAssertTrue(missed.waitForExistence(timeout: 5))
    app.navigationBars["Review Summary"].buttons["Done"].tap()
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews")).firstMatch
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
    let tab = app.tabBars.buttons["Practice"]
    XCTAssertTrue(tab.waitForExistence(timeout: 10))
    tab.tap()
    XCTAssertTrue(app.buttons["practice.katakana"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    let initial = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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

  @MainActor
  private func launchSingleReview(extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      [
        "-FASTLANE_SNAPSHOT", "YES", "SingleReviewFixture",
        "-groupMeaningReading", "YES", "-meaningFirst", "YES", "-ankiMode", "NO",
        "-autoSwitchKeyboard", "NO", "-playAudioAutomatically", "NO",
        "-allowSkippingReviews", "NO", "-showAnswerImmediately", "NO",
        "-enableCheats", "YES",
      ] + extra
    app.launch()
    startReviews(in: app)
    XCTAssertTrue(app.buttons["review.submit"].waitForExistence(timeout: 10))
    return app
  }

  @MainActor
  private func startReviews(in app: XCUIApplication) {
    let table = app.tables.firstMatch
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
    app.launchArguments = ["-FASTLANE_SNAPSHOT", "YES", "ResetUserDefaults"]
    app.launch()
    app.terminate()
  }

  @MainActor
  func testIncorrectAnswerRevealAndOverride() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("banana")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    app.buttons["review.reveal"].tap()
    XCTAssertTrue(app.buttons["review.corrections"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "SwiftUI incorrect answer details"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["review.corrections"].tap()
    app.buttons["My answer was correct"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("watashijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testCombinedAnkiIncorrectThenCorrectCompletesOneSubject() {
    continueAfterFailure = false
    let app = launchSingleReview(extra: [
      "-ankiMode",
      "YES",
      "-ankiModeCombineReadingMeaning",
      "YES",
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
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testLandscapeReviewKeepsAnswerControlsAccessible() {
    continueAfterFailure = false
    let app = launchSingleReview()
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
    field.typeText("personally")
    XCTAssertTrue(app.buttons["review.submit"].isHittable)
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "SwiftUI landscape review"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["review.submit"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("watashijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testQuickSettingsPreservesDraftAndAppliesExactMatch() {
    continueAfterFailure = false
    let app = launchSingleReview(extra: ["-exactMatch", "NO"])
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("personaly")
    app.buttons["review.settings"].tap()
    let exact = app.switches["reviewSettings.exactMatch"]
    XCTAssertTrue(exact.waitForExistence(timeout: 5))
    XCTAssertEqual(exact.value as? String, "0")
    exact.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    XCTAssertEqual(exact.value as? String, "1")
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "SwiftUI quick settings"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, "personaly")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["review.feedback"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["review.feedback"].label, "Use the exact meaning.")
    app.buttons["review.settings"].tap()
    XCTAssertTrue(exact.waitForExistence(timeout: 5))
    XCTAssertEqual(exact.value as? String, "1")
    exact.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    XCTAssertEqual(exact.value as? String, "0")
    app.buttons["reviewSettings.done"].tap()
    XCTAssertEqual(field.value as? String, "personaly")
    app.buttons["review.submit"].tap()
    let reading = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.staticTexts["review.prompt"].label.contains("Reading")
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [reading], timeout: 5), .completed)
    field.tap()
    field.typeText("watashijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testWrapUpCanBeStoppedAndCompleted() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("personally")
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
    XCTAssertFalse(app.staticTexts["Wrapping up"].exists)
    app.buttons["review.close"].tap()
    XCTAssertTrue(wrap.waitForExistence(timeout: 5))
    wrap.tap()
    field.tap()
    field.typeText("watashijishin")
    app.buttons["review.submit"].tap()
    XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testFontLibraryReturnsToDraftAndUnstartedReviewCanClose() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("personally")
    app.buttons["review.settings"].tap()
    XCTAssertTrue(app.buttons["reviewSettings.fonts"].waitForExistence(timeout: 5))
    app.buttons["reviewSettings.fonts"].tap()
    let navigation = app.navigationBars["Select Fonts"]
    XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    navigation.buttons.firstMatch.tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "personally")
    app.buttons["review.close"].tap()
    let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 5))
  }

  @MainActor
  func testExplicitEndDiscardsOnlyTheUnfinishedSession() {
    continueAfterFailure = false
    let app = launchSingleReview()
    defer { clearFixture(app) }
    let field = app.textFields["review.answer"]
    field.tap()
    field.typeText("personally")
    app.buttons["review.submit"].tap()
    app.buttons["review.close"].tap()
    XCTAssertTrue(app.buttons["End review session"].waitForExistence(timeout: 5))
    app.buttons["End review session"].tap()
    let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start reviews"))
      .firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Session complete"].exists)
  }
}

extension ReviewFlowTests {
  @MainActor
  private func launchLessonPicker() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-FASTLANE_SNAPSHOT", "YES", "LessonFlowFixture",
      "-groupMeaningReading", "YES", "-meaningFirst", "YES", "-ankiMode", "NO",
      "-autoSwitchKeyboard", "NO", "-playAudioAutomatically", "NO",
      "-allowSkippingReviews", "NO", "-showAnswerImmediately", "NO",
      "-enableCheats", "YES",
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
    defer { clearFixture(app) }
    XCTAssertFalse(app.buttons["lesson.startSelection"].isEnabled)
    let radical = app.buttons["lesson.select.293"]
    radical.tap()
    XCTAssertEqual(radical.value as? String, "Selected")
    radical.tap()
    XCTAssertEqual(radical.value as? String, "Not selected")
    app.buttons["lesson.select.3864"].tap()
    XCTAssertEqual(app.staticTexts["lesson.selectionCount"].label, "1 selected")
    let picker = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    picker.name = "SwiftUI lesson picker"
    picker.lifetime = .keepAlways
    add(picker)
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    let teaching = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    teaching.name = "SwiftUI lesson navigation"
    teaching.lifetime = .keepAlways
    add(teaching)
    app.buttons["lesson.quiz"].tap()
    let field = app.textFields["review.answer"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("pers")
    app.buttons["lesson.page.0"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    app.buttons["lesson.quiz"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "pers")
    let quiz = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    quiz.name = "SwiftUI lessons retain quiz draft"
    quiz.lifetime = .keepAlways
    add(quiz)
    app.buttons["lesson.back"].tap()
    XCTAssertTrue(app.buttons["lesson.select.3864"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["lesson.selectionCount"].label, "1 selected")
  }

  @MainActor
  func testLessonQuizPreservesWrongAnswerRulesAndCompletesTheSelectedLesson() {
    continueAfterFailure = false
    let app = launchLessonPicker()
    defer { clearFixture(app) }
    app.buttons["lesson.select.3864"].tap()
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
    let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Choose lessons"))
      .firstMatch
    for _ in 0..<4 {
      if choose.exists { break }
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      let answer =
        app.staticTexts["review.prompt"].label.contains("Reading") ? "watashijishin" : "personally"
      field.tap()
      field.typeText(answer)
      app.buttons["review.submit"].tap()
    }
    XCTAssertTrue(choose.waitForExistence(timeout: 5))
    choose.tap()
    XCTAssertTrue(app.buttons["lesson.select.293"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["lesson.select.3864"].exists)
    XCTAssertFalse(app.buttons["lesson.startSelection"].isEnabled)
  }

  @MainActor
  func testLessonNavigationSupportsPagesSwipesAndReturningFromQuiz() {
    continueAfterFailure = false
    let app = launchLessonPicker()
    defer { clearFixture(app) }
    for id in [293, 743, 3864] { app.buttons["lesson.select.\(id)"].tap() }
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
      let form = app.descendants(matching: .any).matching(identifier: "material.form").firstMatch
      if form.exists && form.isHittable {
        if element.exists && element.frame.midY < form.frame.minY {
          form.swipeDown(velocity: .slow)
        } else {
          form.swipeUp(velocity: .slow)
        }
      } else if details.exists && details.isHittable {
        if towardTop || element.exists && element.frame.midY < details.frame.minY {
          details.swipeDown(velocity: .slow)
        } else {
          details.swipeUp(velocity: .slow)
        }
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
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    defer { clearFixture(app) }
    app.buttons["lesson.select.3864"].tap()
    app.buttons["lesson.startSelection"].tap()
    expectLessonPage("Lesson 1 of 1", in: app)
    openMaterialEditor(in: app)
    let note = app.textViews["material.meaningNote"]
    note.tap()
    note.typeText("My personal meaning note")
    let addSynonym = app.buttons["material.addSynonym"]
    scrollTo(addSynonym, in: app)
    addSynonym.tap()
    let synonym = app.descendants(matching: .any).matching(identifier: "material.synonym")
      .firstMatch
    scrollTo(synonym, in: app)
    synonym.tap()
    synonym.typeText("custompersonal")
    app.buttons["material.save"].tap()
    XCTAssertFalse(app.buttons["material.save"].waitForExistence(timeout: 2))
    openMaterialEditor(in: app)
    XCTAssertEqual(note.value as? String, "My personal meaning note")
    XCTAssertEqual(synonym.value as? String, "custompersonal")
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    let app = launchSingleReview(extra: ["-blurContextSentences", "YES"])
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
    let english = app.staticTexts["Personally, I'm indifferent to the zoo's issues."]
    XCTAssertFalse(english.exists)
    translation.tap()
    XCTAssertTrue(english.waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "Shared SwiftUI review details and sentence translation"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testMaterialConflictRetainsDraftAndHiddenNoteUntilExplicitReplacement() {
    continueAfterFailure = false
    let app = launchSingleReview(extra: ["MaterialConflictFixture"])
    defer { clearFixture(app) }
    revealIncorrectMeaning(in: app)
    openMaterialEditor(in: app)
    let note = app.textViews["material.meaningNote"]
    note.tap()
    note.typeText("My draft survives")
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
    handles.element(boundBy: 0).press(forDuration: 0.3, thenDragTo: handles.element(boundBy: 2))
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
    let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    setSettingsSwitch(app.switches["settings.groupMeaningReading"], on: true, in: app)
    XCTAssertTrue(app.buttons["settings.meaningFirst"].exists)
    XCTAssertFalse(app.buttons["settings.reviewBatchSize"].exists)
    setSettingsSwitch(app.switches["settings.groupMeaningReading"], on: false, in: app)
    XCTAssertTrue(app.buttons["settings.reviewBatchSize"].exists)
    XCTAssertFalse(app.buttons["settings.meaningFirst"].exists)
    setSettingsSwitch(app.switches["settings.ankiMode"], on: true, in: app)
    let tasks = app.buttons["settings.ankiModeTaskType"]
    scrollTo(tasks, in: app)
    let combined = app.switches["settings.ankiModeCombineReadingMeaning"]
    setSettingsSwitch(combined, on: true, in: app)
    tasks.tap()
    app.buttons["Reading only"].tap()
    XCTAssertFalse(combined.exists)
    tasks.tap()
    app.buttons["Both"].tap()
    XCTAssertTrue(combined.waitForExistence(timeout: 5))
    XCTAssertEqual(combined.value as? String, "0")
    setSettingsSwitch(app.switches["settings.ankiMode"], on: false, in: app)
    XCTAssertFalse(tasks.exists)
    let fonts = app.buttons["reviewSettings.fonts"]
    scrollTo(fonts, in: app, towardTop: true)
    fonts.tap()
    XCTAssertTrue(app.navigationBars["Select Fonts"].waitForExistence(timeout: 5))
    app.navigationBars["Select Fonts"].buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Reviews"].waitForExistence(timeout: 5))
    let audio = app.buttons["settings.offlineAudio"]
    scrollTo(audio, in: app)
    audio.tap()
    XCTAssertTrue(app.navigationBars["Offline Audio"].waitForExistence(timeout: 5))
    app.navigationBars["Offline Audio"].buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Reviews"].waitForExistence(timeout: 5))
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
    let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
    let app = XCUIApplication()
    app.launchArguments = [
      "-FASTLANE_SNAPSHOT", "YES", "CatalogFlowFixture", "-allowExcludeItems", "YES",
      "-showPreviousLevelGraph", "YES",
    ]
    app.launch()
    XCTAssertTrue(app.tables.firstMatch.waitForExistence(timeout: 10))
    return app
  }
  @MainActor private func openHomeRow(_ prefix: String, in app: XCUIApplication) {
    let row = app.cells.containing(.staticText, identifier: prefix).firstMatch
    for _ in 0..<12 {
      if row.exists && row.isHittable {
        row.tap()
        return
      }
      app.tables.firstMatch.swipeUp(velocity: .slow)
    }
    let hierarchy = XCTAttachment(string: app.debugDescription)
    hierarchy.name = "Missing home catalog entry"
    hierarchy.lifetime = .keepAlways
    add(hierarchy)
    XCTFail("Home catalog entry unavailable: \(prefix)")
  }

  @MainActor func testCatalogLevelPagingHidesAnswersAndStageNavigation() {
    continueAfterFailure = false
    let app = launchCatalog()
    defer { clearFixture(app) }
    openHomeRow("Show all", in: app)
    let first = app.buttons["catalog.subject.743"]
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["catalog.previousLevel"].isEnabled)
    let answers = app.buttons["catalog.answers"]
    if answers.label == "Hide answers" { answers.tap() }
    XCTAssertTrue(first.label.contains("Answers hidden"))
    XCTAssertFalse(first.label.contains("Alcohol"))
    app.buttons["catalog.nextLevel"].tap()
    let second = app.buttons["catalog.subject.923"]
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    XCTAssertTrue(second.label.contains("Answers hidden"))
    app.buttons["catalog.nextLevel"].tap()
    XCTAssertTrue(app.staticTexts["No matching subjects"].waitForExistence(timeout: 5))
    app.buttons["catalog.previousLevel"].tap()
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    app.buttons["catalog.subject.294"].swipeRight()
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["catalog.previousLevel"].isEnabled)
    let last = app.buttons["catalog.subject.8790"]
    for _ in 0..<4 where !last.isHittable { app.swipeUp() }
    XCTAssertTrue(last.isHittable)
    for _ in 0..<4 where !app.buttons["catalog.level"].isHittable { app.swipeDown() }
    XCTAssertTrue(app.buttons["catalog.level"].isHittable)
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "SwiftUI level catalog with hidden answers"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["catalog.back"].tap()
    openHomeRow("Guru", in: app)
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    XCTAssertTrue(second.label.contains("Guru I"))
    XCTAssertTrue(second.label.contains("Answers hidden"))
    XCTAssertFalse(app.buttons["catalog.subject.743"].exists)
    app.buttons["catalog.answers"].tap()
    XCTAssertFalse(second.label.contains("Answers hidden"))
    app.buttons["catalog.back"].tap()
    XCTAssertTrue(app.tables.firstMatch.exists)
  }

  @MainActor func testCatalogSearchClearsKanaQueryAndOpensDetails() {
    continueAfterFailure = false
    let app = launchCatalog()
    defer { clearFixture(app) }
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
    app.buttons["catalog.back"].tap()
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
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "SwiftUI catalog search"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    result.tap()
    XCTAssertTrue(app.buttons["subject.editMaterial"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["subject.back"].exists)
    XCTAssertFalse(field.exists)
    app.buttons["subject.back"].tap()
    XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 5))
  }

  @MainActor func testCatalogRemainingExplainsReadinessAndKeepsDueItemsFirst() {
    continueAfterFailure = false
    let app = launchCatalog()
    defer { clearFixture(app) }
    openHomeRow("Show remaining", in: app)
    let due = app.buttons["catalog.subject.743"]
    let lesson = app.buttons["catalog.subject.578"]
    XCTAssertTrue(due.waitForExistence(timeout: 5))
    XCTAssertTrue(due.label.contains("Review now"))
    XCTAssertTrue(lesson.label.contains("Available now"))
    XCTAssertLessThan(due.frame.minY, lesson.frame.minY)
    XCTAssertTrue(app.buttons["catalog.subject.8790"].label.contains("Locked"))
    XCTAssertFalse(app.buttons["catalog.subject.689"].exists)
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "SwiftUI remaining items and next actions"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["catalog.back"].tap()
  }

  @MainActor func testCatalogExclusionUpdatesAfterReturningFromDetails() {
    continueAfterFailure = false
    let app = launchCatalog()
    defer { clearFixture(app) }
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
    app.buttons["subject.back"].tap()
    XCTAssertTrue(app.staticTexts["No matching subjects"].waitForExistence(timeout: 5))
    XCTAssertFalse(row.exists)
    app.buttons["catalog.back"].tap()
  }
}
