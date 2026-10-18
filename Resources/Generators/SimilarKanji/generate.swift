// Copyright David Sansome. Licensed under the Apache License, Version 2.0.
import Foundation

/// Rebuilds the bundled supplement without a second language/runtime dependency.
struct SimilarKanjiIndex {
  struct Entry: Codable {
    let kan: String
    var score: Float
  }
  private var entries: [String: [Entry]] = [:]

  mutating func add(_ character: String, similar: String, score: Float) {
    if let index = entries[character]?.firstIndex(where: { $0.kan == similar }) {
      entries[character]![index].score = max(entries[character]![index].score, score)
    } else {
      entries[character, default: []].append(Entry(kan: similar, score: score))
    }
  }

  mutating func load(from directory: URL) throws {
    let decoder = JSONDecoder()
    for name in ["from_keisei", "manual", "old_script"] {
      let data = try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
      for (character, values) in try decoder.decode([String: [String]].self, from: data) {
        for value in values { add(character, similar: value, score: 1) }
      }
    }
    for name in ["stroke_edit_dist", "wk_niai_noto", "yl_radical"] {
      let data = try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
      for (character, values) in try decoder.decode([String: [Entry]].self, from: data) {
        for value in values where value.score > 0.4 {
          add(character, similar: value.kan, score: value.score)
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

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
var index = SimilarKanjiIndex()
try index.load(from: directory)
let encoder = JSONEncoder()
encoder.outputFormatting = .sortedKeys
var output = try encoder.encode(index.compact)
output.append(0x0A)
try FileHandle.standardOutput.write(contentsOf: output)
