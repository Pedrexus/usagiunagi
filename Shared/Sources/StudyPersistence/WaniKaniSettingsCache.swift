import Foundation
import StudyCore
import SwiftData

/// Account/origin cache and pending user edits, separate from study data and private iCloud.
enum WaniKaniSettingsV1: VersionedSchema {
  static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
  static var models: [any PersistentModel.Type] { [Entry.self] }

  @Model final class Entry {
    var accountID: String
    var service: String
    var preferences: WaniKaniPreferences
    var savedAt: Date
    var pending: WaniKaniPreferenceChanges?
    var needsConfirmation = false
    init(accountID: String, service: String, preferences: WaniKaniPreferences, savedAt: Date) {
      self.accountID = accountID
      self.service = service
      self.preferences = preferences
      self.savedAt = savedAt
    }
  }
}

@ModelActor public actor WaniKaniSettingsCache {
  public struct Value: Sendable {
    public let preferences: WaniKaniPreferences
    public let savedAt: Date
    public let pending: WaniKaniPreferenceChanges
    public let needsConfirmation: Bool
  }

  @concurrent public static func open(in directory: URL) async throws -> WaniKaniSettingsCache {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let schema = Schema(versionedSchema: WaniKaniSettingsV1.self)
    let configuration = ModelConfiguration(
      schema: schema, url: directory.appending(path: "wanikani-settings.store"),
      cloudKitDatabase: .none)
    return WaniKaniSettingsCache(
      modelContainer: try ModelContainer(for: schema, configurations: configuration))
  }

  public func value(accountID: String, service: String) throws -> Value? {
    guard let entry = try entry(accountID: accountID, service: service) else { return nil }
    return Value(
      preferences: entry.preferences, savedAt: entry.savedAt, pending: entry.pending ?? .init(),
      needsConfirmation: entry.needsConfirmation)
  }

  public func save(
    _ preferences: WaniKaniPreferences, accountID: String, service: String, now: Date,
    pending: WaniKaniPreferenceChanges = .init(), needsConfirmation: Bool = false
  ) throws {
    guard preferences.lessonsBatchSize > 0 else { throw WaniKaniPreferenceError.invalidBatchSize }
    guard pending.lessonsBatchSize.map({ $0 > 0 }) != false else {
      throw WaniKaniPreferenceError.invalidBatchSize
    }
    let previous = try entry(accountID: accountID, service: service)
    do {
      let value =
        previous
        ?? WaniKaniSettingsV1.Entry(
          accountID: accountID, service: service, preferences: preferences, savedAt: now)
      if previous == nil { modelContext.insert(value) }
      value.preferences = preferences
      value.savedAt = now
      value.pending = pending.isEmpty ? nil : pending
      value.needsConfirmation = needsConfirmation && !pending.isEmpty
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  public func remove(accountID: String) throws {
    guard !accountID.isEmpty else { throw StudyStoreError.invalidIdentity }
    modelContext.autosaveEnabled = false
    let query = FetchDescriptor<WaniKaniSettingsV1.Entry>(
      predicate: #Predicate { $0.accountID == accountID })
    for entry in try modelContext.fetch(query) { modelContext.delete(entry) }
    if modelContext.hasChanges {
      do { try modelContext.save() } catch {
        modelContext.rollback()
        throw error
      }
    }
  }

  private func entry(accountID: String, service: String) throws -> WaniKaniSettingsV1.Entry? {
    guard !accountID.isEmpty, !service.isEmpty else { throw StudyStoreError.invalidIdentity }
    modelContext.autosaveEnabled = false
    var query = FetchDescriptor<WaniKaniSettingsV1.Entry>(
      predicate: #Predicate {
        $0.accountID == accountID && $0.service == service
      })
    query.fetchLimit = 2
    let entries = try modelContext.fetch(query)
    guard entries.count <= 1,
      entries.first.map({
        $0.preferences.lessonsBatchSize > 0 && $0.pending?.lessonsBatchSize.map({ $0 > 0 }) != false
      }) != false
    else {
      throw StudyStoreError.invalidIdentity
    }
    return entries.first
  }
}
