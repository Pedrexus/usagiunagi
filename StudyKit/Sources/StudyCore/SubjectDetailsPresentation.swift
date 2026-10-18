import Foundation

public enum SubjectAudioState: Sendable { case idle, loading, playing }

public struct SubjectDetailsPreferences: Sendable {
  public var primaryKanjiReadingsOnly = false
  public var useKatakanaForOnyomi = false
  public var showDeprecatedMnemonic = true
  public var blurTranslations = false
  public init() {}
}

/// Reading explanations can reveal the meaning before its question has been attempted.
public struct SubjectDetailVisibility: Sendable {
  public let questions: Set<StudyQuestionKind>
  public init(_ questions: Set<StudyQuestionKind>) { self.questions = questions }
  public var meaning: Bool { questions.contains(.meaning) }
  public var reading: Bool { questions.contains(.reading) }
  public var readingExplanation: Bool { meaning && reading }
  public var editableQuestions: Set<StudyQuestionKind> {
    var result: Set<StudyQuestionKind> = meaning ? [.meaning] : []
    if readingExplanation { result.insert(.reading) }
    return result
  }
}

extension CatalogSubject {
  public func displayedMeanings(preferences: SubjectDetailsPreferences) -> [Meaning] {
    meanings.filter {
      $0.role != .blacklist
        && ($0.role != .auxiliaryWhitelist
          || kind == .radical && preferences.showDeprecatedMnemonic)
    }.sorted { $0.role == .primary && $1.role != .primary }
  }
  public func displayedReadings(preferences: SubjectDetailsPreferences) -> [Reading] {
    let values =
      readings.isEmpty && kind == .vocabulary
      ? [Reading(japanese, isPrimary: true, kind: .unknown)] : readings
    return values.filter {
      kind != .kanji || !preferences.primaryKanjiReadingsOnly || $0.isPrimary
    }.sorted { $0.isPrimary && !$1.isPrimary }.map { reading in
      var reading = reading
      if preferences.useKatakanaForOnyomi && reading.kind == .onyomi {
        reading.text =
          reading.text.applyingTransform(.hiraganaToKatakana, reverse: false)
          ?? reading.text
      }
      return reading
    }
  }
}
