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

import CoreFoundation
import Foundation

public enum KanaAlphabet: Sendable {
  case hiragana, katakana
}

/// Romaji conversion shared by review input, grading and catalog search.
/// UTF-16 offsets intentionally match native text-field selection and the original converter.
public enum KanaConverter {
  public struct Conversion: Equatable, Sendable {
    public let text: String
    public let convertedAllCharacters: Bool
  }

  /// An edit applied before the native text field processes the proposed insertion.
  public struct Edit: Equatable, Sendable {
    public let text: String
    public let allowsSystemChange: Bool
    /// Nil preserves the existing selection; a value collapses it to this UTF-16 offset.
    public let cursor: Int?
  }

  // Group aliases by kana to keep the complete legacy table readable without duplicate values.
  static let replacements: [String: String] = {
    let groups: [(String, String)] = [
      ("あ", "a"),
      ("ば", "ba"),
      ("べ", "be"),
      ("び", "bi"),
      ("ぼ", "bo"),
      ("ぶ", "bu"),
      ("びゃ", "bya"),
      ("びぇ", "bye"),
      ("びぃ", "byi"),
      ("びょ", "byo"),
      ("びゅ", "byu"),
      ("か", "ca ka"),
      ("け", "ce ke"),
      ("ちゃ", "cha chya cya tya"),
      ("ちぇ", "che chye cye tye"),
      ("ち", "chi ti"),
      ("ちょ", "cho chyo cyo tyo"),
      ("ちゅ", "chu chyu cyu tyu"),
      ("き", "ci ki"),
      ("こ", "co ko"),
      ("く", "cu ku"),
      ("ちぃ", "cyi tyi"),
      ("だ", "da"),
      ("で", "de"),
      ("でゃ", "dha"),
      ("でぇ", "dhe"),
      ("でぃ", "dhi"),
      ("でょ", "dho"),
      ("でゅ", "dhu"),
      ("ぢ", "di"),
      ("ど", "do"),
      ("づ", "du"),
      ("どぁ", "dwa"),
      ("どぇ", "dwe"),
      ("どぃ", "dwi"),
      ("どぉ", "dwo"),
      ("どぅ", "dwu"),
      ("ぢゃ", "dya"),
      ("ぢぇ", "dye"),
      ("ぢぃ", "dyi"),
      ("ぢょ", "dyo"),
      ("ぢゅ", "dyu"),
      ("え", "e"),
      ("ふぁ", "fa fwa"),
      ("ふぇ", "fe fwe fye"),
      ("ふぃ", "fi fwi fyi"),
      ("ふぉ", "fo fwo"),
      ("ふ", "fu hu"),
      ("ふぅ", "fwu"),
      ("ふゃ", "fya"),
      ("ふょ", "fyo"),
      ("ふゅ", "fyu"),
      ("が", "ga"),
      ("げ", "ge"),
      ("ぎ", "gi"),
      ("ご", "go"),
      ("ぐ", "gu"),
      ("ぐぁ", "gwa"),
      ("ぐぇ", "gwe"),
      ("ぐぃ", "gwi"),
      ("ぐぉ", "gwo"),
      ("ぐぅ", "gwu"),
      ("ぎゃ", "gya"),
      ("ぎぇ", "gye"),
      ("ぎぃ", "gyi"),
      ("ぎょ", "gyo"),
      ("ぎゅ", "gyu"),
      ("は", "ha"),
      ("へ", "he"),
      ("ひ", "hi"),
      ("ほ", "ho"),
      ("ひゃ", "hya"),
      ("ひぇ", "hye"),
      ("ひぃ", "hyi"),
      ("ひょ", "hyo"),
      ("ひゅ", "hyu"),
      ("い", "i yi"),
      ("じゃ", "ja jya zya"),
      ("じぇ", "je jye zye"),
      ("じ", "ji zi"),
      ("じょ", "jo jyo zyo"),
      ("じゅ", "ju jyu zyu"),
      ("じぃ", "jyi zyi"),
      ("くぁ", "kwa qa qwa"),
      ("きゃ", "kya"),
      ("きぇ", "kye"),
      ("きぃ", "kyi"),
      ("きょ", "kyo"),
      ("きゅ", "kyu"),
      ("ら", "la ra"),
      ("ヵ", "lca lka xca xka"),
      ("ヶ", "lce lke xce xke"),
      ("れ", "le re"),
      ("り", "li ri"),
      ("ろ", "lo ro"),
      ("っ", "ltsu ltu xtu"),
      ("る", "lu ru"),
      ("ゎ", "lwe xwa"),
      ("りゃ", "lya rya"),
      ("りぇ", "lye rye"),
      ("りぃ", "lyi ryi"),
      ("りょ", "lyo ryo"),
      ("りゅ", "lyu ryu"),
      ("ま", "ma"),
      ("め", "me"),
      ("み", "mi"),
      ("も", "mo"),
      ("む", "mu"),
      ("みゃ", "mya"),
      ("みぇ", "mye"),
      ("みぃ", "myi"),
      ("みょ", "myo"),
      ("みゅ", "myu"),
      ("な", "na"),
      ("ね", "ne"),
      ("に", "ni"),
      ("ん", "nn xn"),
      ("の", "no"),
      ("ぬ", "nu"),
      ("にゃ", "nya"),
      ("にぇ", "nye"),
      ("にぃ", "nyi"),
      ("にょ", "nyo"),
      ("にゅ", "nyu"),
      ("お", "o"),
      ("ぱ", "pa"),
      ("ぺ", "pe"),
      ("ぴ", "pi"),
      ("ぽ", "po"),
      ("ぷ", "pu"),
      ("ぴゃ", "pya"),
      ("ぴぇ", "pye"),
      ("ぴぃ", "pyi"),
      ("ぴょ", "pyo"),
      ("ぴゅ", "pyu"),
      ("くぇ", "qe qwe qye"),
      ("くぃ", "qi qwi qyi"),
      ("くぉ", "qo qwo"),
      ("くぅ", "qwu"),
      ("くゃ", "qya"),
      ("くょ", "qyo"),
      ("くゅ", "qyu"),
      ("さ", "sa"),
      ("せ", "se"),
      ("しゃ", "sha shya sya"),
      ("しぇ", "she shye sye"),
      ("し", "shi si"),
      ("しょ", "sho shyo syo"),
      ("しゅ", "shu shyu syu"),
      ("そ", "so"),
      ("す", "su"),
      ("すぁ", "swa"),
      ("すぇ", "swe"),
      ("すぃ", "swi"),
      ("すぉ", "swo"),
      ("すぅ", "swu"),
      ("しぃ", "syi"),
      ("た", "ta"),
      ("て", "te"),
      ("てゃ", "tha"),
      ("てぇ", "the"),
      ("てぃ", "thi"),
      ("てょ", "tho"),
      ("てゅ", "thu"),
      ("と", "to"),
      ("つぁ", "tsa"),
      ("つぇ", "tse"),
      ("つぃ", "tsi"),
      ("つぉ", "tso"),
      ("つ", "tsu tu"),
      ("とぁ", "twa"),
      ("とぇ", "twe"),
      ("とぃ", "twi"),
      ("とぉ", "two"),
      ("とぅ", "twu"),
      ("う", "u whu wu"),
      ("ゔぁ", "va"),
      ("ゔぇ", "ve vye"),
      ("ゔぃ", "vi vyi"),
      ("ゔぉ", "vo"),
      ("ゔ", "vu"),
      ("ゔゃ", "vya"),
      ("ゔょ", "vyo"),
      ("ゔゅ", "vyu"),
      ("わ", "wa"),
      ("うぇ", "we whe"),
      ("うぁ", "wha"),
      ("うぃ", "whi wi"),
      ("うぉ", "who"),
      ("を", "wo"),
      ("ぁ", "xa"),
      ("ぇ", "xe xye"),
      ("ぃ", "xi xyi"),
      ("ぉ", "xo"),
      ("ぅ", "xu"),
      ("ゃ", "xya"),
      ("ょ", "xyo"),
      ("ゅ", "xyu"),
      ("や", "ya"),
      ("いぇ", "ye"),
      ("よ", "yo"),
      ("ゆ", "yu"),
      ("ざ", "za"),
      ("ぜ", "ze"),
      ("ぞ", "zo"),
      ("ず", "zu"),
      ("ー", "-"),
    ]
    var result = ["n ": "ん"]
    for (kana, aliases) in groups {
      for alias in aliases.split(separator: " ") { result[String(alias)] = kana }
    }
    return result
  }()

  static let consonants = Set("bcdfghjklmnpqrstvwxyz".utf16)
  private static let vowels = Set("aeiou".utf16)
  private static let nasal = Set("nm".utf16)
  private static let canFollowN = Set("aiueony".utf16)

  /// Preserves legacy whole-string conversion, including incomplete trailing-romaji reporting.
  /// This differs deliberately from interactive input: uppercase is left unchanged here.
  public static func convert(_ input: String) -> Conversion {
    let text = NSMutableString(string: input)
    var index = 0
    while index < text.length {
      let current = text.character(at: index)
      if index > 0, current != 110, current == text.character(at: index - 1),
        consonants.contains(current)
      {
        text.replaceCharacters(in: NSRange(location: index - 1, length: 1), with: "っ")
        index += 1
        continue
      }
      for length in stride(from: min(4, index + 1), through: 1, by: -1) {
        let range = NSRange(location: index - length + 1, length: length)
        if let replacement = replacements[text.substring(with: range)] {
          text.replaceCharacters(in: range, with: replacement)
          index -= length - 1
          break
        }
      }
      index += 1
    }
    for index in 0..<text.length where nasal.contains(text.character(at: index)) {
      text.replaceCharacters(in: NSRange(location: index, length: 1), with: "ん")
    }
    var complete = true
    let lowercase = NSCharacterSet.lowercaseLetters as NSCharacterSet
    while text.length > 0, lowercase.characterIsMember(text.character(at: text.length - 1)) {
      text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
      complete = false
    }
    return Conversion(text: text as String, convertedAllCharacters: complete)
  }

  /// A native dictionary reading of written Japanese, not verified phonetics from speech.
  /// Ambiguous forms such as 生 or 一日 may receive a different reading than the speaker used.
  /// Prefer recognizer-provided kana before this fallback; never infer the expected study answer.
  public static func hiraganaReading(_ text: String) -> String? {
    guard text.utf16.count <= 256 else { return nil }
    let input = text.precomposedStringWithCompatibilityMapping
      .components(separatedBy: .whitespacesAndNewlines).joined()
    guard !input.isEmpty, input.utf16.count <= 256 else { return nil }
    if let kana = readingKana(input) { return kana }
    guard
      input.unicodeScalars.allSatisfy({ scalar in
        scalar.properties.isIdeographic || scalar == "々"
          || (0x3041...0x30FA).contains(scalar.value) || scalar == "ー"
          || (0x30...0x39).contains(scalar.value)
      }), let expanded = readingNumerals(input)
    else { return nil }
    let locale = CFLocaleCreate(
      kCFAllocatorDefault, CFLocaleIdentifier(rawValue: "ja_JP" as CFString))
    guard
      let tokenizer = CFStringTokenizerCreate(
        kCFAllocatorDefault, expanded as CFString, CFRangeMake(0, (expanded as NSString).length),
        CFOptionFlags(kCFStringTokenizerUnitWord | kCFStringTokenizerAttributeLatinTranscription),
        locale)
    else { return nil }
    var reading = ""
    var end = 0
    while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
      let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
      guard range.location == end else { return nil }
      let token = (expanded as NSString).substring(
        with: NSRange(location: range.location, length: range.length))
      let latin =
        CFStringTokenizerCopyCurrentTokenAttribute(
          tokenizer, CFOptionFlags(kCFStringTokenizerAttributeLatinTranscription)) as? String
      let converted = latin.flatMap { $0.applyingTransform(.latinToHiragana, reverse: false) }
      guard
        let kana = readingKana(token)
          ?? converted.flatMap(readingKana)
      else { return nil }
      reading += kana
      guard reading.utf16.count <= 512 else { return nil }
      end = range.location + range.length
    }
    return end == (expanded as NSString).length && !reading.isEmpty ? reading : nil
  }

  private static func readingKana(_ text: String) -> String? {
    var kana = ""
    for scalar in text.unicodeScalars {
      let value =
        (0x30A1...0x30F6).contains(scalar.value) || (0x30FD...0x30FE).contains(scalar.value)
        ? scalar.value - 0x60 : scalar.value
      guard
        (0x3041...0x3096).contains(value) || (0x309D...0x309F).contains(value)
          || value == 0x30FC,
        let character = Unicode.Scalar(value)
      else { return nil }
      kana.unicodeScalars.append(character)
    }
    return kana.isEmpty ? nil : kana
  }

  private static func readingNumerals(_ input: String) -> String? {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.numberStyle = .spellOut
    let expanded = NSMutableString(string: input)
    for match in input.matches(of: /[0-9]+/).reversed() {
      let digits = String(match.output)
      guard digits.count <= 9, digits.count == 1 || digits.first != "0",
        let value = Int64(digits), let words = formatter.string(from: NSNumber(value: value)),
        words.unicodeScalars.allSatisfy({ $0.properties.isIdeographic })
      else { return nil }
      expanded.replaceCharacters(in: NSRange(match.range, in: input), with: words)
    }
    return expanded as String
  }

  /// Returns nil when the platform should process the edit unchanged.
  /// Call only outside marked-text composition and when romaji input is enabled.
  public static func edit(
    text: String, range: NSRange, replacement: String,
    alphabet: KanaAlphabet = .hiragana
  ) -> Edit? {
    let original = text as NSString
    let incoming = replacement as NSString
    guard range.location >= 0, range.length >= 0, range.location <= original.length,
      range.length <= original.length - range.location
    else { return nil }
    if range.length > 0, incoming.length == 1,
      vowels.contains(asciiLowercase(incoming.character(at: 0))),
      let kana = replacements[replacement.lowercased()]
    {
      let converted = applyAlphabet(kana, source: replacement, alphabet: alphabet)
      return Edit(
        text: original.replacingCharacters(in: range, with: converted),
        allowsSystemChange: false, cursor: range.location + 1)
    }
    guard range.length == 0, incoming.length > 0 else { return nil }
    if range.location > 0, incoming.length == 1 {
      let previous = original.substring(with: NSRange(location: range.location - 1, length: 1))
      let last = asciiLowercase(original.character(at: range.location - 1))
      let next = asciiLowercase(incoming.character(at: 0))
      let kana: String?
      if !nasal.contains(next), next == last, consonants.contains(next) {
        kana = "っ"
      } else if next != 110, nasal.contains(last), !canFollowN.contains(next) {
        kana = "ん"
      } else {
        kana = nil
      }
      if let kana {
        return Edit(
          text: original.replacingCharacters(
            in: NSRange(location: range.location - 1, length: 1),
            with: applyAlphabet(kana, source: previous, alphabet: alphabet)),
          allowsSystemChange: true, cursor: nil)
      }
    }
    for length in stride(from: min(3, range.location), through: 0, by: -1) {
      let before = NSRange(location: range.location - length, length: length)
      let candidate = original.substring(with: before) + replacement
      guard let kana = replacements[candidate.lowercased()] else { continue }
      let converted = applyAlphabet(kana, source: candidate, alphabet: alphabet)
      // Place the caret after the inserted kana, including multi-character paste.
      let cursor = before.location + converted.utf16.count
      return Edit(
        text: original.replacingCharacters(in: before, with: converted),
        allowsSystemChange: false, cursor: cursor)
    }
    return nil
  }

  private static func asciiLowercase(_ character: UInt16) -> UInt16 {
    (65...90).contains(character) ? character + 32 : character
  }

  private static func applyAlphabet(_ kana: String, source: String, alphabet: KanaAlphabet)
    -> String
  {
    let uppercase = (NSCharacterSet.uppercaseLetters as NSCharacterSet)
      .characterIsMember((source as NSString).character(at: 0))
    return alphabet == .katakana || uppercase
      ? kana.applyingTransform(.hiraganaToKatakana, reverse: false) ?? kana : kana
  }
}
