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

import Foundation
import StudyCore
import StudyUI
import UIKit
import WaniKaniAPI

class AppDelegate: UIResponder, UIApplicationDelegate {
  // Owned here rather than by the scene delegate: these outlive any individual scene, and are used
  // for background fetches that happen while no scene is connected.
  private(set) var services: TKMServices!

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
  )
    -> Bool
  {
    Settings.migrate()
    Screenshotter.setUp()
    let notifications = StudyNotifications(
      preferences: LegacyNotificationPreferences(),
      client: {
        #if DEBUG
          if Screenshotter.isActive { return NotificationFixture.client }
        #endif
        return .system
      }())

    application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    #if DEBUG
      if let (loader, configuration) = Screenshotter.fontFixture() {
        services = TKMServices(
          fontLibrary: StudyFontLibrary(
            catalog: loader, preferences: LegacyFontPreferences(), configuration: configuration),
          audioDownloads: Screenshotter.audioFixture(), notifications: notifications,
          companion: NotificationFixture.companion)
      } else {
        services = TKMServices(
          audioDownloads: Screenshotter.audioFixture(), notifications: notifications,
          companion: NotificationFixture.companion)
      }
    #else
      services = TKMServices(notifications: notifications)
    #endif

    return true
  }

  func application(
    _: UIApplication,
    performFetchWithCompletionHandler completionHandler:
      @escaping (UIBackgroundFetchResult)
      -> Void
  ) {
    guard let lcc = services.localCachingClient else {
      completionHandler(.noData)
      return
    }

    lcc.sync(quick: true, progress: Progress(totalUnitCount: -1)).finally {
      Task { @MainActor in
        await self.services.updateStudyServices()
        completionHandler(.newData)
      }
    }
  }

}
