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

/// CloudKit transports immutable display edits; it never receives WaniKani state or credentials.
@MainActor @Observable public final class StudyCloudPreferences {
  public private(set) var cloudEnabled = false
  public private(set) var notice: String?
  @ObservationIgnored private(set) var container: ModelContainer?
  private let defaults: UserDefaults
  private static let preferencesKey = "native.reviewPreferences"

  private enum Field: String, CaseIterable {
    case appearance, fontScale, stageIndicator
    var pendingKey: String { "native.privateCloudPending.\(rawValue)" }

    func value(in preferences: ReviewPreferences) -> String {
      switch self {
      case .appearance: preferences.appearance.rawValue
      case .fontScale: String(preferences.fontScale)
      case .stageIndicator: preferences.stageIndicator.rawValue
      }
    }

    func apply(_ value: String, to preferences: inout ReviewPreferences) -> Bool {
      switch self {
      case .appearance:
        guard let value = ReviewPreferences.Appearance(rawValue: value) else { return false }
        preferences.appearance = value
      case .fontScale:
        guard let value = Double(value), value.isFinite, (1...2.5).contains(value),
          (value * 4).rounded() == value * 4
        else { return false }
        preferences.fontScale = value
      case .stageIndicator:
        guard let value = ReviewPreferences.StageIndicator(rawValue: value) else { return false }
        preferences.stageIndicator = value
      }
      return true
    }
  }

  public init(directory: URL, cloudContainerIdentifier: String? = nil, defaults: UserDefaults) {
    self.defaults = defaults
    do {
      let schema = Schema(versionedSchema: PrivatePreferencesV1.self)
      var cloud: ModelConfiguration.CloudKitDatabase = .none
      // Let SwiftData inspect signing; never construct CKContainer in an unentitled build.
      if let cloudContainerIdentifier,
        ModelConfiguration(cloudKitDatabase: .automatic).cloudKitContainerIdentifier
          == cloudContainerIdentifier
      {
        cloud = .private(cloudContainerIdentifier)
        cloudEnabled = true
      }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let configuration = ModelConfiguration(
        "PrivatePreferences", schema: schema, url: directory.appending(path: "preferences.store"),
        cloudKitDatabase: cloud)
      let container = try ModelContainer(for: schema, configurations: configuration)
      container.mainContext.autosaveEnabled = false
      self.container = container
      recordChanges(from: .init(), to: .init())
      reconcile(try values())
    } catch {
      cloudEnabled = false
      notice =
        "iCloud display settings are unavailable. Your settings on this device have been kept."
    }
  }

  func values() throws -> [PrivatePreferencesV1.Change.Value] {
    try container?.mainContext.fetch(FetchDescriptor<PrivatePreferencesV1.Change>()).map(\.snapshot)
      ?? []
  }

  /// Only explicit edits publish. Opening a new device must not publish its defaults over iCloud.
  func recordChanges(from old: ReviewPreferences, to new: ReviewPreferences) {
    for field in Field.allCases where field.value(in: old) != field.value(in: new) {
      defaults.set(field.value(in: new), forKey: field.pendingKey)
    }
    let pending = Field.allCases.compactMap { field in
      defaults.string(forKey: field.pendingKey).map { (field, $0) }
    }
    guard !pending.isEmpty, let context = container?.mainContext else { return }
    do {
      let values = try values()
      for (field, value) in pending {
        let previous = values.filter { $0.field == field.rawValue }
        let (revision, overflow) = (previous.map(\.revision).max() ?? 0).addingReportingOverflow(1)
        var validated = new
        guard previous.allSatisfy({ $0.formatVersion == 1 && $0.revision > 0 }),
          !overflow, revision > 0, field.apply(value, to: &validated)
        else {
          notice =
            "Some iCloud display settings need a newer app. Your local settings have been kept."
          context.rollback()
          return
        }
        context.insert(
          PrivatePreferencesV1.Change(
            field: field.rawValue, value: value, revision: revision))
      }
      if context.hasChanges { try context.save() }
      for (field, _) in pending { defaults.removeObject(forKey: field.pendingKey) }
    } catch {
      context.rollback()
      notice = "iCloud display settings could not be saved. Your local settings have been kept."
    }
  }

  func reconcile(_ values: [PrivatePreferencesV1.Change.Value]) {
    do {
      let previous =
        try defaults.data(forKey: Self.preferencesKey).map {
          try JSONDecoder().decode(ReviewPreferences.self, from: $0)
        } ?? ReviewPreferences()
      var updated = previous
      var unreadable = false
      for field in Field.allCases {
        guard defaults.object(forKey: field.pendingKey) == nil else { continue }
        let candidates = values.filter { $0.field == field.rawValue }
        guard !candidates.isEmpty else { continue }
        guard candidates.allSatisfy({ $0.formatVersion == 1 && $0.revision > 0 }),
          let latest = candidates.max(by: {
            ($0.revision, $0.id.uuidString, $0.value) < ($1.revision, $1.id.uuidString, $1.value)
          }), field.apply(latest.value, to: &updated)
        else {
          unreadable = true
          continue
        }
      }
      if updated != previous {
        defaults.set(try JSONEncoder().encode(updated), forKey: Self.preferencesKey)
      }
      if unreadable {
        notice = "Some iCloud display settings could not be read and have been kept unchanged."
      } else if Field.allCases.allSatisfy({ defaults.object(forKey: $0.pendingKey) == nil }) {
        notice = nil
      }
    } catch {
      notice = "Saved display settings could not be read and have been kept unchanged."
    }
  }
}

extension EnvironmentValues {
  @Entry public var studyCloudPreferences: StudyCloudPreferences? = nil
}

extension View {
  public func studyCloudPreferences(_ preferences: StudyCloudPreferences?) -> some View {
    environment(\.studyCloudPreferences, preferences).background {
      if let preferences, let container = preferences.container {
        CloudPreferenceObserver(preferences: preferences).modelContainer(container)
      }
    }
  }
}

private struct CloudPreferenceObserver: View {
  let preferences: StudyCloudPreferences
  @Query private var changes: [PrivatePreferencesV1.Change]
  var body: some View {
    Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
      .onChange(of: changes.map(\.snapshot), initial: true) { _, values in
        preferences.reconcile(values)
      }
  }
}
