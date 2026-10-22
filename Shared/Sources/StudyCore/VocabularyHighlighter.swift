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

import Foundation

/// Non-overlapping, leftmost-longest vocabulary matches, including the original study inflections.
public enum VocabularyHighlighter {
  public static func ranges(of subject: CatalogSubject, in text: String) -> [Range<String.Index>] {
    guard subject.kind == .vocabulary, !subject.japanese.isEmpty, !text.isEmpty else { return [] }
    let pattern = pattern(for: subject)
    guard let search = try? NSRegularExpression(pattern: pattern),
      let complete = try? NSRegularExpression(pattern: "\\A(?:" + pattern + ")\\z")
    else { return [] }

    var result: [Range<String.Index>] = []
    var cursor = text.startIndex
    while cursor < text.endIndex,
      let first = search.firstMatch(in: text, range: NSRange(cursor..<text.endIndex, in: text)),
      let range = Range(first.range, in: text), !range.isEmpty
    {
      // Foundation alternatives prefer their first branch; Rexy's POSIX matching preferred the
      // longest. Matching complete prefixes preserves that behavior even inside nested alternatives.
      // The table uses only finite alternatives and optional groups, so pattern size bounds a match.
      var end =
        text.index(
          range.lowerBound, offsetBy: pattern.utf16.count, limitedBy: text.endIndex)
        ?? text.endIndex
      while end > range.upperBound {
        let candidate = String(text[range.lowerBound..<end])
        if complete.firstMatch(
          in: candidate,
          range: NSRange(
            candidate.startIndex..<candidate.endIndex,
            in: candidate)) != nil
        {
          break
        }
        end = text.index(before: end)
      }
      result.append(range.lowerBound..<end)
      cursor = end
    }
    return result
  }

  private static func pattern(for subject: CatalogSubject) -> String {
    var patterns = [NSRegularExpression.escapedPattern(for: subject.japanese)]
    for value in subject.partsOfSpeech {
      guard let part = Inflection(rawValue: value),
        let group = ConjugationGroup.get(for: subject.japanese, partOfSpeech: part)
      else { continue }
      var stem = subject.japanese
      if stem.hasPrefix(group.prefix) { stem = String(stem.dropFirst(group.prefix.count)) }
      if stem.hasSuffix(group.suffix) { stem = String(stem.dropLast(group.suffix.count)) }
      if !stem.isEmpty {
        patterns.append(NSRegularExpression.escapedPattern(for: stem) + group.pattern)
      }
    }
    return "(?:" + patterns.joined(separator: "|") + ")"
  }

  // These persisted values are populated by native catalog downloads.
  fileprivate enum Inflection: Int {
    case ichidanVerb = 4
    case godanVerb = 7
    case naAdjective = 8
    case iAdjective = 9
    case suffix = 10
    case adverb = 11
    case suruVerb = 12
    case prefix = 13
    case counter = 18
  }
}

private struct ConjugationGroup: Sendable {
  let prefix: String
  let suffix: String
  let pattern: String

  init(prefix: String = "", suffix: String = "", conjugations: [String] = []) {
    self.prefix = prefix
    self.suffix = suffix
    let nonEmpty = conjugations.filter { !$0.isEmpty }
    pattern =
      "(" + nonEmpty.joined(separator: "|") + ")"
      + (nonEmpty.count == conjugations.count ? "" : "?")
  }

  private static func verb(
    suffix: String, te: String, perfective: String, negative: String, continuous: String,
    potential: String, passive: String, causative: String, provisionalConditional: String,
    imperative: String, volitional: String, cha: String, extraConjugations: [String] = []
  ) -> Self {
    Self(
      suffix: suffix,
      conjugations: [
        suffix,
        continuous,
        continuous + "ます",
        continuous + "たい",
        volitional + "う",
        suffix + "だろう",
        continuous + "ましょう",
        suffix + "でしょう",
        imperative,
        te,
        te + "ください",
        perfective,
        continuous + "ました",
        perfective + "ろう",
        perfective + "でしょう",
        te + "い(て|てい)?(る|て|た|ます|ました)",
        te + "る",
        te + "ます",
        te + "た",
        te + "ました",
        provisionalConditional + "ば",
        perfective + "ら",
        perfective + "らば",
        continuous + "ましたら",
        potential + "る",
        potential + "ます",
        causative + "せ(て|てい)?(る|て|た|ます|ました)",
        passive + "れ(て|てい)?(る|て|た|ます|ました)",
        causative + "せられ(て|てい)?(る|て|た|ます|ました)",

        negative + "ない",
        negative + "なかった",
        negative + "ぬ",
        continuous + "ません",
        continuous + "たくない",
        negative + "ないだろう",
        negative + "ぬだろう",
        negative + "ないでしょう",
        suffix + "な",
        negative + "ないでください",
        continuous + "ませんでした",
        negative + "なかっただろう",
        negative + "なかったでしょう",
        te + "いません(でした)?",
        te + "ません(でした)?",
        negative + "なければ",
        negative + "なきゃ",
        negative + "なくちゃ",
        negative + "なくなちゃった",
        negative + "なかったら",
        continuous + "ませんでしたら",
        potential + "ない",
        potential + "ません",
        causative + "せ(て|てい)?(ない|ないで|ません|ませんでした)",
        passive + "れ(て|てい)?(ない|ないで|ません|ませんでした)",
        causative + "せられ(て|てい)?(ない|ないで|ません|ませんでした)",

        te + "しまう",
        te + "しまった",
        te + "しまってた?",
        te + "しまいます",
        te + "しまいました",
        cha + "ゃう",
        cha + "ゃわない",
        cha + "ゃいます",
        cha + "ゃいません",
        cha + "ゃ",
        cha + "ゃった",
        cha + "ゃってた?",
        cha + "ゃわなかった",
        cha + "ゃわなくっ?て",
        cha + "ゃいました",
        cha + "ゃいませんでした",
      ] + extraConjugations)
  }

  private static func godanVerb(
    _ a: String, _ i: String, _ u: String, _ e: String, _ o: String,
    _ te: String, _ ta: String, _ cha: String
  ) -> Self {
    verb(
      suffix: u, te: te, perfective: ta, negative: a, continuous: i, potential: e,
      passive: a, causative: a, provisionalConditional: e, imperative: e, volitional: o, cha: cha)
  }

  private static let godanVerbs: [Character: Self] = [
    "う": godanVerb("わ", "い", "う", "え", "お", "って", "った", "っち"),
    "く": godanVerb("か", "き", "く", "け", "こ", "いて", "いた", "いち"),
    "ぐ": godanVerb("が", "ぎ", "ぐ", "げ", "ご", "いで", "いだ", "いじ"),
    "す": godanVerb("さ", "し", "す", "せ", "そ", "して", "した", "しち"),
    "つ": godanVerb("た", "ち", "つ", "て", "と", "って", "った", "っち"),
    "づ": godanVerb("だ", "ぢ", "づ", "で", "ど", "っで", "っだ", "っじ"),
    "ふ": godanVerb("は", "ひ", "ふ", "へ", "ほ", "んで", "んだ", "んじ"),
    "ぶ": godanVerb("ば", "び", "ぶ", "べ", "ぼ", "んで", "んだ", "んじ"),
    "む": godanVerb("ま", "み", "む", "め", "も", "んで", "んだ", "んじ"),
    "る": godanVerb("ら", "り", "る", "れ", "ろ", "って", "った", "っち"),
    "ぬ": godanVerb("な", "に", "ぬ", "ね", "の", "んで", "んだ", "んじ"),
  ]

  private static let ichidanVerb = verb(
    suffix: "る", te: "て", perfective: "た", negative: "", continuous: "", potential: "られ",
    passive: "ら", causative: "さ", provisionalConditional: "れ", imperative: "ろ", volitional: "よ",
    cha: "ち")

  private static let suruVerb = verb(
    suffix: "する", te: "して", perfective: "した", negative: "し", continuous: "し", potential: "せられ",
    passive: "さ", causative: "さ", provisionalConditional: "すれ", imperative: "しろ", volitional: "しよ",
    cha: "っち", extraConjugations: [""])  // Allow the suru verb stem by itself.

  private static let iAdjective = Self(
    suffix: "い",
    conjugations: [
      "", "い", "いです", "かった(です)?", "くない(です)?", "くなかった(です)?", "く", "くて", "ければ", "かろう",
    ])

  private static let naAdjective = Self(conjugations: [
    "", "だ", "です", "な", "で", "だった", "でした", "でわない", "じゃない", "であれば", "だろう",
  ])

  static func get(for japanese: String, partOfSpeech: VocabularyHighlighter.Inflection) -> Self? {
    switch partOfSpeech {
    case .godanVerb: japanese.last.flatMap { godanVerbs[$0] }
    case .ichidanVerb: ichidanVerb
    case .suruVerb: suruVerb
    case .iAdjective: iAdjective
    case .naAdjective: naAdjective
    case .prefix, .adverb: Self(suffix: "〜")
    case .suffix, .counter: Self(prefix: "〜")
    }
  }
}
