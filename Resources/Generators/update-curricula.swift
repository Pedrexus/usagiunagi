// Usage: swift Resources/Generators/update-curricula.swift kanjidic2.xml kanji.json kanken.pdf output.plist
// Provenance and redistribution terms: Shared/Sources/StudyCore/Resources/SOURCES.md
import CryptoKit
import Foundation
import PDFKit

#if canImport(FoundationXML)
  import FoundationXML
#endif

enum GenerationError: Error { case invalidSource(String) }

final class Grades: NSObject, XMLParserDelegate {
  var grades: [String: Int] = [:]
  var literal = "", text = "", date = ""
  func parser(
    _ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) { text = "" }
  func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
  func parser(
    _ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
    qualifiedName: String?
  ) {
    if element == "literal" { literal = text }
    if element == "grade", let grade = Int(text) {
      grades[literal] = min(grades[literal] ?? grade, grade)
    }
    if element == "date_of_creation" { date = text }
  }
}
struct Source: Decodable {
  var jlptNew: Int?
  enum CodingKeys: String, CodingKey { case jlptNew = "jlpt_new" }
}
struct Entry: Codable {
  let grade: Int?
  let jlpt: Int?
  let kanken: String?
}
struct Catalog: Encodable {
  let version = 2
  let kanjidicDate: String
  let jlptRevision = "00fd7079c3890f430759536f91aa5e854ec0ca4f"
  let kankenDocumentSHA256: String
  let entries: [String: Entry]
}

/// This extraction deliberately accepts only the visually reviewed 2020 official allocation table.
/// A changed document needs a new layout review rather than silently changing exam scopes.
struct KankenAllocation {
  static let documentSHA256 = "8c7513a4ecfc7d6ca2b8f8aa71313b9097e972bac7a43f8a568fe99a9a1d7285"
  let levels: [String: String]

  init(pdf: URL, grades: [String: Int]) throws {
    let data = try Data(contentsOf: pdf)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard digest == Self.documentSHA256, let document = PDFDocument(data: data),
      document.pageCount == 15
    else { throw GenerationError.invalidSource("Unreviewed Kanji Kentei document") }
    let joyo = Set(grades.filter { (1...6).contains($0.value) || $0.value == 8 }.keys)
    var levels = Dictionary(
      uniqueKeysWithValues: grades.compactMap { character, grade in
        (1...6).contains(grade) ? (character, String(11 - grade)) : nil
      })
    for (level, firstPage, count) in [("4", 8, 313), ("3", 10, 284), ("pre2", 12, 328)] {
      var characters: [String] = []
      for (offset, width) in [(0, 425), (1, 470)] {
        guard let page = document.page(at: firstPage - 1 + offset),
          page.bounds(for: .mediaBox) == CGRect(x: 0, y: 0, width: 540, height: 780),
          page.rotation == 0,
          let text = page.selection(for: CGRect(x: 18, y: 30, width: width, height: 700))?.string
        else { throw GenerationError.invalidSource("Kanji Kentei table layout changed") }
        characters += text.unicodeScalars.filter {
          (0x3400...0x9fff).contains($0.value) || (0xf900...0xfaff).contains($0.value)
        }.map { String($0).precomposedStringWithCanonicalMapping }
      }
      let unique = Set(characters)
      guard characters.count == count, unique.count == count,
        unique.isSubset(of: joyo), unique.allSatisfy({ levels[$0] == nil })
      else {
        throw GenerationError.invalidSource("Unexpected Kanji Kentei level \(level) allocation")
      }
      for character in unique { levels[character] = level }
    }
    for character in joyo where levels[character] == nil { levels[character] = "2" }
    let order = ["10", "9", "8", "7", "6", "5", "4", "3", "pre2", "2"]
    var cumulative = 0
    let totals = order.map { level in
      cumulative += levels.values.filter { $0 == level }.count
      return cumulative
    }
    guard totals == [80, 240, 440, 642, 835, 1026, 1339, 1623, 1951, 2136] else {
      throw GenerationError.invalidSource("Unexpected cumulative Kanji Kentei scopes: \(totals)")
    }
    self.levels = levels
  }
}

guard CommandLine.arguments.count == 5 else {
  fatalError("Expected KANJIDIC XML, JLPT JSON, official Kanji Kentei PDF and output paths")
}
let parser = XMLParser(data: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let delegate = Grades()
parser.delegate = delegate
guard parser.parse() else { throw parser.parserError! }
let jlpt = try JSONDecoder().decode(
  [String: Source].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
let kanken = try KankenAllocation(
  pdf: URL(fileURLWithPath: CommandLine.arguments[3]), grades: delegate.grades)
let characters = Set(delegate.grades.keys).union(jlpt.filter { $0.value.jlptNew != nil }.keys)
let entries = Dictionary(
  uniqueKeysWithValues: characters.map {
    ($0, Entry(grade: delegate.grades[$0], jlpt: jlpt[$0]?.jlptNew, kanken: kanken.levels[$0]))
  })
let catalog = Catalog(
  kanjidicDate: delegate.date, kankenDocumentSHA256: KankenAllocation.documentSHA256,
  entries: entries)
let encoder = PropertyListEncoder()
encoder.outputFormat = .binary
try encoder.encode(catalog).write(
  to: URL(fileURLWithPath: CommandLine.arguments[4]), options: .atomic)
print(
  "Wrote \(entries.count) entries; all ten Kanji Kentei scopes use the reviewed official allocation"
)
