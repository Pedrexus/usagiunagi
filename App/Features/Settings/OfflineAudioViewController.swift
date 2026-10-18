// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import StudyUI
import SwiftUI
import UIKit

final class OfflineAudioViewController: UIHostingController<OfflineAudioContent?> {
  required init?(coder: NSCoder) { super.init(coder: coder, rootView: nil) }
  func setup(services: TKMServices) { rootView = OfflineAudioContent(model: services.offlineAudio) }
}

struct OfflineAudioContent: View {
  let model: OfflineAudio
  @ArchivedPreference(Settings.$offlineAudio) private var enabled: Bool
  @ArchivedPreference(Settings.$offlineAudioCellular) private var cellular: Bool
  @ArchivedPreference(Settings.$offlineAudioVoiceActors) private var voices: Set<Int64>
  var body: some View {
    OfflineAudioView(
      enabled: enabled, cellular: cellular, selectedVoices: voices,
      voices: model.voiceActors, downloads: model.downloads, action: send
    )
    .task { await model.downloads.refreshCacheSize() }
  }

  private func send(_ action: OfflineAudioAction) {
    switch action {
    case .enabled(let value):
      enabled = value
      if value && voices.isEmpty { voices = Set(model.voiceActors.map(\.id)) }
    case .cellular(let value): cellular = value
    case .voice(let id, let value):
      if value { voices.insert(id) } else { voices.remove(id) }
    case .retry: break
    case .delete:
      enabled = false
      model.queueDownloads()
      Task { await model.downloads.deleteAll() }
      return
    }
    model.queueDownloads()
  }
}
