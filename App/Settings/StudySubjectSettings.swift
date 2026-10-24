import Foundation
import Observation
import StudyCore

@MainActor public protocol StudySubjectPreferenceStore: AnyObject {
  var value: SubjectDetailsPreferences { get set }
}

@MainActor public final class DefaultsStudySubjectPreferences: StudySubjectPreferenceStore {
  private let defaults: UserDefaults
  private let changed: (@MainActor (SubjectDetailsPreferences, SubjectDetailsPreferences) -> Void)?
  public init(
    defaults: UserDefaults = .standard,
    changed: (@MainActor (SubjectDetailsPreferences, SubjectDetailsPreferences) -> Void)? = nil
  ) {
    self.defaults = defaults
    self.changed = changed
  }
  public var value: SubjectDetailsPreferences {
    get {
      defaults.data(forKey: "native.subjectPreferences").flatMap {
        try? JSONDecoder().decode(SubjectDetailsPreferences.self, from: $0)
      } ?? .init()
    }
    set {
      let old = value
      defaults.set(try? JSONEncoder().encode(newValue), forKey: "native.subjectPreferences")
      if old != newValue { changed?(old, newValue) }
    }
  }
}

@MainActor @Observable public final class StudySubjectSettings {
  public private(set) var value: SubjectDetailsPreferences
  private let store: any StudySubjectPreferenceStore
  public init(store: any StudySubjectPreferenceStore = DefaultsStudySubjectPreferences()) {
    self.store = store
    value = store.value
  }
  public func reload() { value = store.value }
  public func applyChanges(from old: SubjectDetailsPreferences, to new: SubjectDetailsPreferences) {
    var current = store.value
    current.applyChanges(from: old, to: new)
    store.value = current
    value = current
  }
}
