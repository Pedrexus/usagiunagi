// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import StudyCore
import StudyUI
import SwiftUI

/// Temporary navigation bridge; downloads and UI are owned by the shared package.
final class FontsViewController: UIHostingController<FontLibraryView> {
  init(library: StudyFontLibrary) { super.init(rootView: FontLibraryView(library: library)) }
  @MainActor required init?(coder: NSCoder) { fatalError("Use init(library:)") }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(false, animated: animated)
  }
}
