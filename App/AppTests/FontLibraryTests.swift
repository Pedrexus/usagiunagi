import Foundation
import StudyCore
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
  @Test func sharedSelectionKeepsTheExistingArchivedPreferenceFormat() {
    let previous = UserDefaults.standard.object(forKey: "selectedFonts")
    defer {
      if let previous {
        UserDefaults.standard.set(previous, forKey: "selectedFonts")
      } else {
        UserDefaults.standard.removeObject(forKey: "selectedFonts")
      }
    }
    Settings.selectedFonts = ["old.ttf"]
    let preferences = LegacyFontPreferences()
    #expect(preferences.selectedFiles == ["old.ttf"])
    preferences.selectedFiles = ["new.ttf", "another.ttf"]
    #expect(Settings.selectedFonts == ["new.ttf", "another.ttf"])
    #expect(UserDefaults.standard.data(forKey: "selectedFonts") != nil)
  }

}

private final class FontFixtureBundle: NSObject {}
