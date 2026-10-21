import CoreTransferable
import Foundation
import StudyCore
import SwiftData
import UniformTypeIdentifiers

/// Saved public content only. Requested levels describe the scope, not a completeness guarantee.
public struct StudyCatalogDocument: Codable, Sendable {
  public let formatVersion: Int
  public let capturedAt: String
  public let requestedLevels: [Int]
  public let subjects: [CatalogSubject]
  public let systems: [StudySRSSystem]?
  public let voices: [StudyVoiceActor]
}

public struct StudyCatalogArchive: Transferable, Sendable {
  let store: StudyStore
  let accountID: String
  enum Failure: LocalizedError {
    case empty
    var errorDescription: String? {
      "No subjects from levels 1–3 are saved. Refresh your account before exporting."
    }
  }
  public static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .binaryPropertyList) { archive in
      try await archive.data()
    }.suggestedFileName { _ in "usagiunagi-free-levels.plist" }
  }
  @concurrent public func data() async throws -> Data {
    let document = try await store.freeLevelCatalogDocument(accountID: accountID)
    try Task.checkCancellation()
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let result = try encoder.encode(document)
    try Task.checkCancellation()
    return result
  }
}

extension StudyStore {
  /// One actor-owned read; no account identity, notes, progress, credentials or queue state leave.
  public func freeLevelCatalogDocument(accountID: String, capturedAt: Date = .now) throws
    -> StudyCatalogDocument
  {
    try Task.checkCancellation()
    try requireAccount(accountID)
    guard let state = try accountState(accountID: accountID) else {
      throw StudyStoreError.invalidIdentity
    }
    let rows = try CatalogRecord.freeLevels(in: modelContext, accountID: accountID)
    guard
      rows.allSatisfy({
        $0.subjectID == $0.subject.id && $0.subjectID > 0 && $0.level == $0.subject.level
      })
    else { throw StudyStoreOpeningError.invalidGeneration }
    let subjects = rows.map(\.subject).filter { $0.hiddenAt == nil }
    guard !subjects.isEmpty else { throw StudyCatalogArchive.Failure.empty }
    return StudyCatalogDocument(
      formatVersion: 1, capturedAt: capturedAt.ISO8601Format(), requestedLevels: [1, 2, 3],
      subjects: subjects, systems: state.systems, voices: state.voices)
  }
}
