import Foundation
import Observation

/// Choices for new work; an existing durable session keeps its captured items and options.
public struct StudyLessonPreferences: Codable, Hashable, Sendable {
  public static let defaultOrder: [SubjectKind] = [.radical, .kanji, .vocabulary]
  public var order = Self.defaultOrder
  public var batchSize = 5
  public var prioritizeCurrentLevel = false
  public var apprenticeLimit = Int.max
  public var includeKanaVocabulary = true
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case order, batchSize, prioritizeCurrentLevel, apprenticeLimit, includeKanaVocabulary
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
  }
  public var normalized: Self {
    var result = self
    var seen = Set<SubjectKind>()
    result.order = (order + Self.defaultOrder).filter { seen.insert($0).inserted }
    result.batchSize = min(10, max(1, batchSize))
    result.apprenticeLimit = max(0, apprenticeLimit)
    return result
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
    self = normalized
  }
}

@MainActor public protocol StudyLessonPreferenceStore: AnyObject {
  var value: StudyLessonPreferences { get set }
}
@MainActor public final class DefaultsStudyLessonPreferences: StudyLessonPreferenceStore {
  private let defaults: UserDefaults
  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  public var value: StudyLessonPreferences {
    get {
      guard let data = defaults.data(forKey: "native.lessonPreferences"),
        let value = try? JSONDecoder().decode(StudyLessonPreferences.self, from: data)
      else { return .init() }
      return value.normalized
    }
    set {
      defaults.set(
        try? JSONEncoder().encode(newValue.normalized), forKey: "native.lessonPreferences")
    }
  }
}
@MainActor @Observable public final class StudyLessonSettings {
  public private(set) var value: StudyLessonPreferences
  private let store: any StudyLessonPreferenceStore
  public init(store: any StudyLessonPreferenceStore = DefaultsStudyLessonPreferences()) {
    self.store = store
    value = store.value.normalized
  }
  public func reload() { value = store.value.normalized }
  public func applyChanges(from old: StudyLessonPreferences, to new: StudyLessonPreferences) {
    var current = store.value
    current.applyChanges(from: old, to: new)
    store.value = current
    value = current
  }
}
