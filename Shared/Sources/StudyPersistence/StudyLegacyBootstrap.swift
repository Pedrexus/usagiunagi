import Foundation
import StudyCore
import SwiftData

public struct StudyLegacySource: Sendable {
  public let token: String
  public let account: LegacyStudyExport
  public init(token: String, account: LegacyStudyExport) {
    self.token = token
    self.account = account
  }
}

/// A one-way writer choice. Activation is independent of later sign-out or token replacement.
public struct StudyLegacyHandoff: Codable, Equatable, Sendable {
  public let sourceID: String
  public let accountID: String
  public let credentialID: String
  public fileprivate(set) var activated = false
  var receiptID: String { "ios:" + accountID + ":" + sourceID }
}

public enum StudyBootstrapError: Error, LocalizedError {
  case credentialConflict, sourceChanged, invalidState
  public var errorDescription: String? {
    switch self {
    case .credentialConflict:
      "The saved credential changed during migration. Both account stores have been kept."
    case .sourceChanged:
      "The old account changed during migration. Keep its data and retry after its writer has stopped."
    case .invalidState:
      "The saved migration could not be verified. Both account stores have been kept for recovery."
    }
  }
}

/// The host must own this before opening either writer or starting account/background services.
/// A failed or interrupted handoff never authorizes a fallback to the legacy writer.
@MainActor public final class StudyLegacyBootstrap {
  private let store: StudyStore
  private let sourceID: String
  private let credentials: any StudyCredentialStore
  private let client: any WaniKaniAccountReader
  private let readLegacy: @MainActor () async throws -> StudyLegacySource
  private var run: Task<StudyLegacyHandoff, any Error>?

  public init(
    store: StudyStore, sourceID: String, credentials: any StudyCredentialStore,
    client: any WaniKaniAccountReader = WaniKaniClient(),
    readLegacy: @escaping @MainActor () async throws -> StudyLegacySource
  ) {
    self.store = store
    self.sourceID = sourceID
    self.credentials = credentials
    self.client = client
    self.readLegacy = readLegacy
  }

  /// Shared by bootstrap waiters; cancelling a scene does not interrupt the durable handoff.
  public func activate() async throws -> StudyLegacyHandoff {
    try Task.checkCancellation()
    let task =
      run
      ?? Task {
        defer { run = nil }
        return try await perform()
      }
    run = task
    let handoff = try await task.value
    try Task.checkCancellation()
    return handoff
  }

  private func requireCredential(_ id: String) throws -> String? {
    let token = try credentials.load()
    if let token, StudyCredentialID.forToken(token) != id {
      throw StudyBootstrapError.credentialConflict
    }
    return token
  }

  private func perform() async throws -> StudyLegacyHandoff {
    guard !sourceID.isEmpty else { throw StudyBootstrapError.invalidState }
    let previous = try await store.legacyHandoff(sourceID: sourceID)
    // Never inspect the retired source, network or credential to choose the writer again.
    if let previous, previous.activated { return previous }
    let source = try await readLegacy()
    let token = source.token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { throw StudyBootstrapError.credentialConflict }
    let credentialID = StudyCredentialID.forToken(token)
    _ = try requireCredential(credentialID)
    let prepared: StudyLegacyHandoff
    if let previous {
      guard previous.credentialID == credentialID else {
        throw StudyBootstrapError.credentialConflict
      }
      // The receipt already binds the exact source digest and credential to a verified account.
      prepared = try await store.prepareLegacyHandoff(
        source.account, sourceID: sourceID,
        accountID: previous.accountID, credentialID: credentialID, identity: nil)
    } else {
      let identity = try await client.account(token: token)
      try identity.requireLegacyAccount(source.account.profile)
      guard identity.profile != nil else { throw WaniKaniClient.APIError.invalidResponse }
      let current = try await readLegacy()
      guard current.token.trimmingCharacters(in: .whitespacesAndNewlines) == token,
        try current.account.importDigest == source.account.importDigest
      else { throw StudyBootstrapError.sourceChanged }
      prepared = try await store.prepareLegacyHandoff(
        source.account, sourceID: sourceID,
        accountID: identity.id, credentialID: credentialID, identity: identity)
    }
    if prepared.activated { return prepared }
    // Recheck after actor suspension; never overwrite another account's newer credential.
    if try requireCredential(credentialID) == nil { try credentials.save(token) }
    guard try requireCredential(credentialID) != nil else {
      throw StudyBootstrapError.credentialConflict
    }
    return try await store.activateLegacyHandoff(prepared)
  }
}

extension LegacyStudyExport {
  var importDigest: String {
    get throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      return StudyCredentialID.forData(try encoder.encode(self))
    }
  }
}

extension StudyStore {
  public func legacyHandoff(sourceID: String) throws -> StudyLegacyHandoff? {
    let matches = try modelContext.fetch(FetchDescriptor<ImportReceipt>()).compactMap(\.handoff)
      .filter { $0.sourceID == sourceID }
    guard matches.count <= 1 else { throw StudyBootstrapError.invalidState }
    return matches.first
  }

  func prepareLegacyHandoff(
    _ source: LegacyStudyExport, sourceID: String, accountID: String,
    credentialID: String, identity: WaniKaniAccount?
  ) throws -> StudyLegacyHandoff {
    let handoff = StudyLegacyHandoff(
      sourceID: sourceID, accountID: accountID, credentialID: credentialID)
    if let previous = try legacyHandoff(sourceID: sourceID) {
      guard previous.accountID == accountID, previous.credentialID == credentialID else {
        throw StudyBootstrapError.credentialConflict
      }
      if previous.activated { return previous }
    } else {
      guard let identity, identity.id == accountID else { throw StudyBootstrapError.invalidState }
      try identity.requireLegacyAccount(source.profile)
    }
    // Import commits its own receipt first. An interruption before the binding below simply
    // requires fresh identity verification; its idempotent import cannot resurrect consumed work.
    try importLegacyAccount(
      source, sourceID: sourceID, verifiedAccountID: accountID,
      verifiedUsername: source.profile.username, credentialID: credentialID)
    guard try snapshot(credentialID: credentialID)?.accountID == accountID,
      try accountState(accountID: accountID) != nil
    else { throw StudyBootstrapError.invalidState }
    if let identity { try applyVerifiedAccount(identity, accountID: accountID) }
    let receiptID = handoff.receiptID
    try transaction {
      guard
        let receipt = try modelContext.fetch(
          FetchDescriptor<ImportReceipt>(
            predicate:
              #Predicate { $0.sourceID == receiptID })
        ).first
      else { throw StudyBootstrapError.invalidState }
      receipt.handoff = handoff
    }
    return handoff
  }

  func activateLegacyHandoff(_ handoff: StudyLegacyHandoff) throws -> StudyLegacyHandoff {
    var result = handoff
    let receiptID = handoff.receiptID
    try transaction {
      guard
        let receipt = try modelContext.fetch(
          FetchDescriptor<ImportReceipt>(
            predicate:
              #Predicate { $0.sourceID == receiptID })
        ).first,
        let saved = receipt.handoff, saved.accountID == handoff.accountID,
        saved.credentialID == handoff.credentialID, saved.sourceID == handoff.sourceID
      else { throw StudyBootstrapError.invalidState }
      result = saved
      if saved.activated { return }
      guard try snapshot(credentialID: saved.credentialID)?.accountID == saved.accountID,
        try accountState(accountID: saved.accountID) != nil
      else { throw StudyBootstrapError.invalidState }
      result.activated = true
      receipt.handoff = result
    }
    return result
  }
}
