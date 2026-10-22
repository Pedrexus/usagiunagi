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

nonisolated public struct StudyFontDefinition: Sendable {
  public let fontName: String
  public let fileName: String
  public let displayName: String
  public let sizeBytes: Int64
  public init(_ fontName: String, _ fileName: String, _ displayName: String, _ sizeBytes: Int64) {
    self.fontName = fontName
    self.fileName = fileName
    self.displayName = displayName
    self.sizeBytes = sizeBytes
  }
}

@MainActor public final class StudyFont {
  public static let previewText = "色は匂へど散りぬるを我が世誰ぞ常ならん有為の奥山今日越えて浅き夢見じ酔ひもせず"
  public static let definitions: [StudyFontDefinition] = [
    StudyFontDefinition("ArmedBanana", "armed-banana.ttf", "Armed Banana", 3_298_116),
    StudyFontDefinition("darts font", "darts-font.woff", "Darts", 1_349_440),
    StudyFontDefinition("Hina Mincho", "hina-mincho.ttf", "Hina Mincho", 6_428_136),
    StudyFontDefinition("Hosofuwafont", "hoso-fuwa.ttf", "Hoso Fuwa", 5_910_760),
    StudyFontDefinition("nagayama_kai", "nagayama-kai.otf", "Nagayama Kai calligraphy", 15_576_732),
    StudyFontDefinition("Noto Serif JP", "noto-serif-jp.ttf", "Noto Serif", 13_512_012),
    StudyFontDefinition("santyoume-font", "san-chou-me.ttf", "San Chou Me", 4_428_896),
    StudyFontDefinition("Sawarabi Mincho", "sawarabi-mincho.ttf", "Sawarabi Mincho", 1_082_324),
  ]
  public nonisolated static func fontNames(at file: URL) -> [String] {
    guard file.isFileURL else { return [] }
    let descriptors =
      CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] ?? []
    return descriptors.compactMap {
      CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String
    }
  }

  public let definition: StudyFontDefinition
  public private(set) var fontName: String
  public var fileName: String { definition.fileName }
  public var displayName: String { definition.displayName }
  public var sizeBytes: Int64 { definition.sizeBytes }
  public private(set) var available: Bool = false
  private let directory: URL
  private let bundledFonts: URL?

  public init(definition: StudyFontDefinition, directory: URL, bundledFonts: URL?) {
    self.definition = definition
    fontName = definition.fontName
    self.directory = directory
    self.bundledFonts = bundledFonts
    reload()
  }

  public func canRender(_ text: String) -> Bool {
    guard available else { return false }
    let fontRef = CTFontCreateWithName(fontName as CFString, 0.0, nil)
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
      if let name = StudyFont.fontNames(at: url).first,
        names.contains(name) || CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
      {
        fontName = name
        available = true
        return
      }
    }
  }

  func didDelete() { available = false }
}

@MainActor public final class StudyFontCatalog {
  public let allFonts: [StudyFont]
  public let directory: URL

  public init(
    definitions: [StudyFontDefinition] = StudyFont.definitions,
    directory: URL = URL.documentsDirectory.appending(path: "fonts"),
    bundledFonts: URL? = Bundle.main.resourceURL?.appendingPathComponent("fonts")
  ) {
    self.directory = directory
    allFonts = definitions.map {
      StudyFont(definition: $0, directory: directory, bundledFonts: bundledFonts)
    }
  }

  public func font(fileName: String) -> StudyFont? {
    allFonts.first { $0.fileName == fileName }
  }
}
