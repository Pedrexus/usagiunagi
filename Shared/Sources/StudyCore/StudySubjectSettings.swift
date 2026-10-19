import Foundation
import Observation

@MainActor public protocol StudySubjectPreferenceStore: AnyObject {
  var value: SubjectDetailsPreferences { get set }
}

@MainActor public final class DefaultsStudySubjectPreferences: StudySubjectPreferenceStore {
  private let defaults: UserDefaults
  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  public var value: SubjectDetailsPreferences {
    get {
      defaults.data(forKey: "native.subjectPreferences").flatMap {
        try? JSONDecoder().decode(SubjectDetailsPreferences.self, from: $0)
      } ?? .init()
    }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "native.subjectPreferences") }
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
