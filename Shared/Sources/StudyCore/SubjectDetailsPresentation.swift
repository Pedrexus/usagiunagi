import Foundation

public enum SubjectAudioState: Sendable { case idle, loading, playing }

/// Original app defaults; presentation choices never change the grader's accepted answers.
public struct SubjectDetailsPreferences: Codable, Hashable, Sendable {
  public var primaryKanjiReadingsOnly = true
  public var useKatakanaForOnyomi = false
  public var showDeprecatedMnemonic = true
  public var blurTranslations = true
  public var showStatistics = true
  public var showArtwork = false
  public var showPreviousLevelGraph = true
  public var showSimilarKanjiAboveCurrentLevel = false
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case primaryKanjiReadingsOnly, useKatakanaForOnyomi, showDeprecatedMnemonic, blurTranslations,
      showStatistics, showArtwork, showPreviousLevelGraph, showSimilarKanjiAboveCurrentLevel
  }
  private static var fields: [(CodingKeys, WritableKeyPath<Self, Bool>)] {
    [
      (.primaryKanjiReadingsOnly, \.primaryKanjiReadingsOnly),
      (.useKatakanaForOnyomi, \.useKatakanaForOnyomi),
      (.showDeprecatedMnemonic, \.showDeprecatedMnemonic), (.blurTranslations, \.blurTranslations),
      (.showStatistics, \.showStatistics), (.showArtwork, \.showArtwork),
      (.showPreviousLevelGraph, \.showPreviousLevelGraph),
      (.showSimilarKanjiAboveCurrentLevel, \.showSimilarKanjiAboveCurrentLevel),
    ]
  }
  public init(from decoder: any Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    for (key, path) in Self.fields {
      if let value = try values.decodeIfPresent(Bool.self, forKey: key) {
        self[keyPath: path] = value
      }
    }
  }
  public mutating func applyChanges(from old: Self, to new: Self) {
    for (_, path) in Self.fields where old[keyPath: path] != new[keyPath: path] {
      self[keyPath: path] = new[keyPath: path]
    }
  }
  public func visibleSimilar(_ subjects: [CatalogSubject], currentLevel: Int) -> [CatalogSubject] {
    subjects.filter { showSimilarKanjiAboveCurrentLevel || $0.level <= currentLevel }
  }
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
