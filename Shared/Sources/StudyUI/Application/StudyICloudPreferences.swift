import Foundation
import Observation
import StudyCore
import SwiftData
import SwiftUI

/// Separate from StudySchemaV1: this schema contains no account, progress or upload data.
nonisolated enum PrivatePreferencesV1: VersionedSchema {
  static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
  static var models: [any PersistentModel.Type] { [Change.self] }

  @Model final class Change {
    var id: UUID = UUID()
    var field: String = ""
    var value: String = ""
    var revision: Int64 = 0
    var formatVersion: Int = 1

    init(field: String, value: String, revision: Int64, id: UUID = UUID()) {
      self.field = field
      self.value = value
      self.revision = revision
      self.id = id
    }

    struct Value: Equatable, Sendable {
      let id: UUID
      let field: String
      let value: String
      let revision: Int64
      let formatVersion: Int
    }

    var snapshot: Value {
      .init(id: id, field: field, value: value, revision: revision, formatVersion: formatVersion)
    }
  }
}

/// CloudKit transports portable app choices; it never receives WaniKani state or credentials.
@MainActor @Observable public final class StudyICloudPreferences {
  public private(set) var iCloudEnabled = false
  public private(set) var notice: String?
  public private(set) var hasDeferredLearningChanges = false
  public private(set) var revision = UUID()
  @ObservationIgnored private(set) var container: ModelContainer?
  private let defaults: UserDefaults
  private var studyingScenes: Set<UUID> = []
  private typealias Field = StudyPortableField

  public init(directory: URL, iCloudContainerIdentifier: String? = nil, defaults: UserDefaults) {
    self.defaults = defaults
    do {
      let schema = Schema(versionedSchema: PrivatePreferencesV1.self)
      var iCloud: ModelConfiguration.CloudKitDatabase = .none
      // Let SwiftData inspect signing; never construct CKContainer in an unentitled build.
      if let iCloudContainerIdentifier,
        ModelConfiguration(cloudKitDatabase: .automatic).cloudKitContainerIdentifier
          == iCloudContainerIdentifier
      {
        iCloud = .private(iCloudContainerIdentifier)
        iCloudEnabled = true
      }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let configuration = ModelConfiguration(
        "PrivatePreferences", schema: schema, url: directory.appending(path: "preferences.store"),
        cloudKitDatabase: iCloud)
      let container = try ModelContainer(for: schema, configurations: configuration)
      container.mainContext.autosaveEnabled = false
      self.container = container
      savePending()
      reconcile(try values())
    } catch {
      iCloudEnabled = false
      notice =
        "iCloud app settings are unavailable. Your settings on this device have been kept."
    }
  }

  func values() throws -> [PrivatePreferencesV1.Change.Value] {
    try container?.mainContext.fetch(FetchDescriptor<PrivatePreferencesV1.Change>()).map(\.snapshot)
      ?? []
  }

  /// Only explicit edits publish. Opening a new device must not publish its defaults over iCloud.
  func recordChanges(from old: ReviewPreferences, to new: ReviewPreferences) {
    recordChanges(from: .init(review: old), to: .init(review: new), fields: Field.review)
  }
  public func recordLessonChanges(from old: StudyLessonPreferences, to new: StudyLessonPreferences)
  {
    recordChanges(from: .init(lessons: old), to: .init(lessons: new), fields: Field.lessons)
  }
  public func recordSubjectChanges(
    from old: SubjectDetailsPreferences, to new: SubjectDetailsPreferences
  ) {
    recordChanges(from: .init(subjects: old), to: .init(subjects: new), fields: Field.subjects)
  }
  public func recordFontChanges(from old: Set<String>, to new: Set<String>) {
    recordChanges(from: .init(fonts: old), to: .init(fonts: new), fields: [Field.fonts])
  }
  public func recordAudioChanges(from old: StudyAudioOptions, to new: StudyAudioOptions) {
    recordChanges(
      from: .init(voices: old.voiceIDs), to: .init(voices: new.voiceIDs), fields: [Field.voices])
  }
  fileprivate func recordScalarChange(_ key: StudyPortableSetting) {
    do {
      let current = try StudyPortablePreferences.read(defaults)
      guard let field = Field.scalars.first(where: { $0.name == key.rawValue }) else { return }
      defaults.set(field.value(current), forKey: field.pendingKey)
      savePending()
    } catch {
      notice = "Saved app settings could not be read. Your local settings have been kept."
    }
  }

  private func recordChanges(
    from old: StudyPortablePreferences, to new: StudyPortablePreferences, fields: [Field]
  ) {
    for field in fields where field.value(old) != field.value(new) {
      defaults.set(field.value(new), forKey: field.pendingKey)
    }
    savePending()
  }

  private func savePending() {
    let pending = Field.all.compactMap { field in
      defaults.string(forKey: field.pendingKey).map { (field, $0) }
    }
    guard !pending.isEmpty, let context = container?.mainContext else { return }
    do {
      let values = try values()
      for (field, value) in pending {
        let previous = values.filter { $0.field == field.name }
        let (revision, overflow) = (previous.map(\.revision).max() ?? 0).addingReportingOverflow(1)
        var validated = StudyPortablePreferences()
        guard previous.allSatisfy({ $0.formatVersion == 1 && $0.revision > 0 }),
          !overflow, revision > 0, field.apply(value, &validated)
        else {
          notice =
            "Some iCloud app settings could not be updated. Your local settings have been kept."
          context.rollback()
          return
        }
        context.insert(
          PrivatePreferencesV1.Change(
            field: field.name, value: value, revision: revision))
      }
      if context.hasChanges { try context.save() }
      for (field, _) in pending { defaults.removeObject(forKey: field.pendingKey) }
    } catch {
      context.rollback()
      notice = "iCloud app settings could not be saved. Your local settings have been kept."
    }
  }

  func reconcile(_ values: [PrivatePreferencesV1.Change.Value]) {
    do {
      let previous = try StudyPortablePreferences.read(defaults)
      var updated = previous
      var unreadable = false
      hasDeferredLearningChanges = false
      for field in Field.all {
        guard defaults.object(forKey: field.pendingKey) == nil else { continue }
        let candidates = values.filter { $0.field == field.name }
        guard !candidates.isEmpty else { continue }
        guard candidates.allSatisfy({ $0.formatVersion == 1 && $0.revision > 0 }),
          let latest = candidates.max(by: {
            ($0.revision, $0.id.uuidString, $0.value) < ($1.revision, $1.id.uuidString, $1.value)
          })
        else {
          unreadable = true
          continue
        }
        var candidate = updated
        guard field.apply(latest.value, &candidate) else {
          unreadable = true
          continue
        }
        if field.affectsLearning, !studyingScenes.isEmpty,
          field.value(candidate) != field.value(updated)
        {
          hasDeferredLearningChanges = true
          continue
        }
        updated = candidate
      }
      if try updated.saveChanges(from: previous, to: defaults) { revision = UUID() }
      if unreadable {
        notice = "Some iCloud app settings could not be read and have been kept unchanged."
      } else if Field.all.allSatisfy({ defaults.object(forKey: $0.pendingKey) == nil }) {
        notice = nil
      }
    } catch {
      notice = "Saved app settings could not be read and have been kept unchanged."
    }
  }

  func updateScene(_ id: UUID, studying: Bool) {
    let wasStudying = !studyingScenes.isEmpty
    if studying { studyingScenes.insert(id) } else { studyingScenes.remove(id) }
    if wasStudying, studyingScenes.isEmpty {
      do { reconcile(try values()) } catch {
        notice = "iCloud app settings could not be read. Your local settings have been kept."
      }
    }
  }
}

extension Binding where Value: Equatable {
  @MainActor func syncing(_ key: StudyPortableSetting, with iCloud: StudyICloudPreferences?) -> Self
  {
    Self(
      get: { wrappedValue },
      set: { value in
        let old = wrappedValue
        wrappedValue = value
        if wrappedValue != old { iCloud?.recordScalarChange(key) }
      })
  }
}

extension EnvironmentValues {
  @Entry public var studyICloudPreferences: StudyICloudPreferences? = nil
}

extension View {
  public func studyICloudPreferences(_ preferences: StudyICloudPreferences?) -> some View {
    environment(\.studyICloudPreferences, preferences).background {
      if let preferences, let container = preferences.container {
        ICloudPreferenceObserver(preferences: preferences).modelContainer(container)
      }
    }
  }
}

private struct ICloudPreferenceObserver: View {
  let preferences: StudyICloudPreferences
  @Query private var changes: [PrivatePreferencesV1.Change]
  var body: some View {
    Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
      .onChange(of: changes.map(\.snapshot), initial: true) { _, values in
        preferences.reconcile(values)
      }
  }
}
