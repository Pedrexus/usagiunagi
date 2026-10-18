// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import StudyCore
import SwiftUI

@main struct FontScreenshotterApp: App {
  private let loader = StudyFontCatalog()
  var body: some Scene {
    WindowGroup {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          ForEach(loader.allFonts, id: \.fileName) { font in
            VStack(alignment: .leading, spacing: 8) {
              Text(font.displayName).font(.headline)
              Text(StudyFont.previewText).font(.custom(font.fontName, size: 24))
                .frame(width: 320, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(font.definition.fontName).accessibilityIdentifier("preview")
            }
          }
        }.padding(15).frame(width: 360, alignment: .leading)
      }.foregroundStyle(.black).background(.white).preferredColorScheme(.light)
    }
  }
}
