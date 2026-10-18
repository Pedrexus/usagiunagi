// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import CoreText
import Foundation

struct FontDefinition: Sendable {
  let fontName: String
  let fileName: String
  let displayName: String
  let sizeBytes: Int64
  init(_ fontName: String, _ fileName: String, _ displayName: String, _ sizeBytes: Int64) {
    self.fontName = fontName
    self.fileName = fileName
    self.displayName = displayName
    self.sizeBytes = sizeBytes
  }
}

final class Font {
  static let fontPreviewText = "色は匂へど散りぬるを我が世誰ぞ常ならん有為の奥山今日越えて浅き夢見じ酔ひもせず"
  static let fontDefinitions: [FontDefinition] = [
    FontDefinition("ArmedBanana", "armed-banana.ttf", "Armed Banana", 3_298_116),
    FontDefinition("darts font", "darts-font.woff", "Darts", 1_349_440),
    FontDefinition("Hina Mincho", "hina-mincho.ttf", "Hina Mincho", 6_428_136),
    FontDefinition("Hosofuwafont", "hoso-fuwa.ttf", "Hoso Fuwa", 5_910_760),
    FontDefinition("nagayama_kai", "nagayama-kai.otf", "Nagayama Kai calligraphy", 15_576_732),
    FontDefinition("Noto Serif JP", "noto-serif-jp.ttf", "Noto Serif", 13_512_012),
    FontDefinition("santyoume-font", "san-chou-me.ttf", "San Chou Me", 4_428_896),
    FontDefinition("Sawarabi Mincho", "sawarabi-mincho.ttf", "Sawarabi Mincho", 1_082_324),
  ]
  static func graphicsFont(path: String) -> CGFont? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    return CGFont(provider)
  }

  let definition: FontDefinition
  private(set) var fontName: String
  var fileName: String { definition.fileName }
  var displayName: String { definition.displayName }
  var sizeBytes: Int64 { definition.sizeBytes }
  private(set) var available: Bool = false
  private let directory: URL
  private let bundledFonts: URL?

  init(definition: FontDefinition, directory: URL, bundledFonts: URL?) {
    self.definition = definition
    fontName = definition.fontName
    self.directory = directory
    self.bundledFonts = bundledFonts
    reload()
  }

  func canRender(_ text: String) -> Bool {
    guard available else { return false }
    let fontRef = CTFontCreateWithName(NSString(string: fontName), 0.0, nil)
    let characters = Array(text.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    guard CTFontGetGlyphsForCharacters(fontRef, characters, &glyphs, characters.count) else {
      return false
    }
    // Core Text uses a zero continuation slot for a surrogate pair.
    return glyphs.filter { $0 != 0 }.allSatisfy {
      CTFontCreatePathForGlyph(fontRef, $0, nil) != nil
    }
  }

  func reload() {
    if available { return }
    let names = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
    if names.contains(definition.fontName) {
      available = true
      return
    }
    if (CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []).contains(
      definition.fontName)
    {
      let pattern = CTFontDescriptorCreateWithAttributes(
        [kCTFontFamilyNameAttribute: definition.fontName] as CFDictionary)
      if let match = CTFontDescriptorCreateMatchingFontDescriptor(pattern, nil),
        let name = CTFontDescriptorCopyAttribute(match, kCTFontNameAttribute) as? String
      {
        fontName = name
        available = true
        return
      }
    }
    for url in [
      bundledFonts?.appendingPathComponent(fileName), directory.appendingPathComponent(fileName),
    ].compactMap({ $0 }) {
      if let font = Font.graphicsFont(path: url.path), let name = font.postScriptName as String?,
        names.contains(name) || CTFontManagerRegisterGraphicsFont(font, nil)
      {
        fontName = name
        available = true
        return
      }
    }
  }

  func didDelete() { available = false }
}

final class FontLoader {
  static var cacheDirectoryPath: String {
    "\(NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])/fonts"
  }

  let allFonts: [Font]
  let directory: URL

  init(
    definitions: [FontDefinition] = Font.fontDefinitions,
    directory: URL = URL(fileURLWithPath: FontLoader.cacheDirectoryPath),
    bundledFonts: URL? = Bundle.main.resourceURL?.appendingPathComponent("fonts")
  ) {
    self.directory = directory
    allFonts = definitions.map {
      Font(definition: $0, directory: directory, bundledFonts: bundledFonts)
    }
  }

  func font(fileName: String) -> Font? {
    for font in allFonts {
      if font.fileName == fileName { return font }
    }
    return nil
  }
}
