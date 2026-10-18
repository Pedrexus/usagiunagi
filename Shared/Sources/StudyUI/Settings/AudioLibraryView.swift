import StudyCore
import SwiftUI

public struct AudioLibraryView: View {
  @Bindable private var library: StudyAudioLibrary
  public init(library: StudyAudioLibrary) { self.library = library }
  public var body: some View {
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
