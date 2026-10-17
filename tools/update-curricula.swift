// Usage: swift tools/update-curricula.swift kanjidic2.xml kanji.json output.json
// Input provenance and redistribution terms: StudyKit/Sources/StudyCore/Resources/SOURCES.md
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

final class Grades: NSObject, XMLParserDelegate {
    var grades: [String: Int] = [:]
    var literal = "", text = "", date = ""
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) { text = "" }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "literal" { literal = text }
        if element == "grade", let grade = Int(text) { grades[literal] = min(grades[literal] ?? grade, grade) }
        if element == "date_of_creation" { date = text }
    }
}
struct Source: Decodable { var jlpt_new: Int? }
struct Entry: Codable { let grade: Int?; let jlpt: Int? }
struct Catalog: Encodable { let version: Int; let kanjidicDate: String; let jlptRevision: String; let entries: [String: Entry] }
guard CommandLine.arguments.count == 4 else { fatalError("Expected XML, JLPT JSON and output paths") }
let parser = XMLParser(data: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let delegate = Grades(); parser.delegate = delegate
guard parser.parse() else { throw parser.parserError! }
let jlpt = try JSONDecoder().decode([String: Source].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
let characters = Set(delegate.grades.keys).union(jlpt.filter { $0.value.jlpt_new != nil }.keys)
let entries = Dictionary(uniqueKeysWithValues: characters.map { ($0, Entry(grade: delegate.grades[$0], jlpt: jlpt[$0]?.jlpt_new)) })
let gradeCounts = (1...6).map { grade in entries.values.filter { $0.grade == grade }.count }
guard gradeCounts == [80, 160, 200, 202, 193, 191], entries.values.filter({ (1...6).contains($0.grade ?? 0) || $0.grade == 8 }).count == 2136 else {
    fatalError("Unexpected grade totals: \(gradeCounts), \(delegate.grades.count) classified; review source changes before updating")
}
let catalog = Catalog(version: 1, kanjidicDate: delegate.date, jlptRevision: "00fd7079c3890f430759536f91aa5e854ec0ca4f", entries: entries)
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(catalog).write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
print("Wrote \(entries.count) entries; school grades \(gradeCounts)")
