// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Foundation
import StudyCore

/// Adapts the current account cache and archived preferences to native audio downloads.
@MainActor final class OfflineAudio {
  nonisolated let downloads: StudyAudioDownloads
  private weak var services: TKMServices?
  private let notifications = NotificationDispatcher()
  private var lastLevel: Int32?

  init(services: TKMServices, downloads: StudyAudioDownloads? = nil) {
    self.services = services
    self.downloads =
      downloads
      ?? StudyAudioDownloads(directory: .documentsDirectory.appendingPathComponent("audio"))
    notifications.add(name: .lccUserInfoChanged) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, let level = self.services?.localCachingClient?.getUserInfo()?.level,
          level != self.lastLevel
        else { return }
        self.lastLevel = level
        self.queueDownloads()
      }
    }
  }

  var voiceActors: [StudyVoiceActor] {
    (services?.localCachingClient?.getVoiceActors() ?? []).map {
      var voice = StudyVoiceActor(id: $0.id)
      voice.name = $0.name
      voice.description = $0.description_p
      voice.gender = $0.gender.rawValue
      return voice
    }
  }
  nonisolated func cacheUrl(subjectId: Int64, voiceActorId: Int64) -> URL {
    downloads.cacheURL(subjectID: subjectId, voiceActorID: voiceActorId)
  }
  nonisolated func isCached(subjectId: Int64, voiceActorId: Int64) -> Bool {
    downloads.isCached(subjectID: subjectId, voiceActorID: voiceActorId)
  }

  func queueDownloads() {
    guard Settings.offlineAudio, let client = services?.localCachingClient else {
      downloads.cancel()
      return
    }
    let level = max(1, Int(client.getUserInfo()?.currentLevel ?? 1))
    let levels = [level] + (1..<level).reversed() + [level + 1]
    let order = Dictionary(
      uniqueKeysWithValues: levels.enumerated().map { ($0.element, $0.offset) })
    let assets = client.getAudioUrls(
      levels: levels, voiceActorIds: Array(Settings.offlineAudioVoiceActors)
    )
    .sorted { (order[$0.level] ?? 0) < (order[$1.level] ?? 0) }
    .map {
      StudyAudioReference(
        subjectID: $0.subjectId, voiceActorID: $0.voiceActorId, level: $0.level, url: $0.url)
    }
    downloads.start(assets, allowsCellular: Settings.offlineAudioCellular)
  }
}
