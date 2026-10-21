import Foundation

/// Shared values; each host preserves its existing durable settings format.
public struct ReviewPreferences: Codable, Equatable, Sendable {
  public enum Appearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
  public enum StageIndicator: String, Codable, CaseIterable, Sendable { case none, name, dots }
  public var appearance = Appearance.system
  public var stageIndicator = StageIndicator.name
  public var fontScale = 1.0
  public var policy = StudyReviewPolicy()
  public var sessionOptions = StudySessionOptions()
  public var revealAnswers = true
  public var revealFullAnswer = false
  public var exactMatch = false
  public var allowCorrections = true
  public var allowSkipping = false
  public var autoplayAudio = false
  public var interruptBackgroundAudio = false
  public var correctAnswerFeedback = true
  public var completedItemFeedback = true
  public var srsMilestoneFeedback = true
  public init() {}

  private enum CodingKeys: String, CodingKey {
    case policy, appearance, stageIndicator, fontScale, revealAnswers, revealFullAnswer, exactMatch
    case allowCorrections, allowSkipping, autoplayAudio, interruptBackgroundAudio
    case correctAnswerFeedback, completedItemFeedback, srsMilestoneFeedback, sessionOptions
  }

  /// New preferences must not reset an existing window's saved review options.
  public init(from decoder: any Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    policy =
      try values.decodeIfPresent(StudyReviewPolicy.self, forKey: .policy)?.normalized ?? policy
    sessionOptions =
      try values.decodeIfPresent(StudySessionOptions.self, forKey: .sessionOptions)
      ?? sessionOptions
    appearance = try values.decodeIfPresent(Appearance.self, forKey: .appearance) ?? appearance
    stageIndicator =
      try values.decodeIfPresent(StageIndicator.self, forKey: .stageIndicator) ?? stageIndicator
    fontScale = try values.decodeIfPresent(Double.self, forKey: .fontScale) ?? fontScale
    for (key, path) in Self.booleanFields {
      if let value = try values.decodeIfPresent(Bool.self, forKey: key) {
        self[keyPath: path] = value
      }
    }
  }

  private static var booleanFields: [(CodingKeys, WritableKeyPath<Self, Bool>)] {
    [
      (.revealAnswers, \.revealAnswers), (.revealFullAnswer, \.revealFullAnswer),
      (.exactMatch, \.exactMatch), (.allowCorrections, \.allowCorrections),
      (.allowSkipping, \.allowSkipping), (.autoplayAudio, \.autoplayAudio),
      (.interruptBackgroundAudio, \.interruptBackgroundAudio),
      (.correctAnswerFeedback, \.correctAnswerFeedback),
      (.completedItemFeedback, \.completedItemFeedback),
      (.srsMilestoneFeedback, \.srsMilestoneFeedback),
    ]
  }

  /// A settings window only replaces fields it changed, preserving another window's edits.
  public mutating func applyChanges(from old: Self, to new: Self) {
    if old.policy.order != new.policy.order { policy.order = new.policy.order }
    if old.policy.limitEnabled != new.policy.limitEnabled {
      policy.limitEnabled = new.policy.limitEnabled
    }
    if old.policy.limit != new.policy.limit { policy.limit = new.policy.normalized.limit }
    if old.policy.leechThreshold != new.policy.leechThreshold {
      policy.leechThreshold = new.policy.normalized.leechThreshold
    }
    if old.sessionOptions.ankiMode != new.sessionOptions.ankiMode {
      sessionOptions.ankiMode = new.sessionOptions.ankiMode
    }
    let booleans: [WritableKeyPath<StudySessionOptions, Bool>] = [
      \.groupMeaningReading, \.combinedAnki, \.meaningFirst, \.skipKanjiReadings, \.minimizePenalty,
    ]
    for key in booleans where old.sessionOptions[keyPath: key] != new.sessionOptions[keyPath: key] {
      sessionOptions[keyPath: key] = new.sessionOptions[keyPath: key]
    }
    for key in [\StudySessionOptions.batchSize, \.incorrectAnswerDelay]
    where old.sessionOptions[keyPath: key] != new.sessionOptions[keyPath: key] {
      sessionOptions[keyPath: key] = new.sessionOptions[keyPath: key]
    }
    if sessionOptions.ankiMode != .both { sessionOptions.combinedAnki = false }
    if old.appearance != new.appearance { appearance = new.appearance }
    if old.stageIndicator != new.stageIndicator { stageIndicator = new.stageIndicator }
    if old.fontScale != new.fontScale { fontScale = new.fontScale }
    for (_, key) in Self.booleanFields {
      if old[keyPath: key] != new[keyPath: key] { self[keyPath: key] = new[keyPath: key] }
    }
  }

  public func reviewPolicy(waniKani: WaniKaniPreferences?, followWaniKani: Bool)
    -> StudyReviewPolicy
  {
    var result = policy
    if followWaniKani, let order = waniKani?.reviewOrder { result.order = order }
    return result
  }

  public func autoplay(
    in context: WaniKaniPreferences.Context, waniKani: WaniKaniPreferences?, followWaniKani: Bool
  )
    -> Bool
  {
    if followWaniKani, let waniKani { return waniKani.autoplay(in: context) }
    return autoplayAudio
  }
}
