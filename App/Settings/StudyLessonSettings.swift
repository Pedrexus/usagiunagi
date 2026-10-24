import Foundation
import Observation
import StudyCore

@MainActor public protocol StudyLessonPreferenceStore: AnyObject {
  var value: StudyLessonPreferences { get set }
}
@MainActor public final class DefaultsStudyLessonPreferences: StudyLessonPreferenceStore {
  private let defaults: UserDefaults
  private let changed: (@MainActor (StudyLessonPreferences, StudyLessonPreferences) -> Void)?
  public init(
    defaults: UserDefaults = .standard,
    changed: (@MainActor (StudyLessonPreferences, StudyLessonPreferences) -> Void)? = nil
  ) {
    self.defaults = defaults
    self.changed = changed
  }
  public var value: StudyLessonPreferences {
    get {
      guard let data = defaults.data(forKey: "native.lessonPreferences"),
        let value = try? JSONDecoder().decode(StudyLessonPreferences.self, from: data)
      else { return .init() }
      return value.normalized
    }
    set {
      let old = value
      let current = newValue.normalized
      defaults.set(
        try? JSONEncoder().encode(current), forKey: "native.lessonPreferences")
      if old != current { changed?(old, current) }
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
