import Foundation
import StudyCore

/// Portable app choices use the same scope across WaniKani accounts, as their local owners do.
nonisolated public enum StudyPortableSetting: String, CaseIterable, Sendable {
  case waniKaniAudio = "native.waniKani.audio"
  case waniKaniReviewOrder = "native.waniKani.reviewOrder"
  case waniKaniSrsFeedback = "native.waniKani.srsFeedback"
  case waniKaniLessonBatch = "native.waniKani.lessonBatch"
  case showMinutes = "native.showMinutesForNextLevelUpReview"
  case showCatalogAnswers = "catalog.showAnswers"
  case avatarEmail = "native.gravatarCustomEmail"

  var defaultValue: String {
    switch self {
    case .showCatalogAnswers: "true"
    case .avatarEmail: ""
    default: "false"
    }
  }
  var affectsLearning: Bool { self == .waniKaniReviewOrder || self == .waniKaniLessonBatch }
  func validated(_ value: String) -> String? {
    if self == .avatarEmail {
      return value.utf8.count <= 2048 && !value.contains("\0") ? value : nil
    }
    return Bool(value).map { String($0) }
  }
}

/// A transient projection; no new Codable type is added to historical study receipts.
@MainActor struct StudyPortablePreferences {
  var review = ReviewPreferences()
  var lessons = StudyLessonPreferences()
  var subjects = SubjectDetailsPreferences()
  var scalars = Dictionary(
    uniqueKeysWithValues: StudyPortableSetting.allCases.map { ($0, $0.defaultValue) })
  var fonts: Set<String> = []
  var voices: Set<Int64> = []

  subscript(_ setting: StudyPortableSetting) -> String {
    get { scalars[setting] ?? setting.defaultValue }
    set { scalars[setting] = newValue }
  }

  static func read(_ defaults: UserDefaults) throws -> Self {
    var value = Self()
    func read<Value: Decodable>(_ key: String, fallback: Value) throws -> Value {
      try defaults.data(forKey: key).map { try JSONDecoder().decode(Value.self, from: $0) }
        ?? fallback
    }
    value.review = try read("native.reviewPreferences", fallback: value.review)
    value.lessons = try read("native.lessonPreferences", fallback: value.lessons)
    value.subjects = try read("native.subjectPreferences", fallback: value.subjects)
    for key in StudyPortableSetting.allCases {
      if key == .avatarEmail {
        value.scalars[key] = defaults.string(forKey: key.rawValue) ?? key.defaultValue
      } else if defaults.object(forKey: key.rawValue) != nil {
        value.scalars[key] = String(defaults.bool(forKey: key.rawValue))
      }
    }
    value.fonts = Set(defaults.stringArray(forKey: "native.selectedFonts") ?? [])
    value.voices = Set(
      (defaults.array(forKey: "native.offlineAudioVoices") as? [NSNumber] ?? []).map(\.int64Value))
    return value
  }

  func saveChanges(from old: Self, to defaults: UserDefaults) throws -> Bool {
    // Prepare all encodings before changing any local group.
    let reviewData = review != old.review ? try JSONEncoder().encode(review) : nil
    let lessonData = lessons != old.lessons ? try JSONEncoder().encode(lessons) : nil
    let subjectData = subjects != old.subjects ? try JSONEncoder().encode(subjects) : nil
    if let reviewData { defaults.set(reviewData, forKey: "native.reviewPreferences") }
    if let lessonData { defaults.set(lessonData, forKey: "native.lessonPreferences") }
    if let subjectData { defaults.set(subjectData, forKey: "native.subjectPreferences") }
    for key in StudyPortableSetting.allCases where scalars[key] != old.scalars[key] {
      if key == .avatarEmail {
        defaults.set(scalars[key], forKey: key.rawValue)
      } else if let value = scalars[key].flatMap(Bool.init) {
        defaults.set(value, forKey: key.rawValue)
      }
    }
    if fonts != old.fonts { defaults.set(fonts.sorted(), forKey: "native.selectedFonts") }
    if voices != old.voices {
      defaults.set(voices.sorted().map(NSNumber.init(value:)), forKey: "native.offlineAudioVoices")
    }
    return reviewData != nil || lessonData != nil || subjectData != nil || scalars != old.scalars
      || fonts != old.fonts || voices != old.voices
  }
}

/// One typed allowlist encodes individual logical choices, rather than whole preference groups.
@MainActor struct StudyPortableField {
  let name: String
  let affectsLearning: Bool
  let value: (StudyPortablePreferences) -> String
  let apply: (String, inout StudyPortablePreferences) -> Bool
  var pendingKey: String { "native.privateCloudPending.\(name)" }

  init<Value>(
    _ name: String, _ path: WritableKeyPath<StudyPortablePreferences, Value>,
    learning: Bool = false, parse: @escaping (String) -> Value?,
    string: @escaping (Value) -> String
  ) {
    self.name = name
    affectsLearning = learning
    value = { string($0[keyPath: path]) }
    apply = { raw, preferences in
      guard let value = parse(raw) else { return false }
      preferences[keyPath: path] = value
      return true
    }
  }

  private static func boolean(
    _ name: String, _ path: WritableKeyPath<StudyPortablePreferences, Bool>, learning: Bool = false
  ) -> Self { .init(name, path, learning: learning, parse: Bool.init, string: { String($0) }) }
  private static func integer(
    _ name: String, _ path: WritableKeyPath<StudyPortablePreferences, Int>,
    learning: Bool = true, valid: @escaping (Int) -> Bool
  ) -> Self {
    .init(
      name, path, learning: learning,
      parse: { Int($0).flatMap { valid($0) ? $0 : nil } }, string: { String($0) })
  }
  private static func enumeration<Value: RawRepresentable & Sendable>(
    _ name: String, _ path: WritableKeyPath<StudyPortablePreferences, Value>, learning: Bool = false
  ) -> Self where Value.RawValue: LosslessStringConvertible & Sendable {
    .init(
      name, path, learning: learning,
      parse: { Value.RawValue($0).flatMap(Value.init(rawValue:)) }, string: { String($0.rawValue) })
  }

  static let review: [Self] =
    [
      .enumeration("appearance", \.review.appearance),
      .enumeration("stageIndicator", \.review.stageIndicator),
      .init(
        "fontScale", \.review.fontScale,
        parse: {
          Double($0).flatMap {
            $0.isFinite && (1...2.5).contains($0) && ($0 * 4).rounded() == $0 * 4 ? $0 : nil
          }
        }, string: { String($0) }),
      .enumeration("reviewOrder", \.review.policy.order, learning: true),
      .boolean("reviewLimitEnabled", \.review.policy.limitEnabled, learning: true),
      .integer("reviewLimit", \.review.policy.limit, valid: { $0 > 0 }),
      .init(
        "leechThreshold", \.review.policy.leechThreshold, learning: true,
        parse: { Double($0).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }, string: { String($0) }),
      // Answer mode and its combined variant are one choice, so independent imports cannot split them.
      .init(
        "answerMode", \.answerMode, learning: true,
        parse: {
          ["off", "meaning", "reading", "both", "both_combined"].contains($0) ? $0 : nil
        }, string: { $0 }),
      .integer(
        "sessionBatchSize", \.review.sessionOptions.batchSize, valid: { (1...10).contains($0) }),
      .integer(
        "incorrectAnswerDelay", \.review.sessionOptions.incorrectAnswerDelay,
        valid: { (0...10).contains($0) }),
    ]
    + [
      ("groupMeaningReading", \StudyPortablePreferences.review.sessionOptions.groupMeaningReading),
      ("meaningFirst", \.review.sessionOptions.meaningFirst),
      ("skipKanjiReadings", \.review.sessionOptions.skipKanjiReadings),
      ("minimizePenalty", \.review.sessionOptions.minimizePenalty),
      ("revealAnswers", \.review.revealAnswers), ("revealFullAnswer", \.review.revealFullAnswer),
      ("exactMatch", \.review.exactMatch), ("allowCorrections", \.review.allowCorrections),
      ("allowSkipping", \.review.allowSkipping), ("autoplayAudio", \.review.autoplayAudio),
      ("correctAnswerFeedback", \.review.correctAnswerFeedback),
      ("completedItemFeedback", \.review.completedItemFeedback),
      ("srsMilestoneFeedback", \.review.srsMilestoneFeedback),
    ].map { .boolean($0.0, $0.1, learning: true) }

  static let lessons: [Self] = [
    .init(
      "lessonOrder", \.lessons.order, learning: true,
      parse: {
        let pieces = $0.split(separator: ",", omittingEmptySubsequences: false)
        let values = pieces.compactMap { SubjectKind(rawValue: String($0)) }
        return pieces.count == 3 && values.count == 3
          && Set(values) == Set(StudyLessonPreferences.defaultOrder) ? values : nil
      }, string: { $0.map(\.rawValue).joined(separator: ",") }),
    .integer("lessonBatchSize", \.lessons.batchSize, valid: { (1...10).contains($0) }),
    .integer("apprenticeLimit", \.lessons.apprenticeLimit, valid: { $0 >= 0 }),
    .boolean("prioritizeCurrentLevel", \.lessons.prioritizeCurrentLevel, learning: true),
    .boolean("includeKanaVocabulary", \.lessons.includeKanaVocabulary, learning: true),
    .boolean("allowVocabularyExclusion", \.lessons.allowVocabularyExclusion, learning: true),
  ]

  static let subjects: [Self] = [
    ("primaryKanjiReadingsOnly", \StudyPortablePreferences.subjects.primaryKanjiReadingsOnly),
    ("useKatakanaForOnyomi", \.subjects.useKatakanaForOnyomi),
    ("showDeprecatedMnemonic", \.subjects.showDeprecatedMnemonic),
    ("blurTranslations", \.subjects.blurTranslations),
    ("showStatistics", \.subjects.showStatistics),
    ("showArtwork", \.subjects.showArtwork),
    ("showPreviousLevelGraph", \.subjects.showPreviousLevelGraph),
    ("showSimilarKanjiAboveCurrentLevel", \.subjects.showSimilarKanjiAboveCurrentLevel),
  ].map { .boolean($0.0, $0.1) }

  static let scalars = StudyPortableSetting.allCases.map { key in
    Self(
      key.rawValue, \StudyPortablePreferences.[key], learning: key.affectsLearning,
      parse: key.validated, string: { $0 })
  }
  static let fonts = Self(
    "selectedFonts", \.fonts,
    parse: {
      let files =
        $0.isEmpty
        ? [] : $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      guard files.count <= 128, Set(files).count == files.count,
        files.allSatisfy({
          !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 128
            && !$0.contains(where: { "/\\:\0".contains($0) || $0.isNewline })
        })
      else { return nil }
      return Set(files)
    }, string: { $0.sorted().joined(separator: ",") })
  static let voices = Self(
    "offlineAudioVoices", \.voices,
    parse: {
      let pieces =
        $0.isEmpty
        ? [] : $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      let ids = pieces.compactMap(Int64.init)
      return ids.count == pieces.count && ids.count <= 128 && ids.allSatisfy({ $0 > 0 })
        && Set(ids).count == ids.count ? Set(ids) : nil
    }, string: { $0.sorted().map(String.init).joined(separator: ",") })
  static let all = review + lessons + subjects + scalars + [fonts, voices]
}

extension StudyPortablePreferences {
  fileprivate var answerMode: String {
    get {
      review.sessionOptions.ankiMode == .both && review.sessionOptions.combinedAnki
        ? "both_combined" : review.sessionOptions.ankiMode.rawValue
    }
    set {
      review.sessionOptions.ankiMode =
        newValue == "both_combined"
        ? .both : StudySessionOptions.AnkiMode(rawValue: newValue) ?? .off
      review.sessionOptions.combinedAnki = newValue == "both_combined"
    }
  }
}
