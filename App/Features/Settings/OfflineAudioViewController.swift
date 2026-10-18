// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import StudyCore
import StudyUI
import SwiftUI

final class OfflineAudioViewController: UIHostingController<AudioLibraryView> {
  init(library: StudyAudioLibrary) { super.init(rootView: AudioLibraryView(library: library)) }
  @MainActor required init?(coder: NSCoder) { fatalError("Use init(library:)") }
}
