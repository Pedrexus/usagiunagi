import StudyCore
import SwiftUI

struct AudioLibraryView: View {
  @Bindable var library: StudyAudioLibrary
  var body: some View {
    OfflineAudioView(
      enabled: library.options.enabled, cellular: library.options.cellular,
      selectedVoices: library.options.voiceIDs, voices: library.voices,
      downloads: library.downloads, action: library.send
    )
    .task {
      library.reloadPreferences()
      await library.downloads.refreshCacheSize()
    }
  }
}
