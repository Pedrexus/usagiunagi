// Copyright David Sansome. Licensed under the Apache License, Version 2.0.
import Foundation

/// Rebuilds the bundled supplement without a second language/runtime dependency.
struct SimilarKanjiIndex {
  struct Entry: Codable {
    let kan: String
    var score: Double
  }
  private var entries: [String: [Entry]] = [:]

  mutating func add(_ character: String, similar: String, score: Float) {
    let score = Double(score)
    if let index = entries[character]?.firstIndex(where: { $0.kan == similar }) {
      entries[character]![index].score = max(entries[character]![index].score, score)
    } else {
      entries[character, default: []].append(Entry(kan: similar, score: score))
    }
  }

  mutating func load(from directory: URL) throws {
    let decoder = PropertyListDecoder()
    for name in ["from_keisei", "manual", "old_script"] {
      let data = try Data(contentsOf: directory.appendingPathComponent("\(name).plist"))
      for (character, values) in try decoder.decode([String: [String]].self, from: data) {
        for value in values { add(character, similar: value, score: 1) }
      }
    }
    for name in ["stroke_edit_dist", "wk_niai_noto", "yl_radical"] {
      let data = try Data(contentsOf: directory.appendingPathComponent("\(name).plist"))
      for (character, values) in try decoder.decode([String: [Entry]].self, from: data) {
        for value in values {
          // Preserve the original JSON decoder’s Float rounding, threshold and equal-score ties.
          let score = Float(value.score)
          if score > 0.4 { add(character, similar: value.kan, score: score) }
        }
      }
    }
  }

  var compact: [String: String] {
    entries.mapValues { values in
      values.enumerated().sorted {
        $0.element.score == $1.element.score
          ? $0.offset < $1.offset : $0.element.score > $1.element.score
      }.map(\.element.kan).joined()
    }
  }
}

guard CommandLine.arguments.count == 2 else {
  fatalError("Expected an output property-list path")
}
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
var index = SimilarKanjiIndex()
try index.load(from: directory)
let encoder = PropertyListEncoder()
encoder.outputFormat = .binary
let output = try encoder.encode(index.compact)
try output.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
print("Wrote \(index.compact.count) similar-kanji entries")
