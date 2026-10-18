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
import WaniKaniAPI

class TKMServices {
  let reachability: Reachability = .forInternetConnection()
  let legacyAvatars = LegacyAvatarCache(
    directory: URL.cachesDirectory.appending(
      path: "com.hpique.haneke/shared", directoryHint: .isDirectory))
  @MainActor let lessonSettings: StudyLessonSettings
  @MainActor let fontLibrary: StudyFontLibrary

  private(set) var offlineAudio: OfflineAudio!
  @MainActor let audio: StudyAudioLibrary
  private(set) var radicalCharacterImages: RadicalCharacterImages!

  var client: WaniKaniAPIClient!
  var localCachingClient: LocalCachingClient!

  @MainActor init(fontLibrary: StudyFontLibrary? = nil, audioDownloads: StudyAudioDownloads? = nil)
  {
    lessonSettings = StudyLessonSettings(store: LegacyLessonPreferences())
    self.fontLibrary = fontLibrary ?? StudyFontLibrary(preferences: LegacyFontPreferences())
    let downloads =
      audioDownloads ?? StudyAudioDownloads(directory: .documentsDirectory.appending(path: "audio"))
    audio = StudyAudioLibrary(downloads: downloads, preferences: LegacyAudioPreferences())
    offlineAudio = OfflineAudio(services: self)
    radicalCharacterImages = RadicalCharacterImages(services: self)
  }
}
