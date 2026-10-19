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
import Reachability
import StudyCore
import StudyUI
import WaniKaniAPI

class TKMServices {
  let reachability: Reachability = .forInternetConnection()
  let legacyAvatars = LegacyAvatarCache(
    directory: URL.cachesDirectory.appending(
      path: "com.hpique.haneke/shared", directoryHint: .isDirectory))
  @MainActor let notifications: StudyNotifications
  @MainActor let lessonSettings: StudyLessonSettings
  @MainActor let subjectSettings: StudySubjectSettings
  @MainActor let fontLibrary: StudyFontLibrary

  private(set) var offlineAudio: OfflineAudio!
  @MainActor let audio: StudyAudioLibrary
  private(set) var radicalCharacterImages: RadicalCharacterImages!

  var client: WaniKaniAPIClient!
  var localCachingClient: LocalCachingClient!

  @MainActor init(
    fontLibrary: StudyFontLibrary? = nil, audioDownloads: StudyAudioDownloads? = nil,
    notifications: StudyNotifications? = nil
  ) {
    self.notifications =
      notifications ?? StudyNotifications(preferences: LegacyNotificationPreferences())
    lessonSettings = StudyLessonSettings(store: LegacyLessonPreferences())
    subjectSettings = StudySubjectSettings(store: LegacySubjectPreferences())
    self.fontLibrary = fontLibrary ?? StudyFontLibrary(preferences: LegacyFontPreferences())
    let downloads =
      audioDownloads ?? StudyAudioDownloads(directory: .documentsDirectory.appending(path: "audio"))
    audio = StudyAudioLibrary(downloads: downloads, preferences: LegacyAudioPreferences())
    offlineAudio = OfflineAudio(services: self)
    radicalCharacterImages = RadicalCharacterImages(services: self)
  }
  @MainActor func updateStudyServices() async {
    WatchHelper.sharedInstance.updatedData(client: localCachingClient)
    await notifications.update { [weak self] in
      guard let client = self?.localCachingClient, let user = client.getUserInfo() else {
        return .init()
      }
      let pending = Set(client.getAllPendingProgress().map { $0.assignment.subjectID })
      let valid = Set(
        client.getAllSubjects().filter { Int($0.level) <= client.maxLevelGrantedBySubscription }
          .map(\.id))
      let dates = client.getNonExcludedAssignments().filter {
        $0.isReviewStage && $0.hasAvailableAt && !pending.contains($0.subjectID)
          && valid.contains($0.subjectID)
          && (Settings.showKanaOnlyVocab || !$0.isKanaOnlyVocab)
      }.map(\.availableAtDate)
      return StudyNotificationSnapshot(reviewDates: dates, onVacation: user.hasVacationStartedAt)
    }
  }

}
