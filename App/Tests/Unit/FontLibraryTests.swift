import Foundation
import Testing

@testable import Tsurukame

@Suite(.serialized) @MainActor
struct FontLibraryTests {
  private func sources() throws -> URL {
    try #require(Bundle(for: FontFixtureBundle.self).resourceURL?.appendingPathComponent("fonts"))
  }

  @Test func originalCatalogFilesActivateAndGlyphChecksHandleUTF16() throws {
    let loader = StudyFontCatalog(
      directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
      bundledFonts: try sources())
    #expect(loader.allFonts.map(\.fileName) == StudyFont.definitions.map(\.fileName))
    for font in loader.allFonts { #expect(font.available, "\(font.fileName)") }
    let noto = try #require(loader.font(fileName: "noto-serif-jp.ttf"))
    #expect(noto.canRender("私自身"))
    #expect(noto.canRender("𠮟"))
    #expect(!noto.canRender("\u{10FFFF}"))
  }
  @Test func sharedSelectionPersistsInNativeDefaults() throws {
    try PreferenceTestValues.withDefaults { defaults in
      defaults.set("keep", forKey: "unrelated")
      let preferences = DefaultsStudyFontPreferences(defaults: defaults)
      preferences.selectedFiles = ["old.ttf"]
      #expect(DefaultsStudyFontPreferences(defaults: defaults).selectedFiles == ["old.ttf"])
      preferences.selectedFiles = ["new.ttf", "another.ttf"]
      #expect(
        DefaultsStudyFontPreferences(defaults: defaults).selectedFiles == [
          "new.ttf", "another.ttf",
        ])
      #expect(defaults.stringArray(forKey: "native.selectedFonts") == ["another.ttf", "new.ttf"])
      #expect(defaults.string(forKey: "unrelated") == "keep")
    }
  }
}

private final class FontFixtureBundle: NSObject {}
