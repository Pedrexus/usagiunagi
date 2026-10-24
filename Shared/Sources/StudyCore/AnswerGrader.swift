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

public enum StudyQuestionKind: String, Codable, Sendable {
  case reading, meaning
}

/// Complete accepted-answer data, independent of network/database representations.
/// Primary/alternate readings stay separate because kanji alternates prompt another attempt.
public struct GradingSubject: Codable, Sendable {
  public let japanese: String
  public let kind: SubjectKind
  public let meanings: [String]
  public let blacklistedMeanings: [String]
  public let primaryReadings: [String]
  public let alternateReadings: [String]
  public let componentSubjectIds: [Int64]

  public init(
    japanese: String, kind: SubjectKind, meanings: [String],
    blacklistedMeanings: [String] = [], primaryReadings: [String] = [],
    alternateReadings: [String] = [], componentSubjectIds: [Int64] = []
  ) {
    self.japanese = japanese
    self.kind = kind
    self.meanings = meanings
    self.blacklistedMeanings = blacklistedMeanings
    self.primaryReadings = primaryReadings
    self.alternateReadings = alternateReadings
    self.componentSubjectIds = componentSubjectIds
  }
}

public enum AnswerGrade: Equatable, Sendable {
  case precise
  case imprecise
  case otherKanjiReading
  case mismatchingOkurigana([NSRange])
  case containsInvalidCharacters([NSRange])
  case isReadingButWantMeaning
  case incorrect
}

public enum AnswerGrader {
  static let kHiraganaCharacterSet = CharacterSet(
    charactersIn:
      Unicode
      .Scalar(UInt32(0x3040))!..<Unicode.Scalar(UInt32(0x309D))!)
  static let kAllKanaCharacterSet = CharacterSet(
    charactersIn:
      Unicode
      .Scalar(UInt32(0x3040))!..<Unicode.Scalar(UInt32(0x3100))!)
  static let kJapaneseCharacterSet =
    kAllKanaCharacterSet
    .union(
      CharacterSet(charactersIn: Unicode.Scalar(UInt32(0x3400))!..<Unicode.Scalar(UInt32(0x4DC0))!)
    )
    .union(
      CharacterSet(charactersIn: Unicode.Scalar(UInt32(0x4E00))!..<Unicode.Scalar(UInt32(0xA000))!)
    )
    .union(
      CharacterSet(charactersIn: Unicode.Scalar(UInt32(0xF900))!..<Unicode.Scalar(UInt32(0xFB00))!)
    )
    .union(
      CharacterSet(charactersIn: Unicode.Scalar(UInt32(0xFF66))!..<Unicode.Scalar(UInt32(0xFFA0))!))

  private static func findNonKanaRanges(_ s: String) -> [NSRange] {
    findCharacterRanges(in: s, from: kAllKanaCharacterSet.inverted)
  }

  private static func findJapaneseRanges(_ s: String) -> [NSRange] {
    findCharacterRanges(in: s, from: kJapaneseCharacterSet)
  }

  private static func findCharacterRanges(in s: String, from: CharacterSet) -> [NSRange] {
    var ranges = [NSRange]()
    var start: Int?
    var offset = 0
    for scalar in s.unicodeScalars {
      if from.contains(scalar) {
        if start == nil { start = offset }
      } else if let begin = start {
        ranges.append(NSRange(location: begin, length: offset - begin))
        start = nil
      }
      // Native attributed strings use UTF-16 offsets, not scalar or grapheme indices.
      offset += scalar.utf16.count
    }
    if let start { ranges.append(NSRange(location: start, length: offset - start)) }
    return ranges
  }

  private static func distanceTolerance(_ answer: String) -> Int {
    if answer.count <= 3 {
      return 0
    }
    if answer.count <= 5 {
      return 1
    }
    if answer.count <= 7 {
      return 2
    }
    return Int(2 + 1 * floor(Double(answer.count) / 7))
  }

  private static func mismatchingOkurigana(answer: String, japanese: String) -> [NSRange] {
    if answer.unicodeScalars.count < japanese.unicodeScalars.count {
      return []
    }

    var ret = [NSRange]()

    if let prefixRange = mismatchingOkurigana(
      answer: answer.unicodeScalars,
      japanese: japanese.unicodeScalars)
    {
      ret.append(prefixRange)
    }

    if let suffixRange = mismatchingOkurigana(
      answer: answer.unicodeScalars.reversed(),
      japanese: japanese.unicodeScalars.reversed())
    {
      // Reverse the range again to match the original string.
      ret.append(
        NSMakeRange(
          answer.utf16.count - suffixRange.lowerBound - suffixRange.length,
          suffixRange.length))
    }

    return ret
  }

  private static func mismatchingOkurigana<T: Collection<Unicode.Scalar>>(
    answer: T,
    japanese: T
  ) -> NSRange? {
    var mismatchingRangeBegin: Int?
    var mismatchingRangeEnd: Int?

    for (index, (japaneseChar, answerChar)) in zip(japanese, answer).enumerated() {
      if !kHiraganaCharacterSet.contains(japaneseChar) {
        break
      }
      if japaneseChar != answerChar {
        mismatchingRangeBegin = min(index, mismatchingRangeBegin ?? index)
        mismatchingRangeEnd = max(index, mismatchingRangeEnd ?? index)
      }
    }

    if let begin = mismatchingRangeBegin, let end = mismatchingRangeEnd {
      return NSMakeRange(begin, end - begin + 1)
    }
    return nil
  }

  public static func convertKatakanaToHiragana(_ text: String) -> String {
    // Transform each segment independently so the long-vowel mark remains unchanged.
    text.components(separatedBy: "ー")
      .map { $0.applyingTransform(.hiraganaToKatakana, reverse: true) ?? $0 }
      .joined(separator: "ー")
  }

  public static func normalizedString(
    _ text: String, taskType: StudyQuestionKind,
    alphabet: KanaAlphabet = KanaAlphabet.hiragana
  ) -> String {
    var s =
      text.trimmingCharacters(in: CharacterSet.whitespaces)
      .lowercased()
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: ".", with: "")
      .replacingOccurrences(of: "'", with: "")
      .replacingOccurrences(of: "/", with: "")
    if taskType == .reading {
      s = s.replacingOccurrences(of: "n", with: alphabet == KanaAlphabet.hiragana ? "ん" : "ン")

      // Gboard Godan layout uses "ｎ" or Unicode code point U+FF4E.
      s = s.replacingOccurrences(of: "ｎ", with: alphabet == KanaAlphabet.hiragana ? "ん" : "ン")

      s = s.replacingOccurrences(of: " ", with: "")
    }
    return s
  }

  /// The caller supplies the normalized answer so feedback highlights refer to displayed text.
  /// Voice and typed input must use the same normalization and grading path.
  public static func checkNormalizedAnswer(
    _ answer: String,
    subject: GradingSubject,
    synonyms: [String] = [],
    taskType: StudyQuestionKind,
    subjectLookup: (Int64) -> GradingSubject? = { _ in nil }
  ) -> AnswerGrade {
    switch taskType {
    case .reading:
      let hiraganaText = convertKatakanaToHiragana(answer)

      let nonKanaRanges = findNonKanaRanges(answer)
      if !nonKanaRanges.isEmpty {
        return .containsInvalidCharacters(nonKanaRanges)
      }

      for reading in subject.primaryReadings
      where convertKatakanaToHiragana(reading) == hiraganaText {
        return .precise
      }
      for reading in subject.alternateReadings
      where convertKatakanaToHiragana(reading) == hiraganaText {
        return subject.kind == .kanji ? .otherKanjiReading : .precise
      }
      if subject.kind == .vocabulary, subject.japanese.count == 1,
        subject.componentSubjectIds.count == 1
      {
        // If the vocabulary is made up of only one Kanji, check whether the user wrote the Kanji
        // reading instead of the vocabulary reading.
        if let kanji = subjectLookup(subject.componentSubjectIds[0]), kanji.kind == .kanji {
          let result = checkNormalizedAnswer(
            answer, subject: kanji, taskType: taskType,
            subjectLookup: subjectLookup)
          if result == .precise {
            return .otherKanjiReading
          }
        }
      }
      if subject.kind == .vocabulary {
        let ranges = mismatchingOkurigana(
          answer: answer,
          japanese: subject.japanese)
        if !ranges.isEmpty {
          return .mismatchingOkurigana(ranges)
        }
      }

    case .meaning:
      let japaneseRanges = findJapaneseRanges(answer)
      if !japaneseRanges.isEmpty {
        return .containsInvalidCharacters(japaneseRanges)
      }

      // Check blacklisted meanings first.  If the answer matches one exactly, it's incorrect.
      for meaning in subject.blacklistedMeanings {
        if normalizedString(meaning, taskType: taskType) == answer { return .incorrect }
      }

      let meaningTexts = synonyms + subject.meanings

      // Check if the answer matches a meaning exactly.
      for meaning in meaningTexts {
        if normalizedString(meaning, taskType: taskType) == answer {
          return .precise
        }
      }

      // Check if the answer *almost* matches a meaning.
      for meaning in meaningTexts {
        let meaningText = normalizedString(meaning, taskType: taskType)
        let distance = AnswerDistance.between(meaningText, answer)
        let tolerance = distanceTolerance(meaningText)
        if distance <= tolerance {
          return .imprecise
        }
      }

      // Check if the answer would match one of the readings if converted to hiragana.
      let kanaText = KanaConverter.convert(answer).text
      switch checkNormalizedAnswer(
        kanaText, subject: subject, synonyms: synonyms,
        taskType: .reading, subjectLookup: subjectLookup)
      {
      case .precise, .imprecise:
        return .isReadingButWantMeaning
      case .otherKanjiReading:
        return .otherKanjiReading
      default:
        break
      }
    }

    return .incorrect
  }
}
