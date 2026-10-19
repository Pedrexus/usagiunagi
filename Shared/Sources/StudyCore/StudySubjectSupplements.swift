// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import Foundation

/// One immutable catalog for the original radical mnemonics and similar-kanji lists.
public struct StudySubjectSupplements: Sendable {
  let mnemonics: [String: String]
  let similar: [String: String]
  public static let bundled: Result<Self, any Error> = Result {
    func load(_ name: String) throws -> [String: String] {
      guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
        throw CocoaError(.fileReadNoSuchFile)
      }
      return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }
    return try Self(mnemonics: load("old-mnemonics"), similar: load("visually-similar-kanji"))
  }
  public func deprecatedMnemonic(subjectID: Int64) -> String? { mnemonics[String(subjectID)] }
  public func similarKanji(to characters: String) -> String? { similar[characters] }
}
