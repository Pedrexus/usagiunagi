// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

#if DEBUG
  import Observation
  import StudyCore
  import StudyUI
  import UIKit

  /// Temporary old-host test setup. Shipping lifecycle and views are SwiftUI.
  @MainActor @Observable final class AppDelegate: UIResponder, UIApplicationDelegate {
    private(set) var legacyFixtureServices: TKMServices?
    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
      guard Screenshotter.isActive else { return true }
      Settings.migrate()
      Screenshotter.setUp()
      let notifications = StudyNotifications(
        preferences: LegacyNotificationPreferences(),
        client: NotificationFixture.client)
      if let (loader, configuration) = Screenshotter.fontFixture() {
        legacyFixtureServices = TKMServices(
          fontLibrary: .init(
            catalog: loader,
            preferences: LegacyFontPreferences(), configuration: configuration),
          audioDownloads: Screenshotter.audioFixture(), notifications: notifications,
          companion: NotificationFixture.companion)
      } else {
        legacyFixtureServices = TKMServices(
          audioDownloads: Screenshotter.audioFixture(),
          notifications: notifications, companion: NotificationFixture.companion)
      }
      return true
    }
  }
#endif
