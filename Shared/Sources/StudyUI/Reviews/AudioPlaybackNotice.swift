import StudyCore
import SwiftUI

struct AudioPlaybackNotice: View {
  let library: StudyAudioLibrary
  var body: some View {
    if let error = library.error {
      HStack(alignment: .top) {
        Label {
          Text(
            error
              + (library.voiceInputActive
                ? "" : " Download pronunciation in Settings to make it available offline."))
        } icon: {
          Image(systemName: "speaker.slash")
        }
        Spacer()
        Button("Dismiss audio message", systemImage: "xmark") { library.stop() }.labelStyle(
          .iconOnly)
      }.font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("review.audioError")
    }
  }
}
