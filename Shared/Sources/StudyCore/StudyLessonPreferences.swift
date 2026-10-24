import Foundation

/// Choices for new work; an existing durable session keeps its captured items and options.
public struct StudyLessonPreferences: Codable, Hashable, Sendable {
  public static let defaultOrder: [SubjectKind] = [.radical, .kanji, .vocabulary]
  public var order = Self.defaultOrder
  public var batchSize = 5
  public var prioritizeCurrentLevel = false
  public var apprenticeLimit = Int.max
  public var includeKanaVocabulary = true
  public var allowVocabularyExclusion = true
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case order, batchSize, prioritizeCurrentLevel, apprenticeLimit, includeKanaVocabulary,
      allowVocabularyExclusion
  }
  public init(from decoder: any Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    order = try c.decodeIfPresent([SubjectKind].self, forKey: .order) ?? order
    batchSize = try c.decodeIfPresent(Int.self, forKey: .batchSize) ?? batchSize
    prioritizeCurrentLevel =
      try c.decodeIfPresent(Bool.self, forKey: .prioritizeCurrentLevel) ?? prioritizeCurrentLevel
    apprenticeLimit = try c.decodeIfPresent(Int.self, forKey: .apprenticeLimit) ?? apprenticeLimit
    includeKanaVocabulary =
      try c.decodeIfPresent(Bool.self, forKey: .includeKanaVocabulary) ?? includeKanaVocabulary
    allowVocabularyExclusion =
      try c.decodeIfPresent(Bool.self, forKey: .allowVocabularyExclusion)
      ?? allowVocabularyExclusion
  }
  public var normalized: Self {
    var result = self
    var seen = Set<SubjectKind>()
    result.order = (order + Self.defaultOrder).filter { seen.insert($0).inserted }
    result.batchSize = min(10, max(1, batchSize))
    result.apprenticeLimit = max(0, apprenticeLimit)
    return result
  }
  public func effectiveBatchSize(waniKani: WaniKaniPreferences?, followWaniKani: Bool) -> Int {
    if followWaniKani, let size = waniKani?.lessonsBatchSize, size > 0 { return size }
    return normalized.batchSize
  }
  public typealias SortKey = (level: Int, kind: SubjectKind, subjectID: Int64)
  public func precedes(_ lhs: SortKey, _ rhs: SortKey) -> Bool {
    if lhs.level != rhs.level {
      return prioritizeCurrentLevel ? lhs.level > rhs.level : lhs.level < rhs.level
    }
    let ordered = normalized.order
    let left = ordered.firstIndex(of: lhs.kind) ?? ordered.count
    let right = ordered.firstIndex(of: rhs.kind) ?? ordered.count
    return left == right ? lhs.subjectID < rhs.subjectID : left < right
  }
  public mutating func applyChanges(from old: Self, to new: Self) {
    if old.order != new.order { order = new.order }
    if old.batchSize != new.batchSize { batchSize = new.batchSize }
    if old.prioritizeCurrentLevel != new.prioritizeCurrentLevel {
      prioritizeCurrentLevel = new.prioritizeCurrentLevel
    }
    if old.apprenticeLimit != new.apprenticeLimit { apprenticeLimit = new.apprenticeLimit }
    if old.includeKanaVocabulary != new.includeKanaVocabulary {
      includeKanaVocabulary = new.includeKanaVocabulary
    }
    if old.allowVocabularyExclusion != new.allowVocabularyExclusion {
      allowVocabularyExclusion = new.allowVocabularyExclusion
    }
    self = normalized
  }
}
