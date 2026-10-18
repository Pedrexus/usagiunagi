// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Foundation
import StudyCore

/// Temporary catalog adapter; shared code owns downloads, selection and playback.
@MainActor final class OfflineAudio {
  private weak var services: TKMServices?
  private let notifications = NotificationDispatcher()
  init(services: TKMServices) {
    self.services = services
    notifications.add(name: .lccUserInfoChanged) { [weak self] _ in
      Task { @MainActor [weak self] in self?.queueDownloads() }
    }
  }
  func queueDownloads() {
    guard let services else { return }
    guard let client = services.localCachingClient, let user = client.getUserInfo() else {
      services.audio.updateCatalog(nil)
      return
    }
    let voices = client.getVoiceActors().map {
      var voice = StudyVoiceActor(id: $0.id)
      voice.name = $0.name
      voice.description = $0.description_p
      voice.gender = $0.gender.rawValue
      return voice
    }
    let current = max(1, Int(user.currentLevel))
    let levels = Array(1...max(1, min(current + 1, Int(user.maxLevelGrantedBySubscription))))
    let assets = client.getAudioUrls(levels: levels, voiceActorIds: voices.map(\.id)).map {
      StudyAudioReference(
        subjectID: $0.subjectId, voiceActorID: $0.voiceActorId, level: $0.level, url: $0.url)
    }
    services.audio.updateCatalog(
      StudyAudioCatalog(
        accountID: user.username, currentLevel: current,
        maximumLevel: Int(user.maxLevelGrantedBySubscription), voices: voices, audio: assets))
  }
}
