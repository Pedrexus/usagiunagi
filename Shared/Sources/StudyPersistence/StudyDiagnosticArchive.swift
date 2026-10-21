import CoreTransferable
import Foundation
import StudyCore
import SwiftData
import UniformTypeIdentifiers

/// An account-scoped diagnostic projection, not a restorable store or an upload queue.
public struct StudyDiagnosticDocument: Codable, Sendable {
  public enum ReceiptScope: String, Codable, Sendable {
    case verifiedAccountHandoffsOnly
  }
  public struct Assignment: Codable, Sendable {
    public let revision: UUID
    public let value: CatalogAssignment
  }
  public struct Session: Codable, Sendable {
    public let revision: UUID
    public let value: StudySession
  }
  public struct Material: Codable, Sendable {
    public struct Baseline: Codable, Sendable {
      /// A present baseline with no remote value means the material was checked and missing.
      public let remote: WaniKaniMaterial?
    }
    public let value: StudyMaterial
    public let revision: UUID
    public let pending: Bool
    public let serverID: Int64?
    public let issue: StudyUploadIssue?
    public let attemptedRevision: UUID?
    public let attemptedMaterial: StudyMaterial?
    public let recoveryBaseline: Baseline?
  }
  public struct Import: Codable, Sendable {
    public let sourceDigest: String
    public let activated: Bool
  }
  public let formatVersion: Int
  public let generatedAt: Date
  public let accountID: String
  public let account: StudyAccountState
  public let snapshots: [StudySnapshot]
  public let catalog: [CatalogSubject]
  public let assignments: [Assignment]
  public let session: Session?
  public let reviews: [SavedReview]
  public let materials: [Material]
  public let archivedReviews: [ArchivedStudyReview]
  public let retryAt: Date?
  /// Unbound receipts and global writer selection are always outside this format's scope.
  public let receiptScope: ReceiptScope
  public let imports: [Import]
}

/// Apple owns transfer-file publication and lifetime; the app keeps no diagnostic cache.
public struct StudyDiagnosticArchive: Transferable, Sendable {
  private let store: StudyStore
  private let accountID: String
  private let fileName: String
  public init(store: StudyStore, accountID: String) {
    self.store = store
    self.accountID = accountID
    fileName = "usagiunagi-study-diagnostics-\(UUID()).plist"
  }
  public static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .binaryPropertyList) { archive in
      try await archive.data()
    }.suggestedFileName { $0.fileName }
  }
  @concurrent public func data() async throws -> Data {
    let document = try await store.diagnosticDocument(accountID: accountID)
    try Task.checkCancellation()
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(document)
    try Task.checkCancellation()
    return data
  }
}

extension StudyStore {
  /// No suspension or mutation: all reads observe one committed state of the single app writer.
  public func diagnosticDocument(accountID: String, generatedAt: Date = .now) throws
    -> StudyDiagnosticDocument
  {
    try Task.checkCancellation()
    try requireAccount(accountID)
    guard let account = try accountState(accountID: accountID) else {
      throw StudyStoreError.invalidIdentity
    }
    let snapshots = try modelContext.fetch(FetchDescriptor<SnapshotRecord>()).map(\.snapshot)
      .filter { $0.accountID == accountID && !$0.isSample }.sorted { $0.savedAt < $1.savedAt }
    let assignments = try modelContext.fetch(
      FetchDescriptor<AssignmentRecord>(
        predicate: #Predicate { $0.accountID == accountID }, sortBy: [SortDescriptor(\.subjectID)])
    ).map { StudyDiagnosticDocument.Assignment(revision: $0.revision, value: $0.assignment) }
    let savedSession = try session(accountID: accountID).map {
      StudyDiagnosticDocument.Session(revision: $0.revision, value: $0.session)
    }
    let materials = try MaterialRecord.fetch(in: modelContext, accountID: accountID).sorted {
      $0.subjectID < $1.subjectID
    }
    .map { row in
      StudyDiagnosticDocument.Material(
        value: row.material, revision: row.revision, pending: row.pending, serverID: row.serverID,
        issue: row.issue, attemptedRevision: row.attemptedRevision,
        attemptedMaterial: row.attemptedMaterial,
        recoveryBaseline: row.recoveryBaseline.map { .init(remote: $0.remote) })
    }
    // A bound handoff carries verified ownership. Never infer it from a string prefix or include
    // raw receipt names, credential fingerprints, preference payloads or unbound/global counts.
    let imports = try modelContext.fetch(FetchDescriptor<ImportReceipt>()).compactMap {
      row -> StudyDiagnosticDocument.Import? in
      guard let handoff = row.handoff, handoff.accountID == accountID else {
        return nil
      }
      guard row.sourceID == handoff.receiptID else { throw StudyBootstrapError.invalidState }
      return StudyDiagnosticDocument.Import(sourceDigest: row.digest, activated: handoff.activated)
    }.sorted { $0.sourceDigest < $1.sourceDigest }
    let retryAt = try modelContext.fetch(
      FetchDescriptor<UploadPauseRecord>(predicate: #Predicate { $0.accountID == accountID })
    ).first?.retryAt
    return try StudyDiagnosticDocument(
      formatVersion: 1, generatedAt: generatedAt, accountID: accountID, account: account,
      snapshots: snapshots, catalog: catalog(accountID: accountID), assignments: assignments,
      session: savedSession, reviews: pendingReviews(accountID: accountID), materials: materials,
      archivedReviews: archivedReviews(accountID: accountID), retryAt: retryAt,
      receiptScope: .verifiedAccountHandoffsOnly, imports: imports)
  }
}
