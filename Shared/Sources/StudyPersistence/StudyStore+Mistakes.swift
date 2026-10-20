import Foundation
import StudyCore
import SwiftData

/// Supplied only by a verified source handoff. Existing receipts do not acquire this implicitly.
public struct StudyLegacyMistakeBinding: Codable, Equatable, Sendable {
  public let accountID: String
  public let sourceID: String
  public let sourceDigest: String
  public let username: String
  public let context: StudyLegacyMistakeContext
  public init(
    accountID: String, sourceID: String, sourceDigest: String, username: String,
    context: StudyLegacyMistakeContext
  ) {
    self.accountID = accountID
    self.sourceID = sourceID
    self.sourceDigest = sourceDigest
    self.username = username
    self.context = context
  }
  public var key: String { username + "tsurukame-mistakes" }
}

/// Revocation retains the original evidence and cannot be undone by a later username change.
public enum StudyLegacyMistakeAccess: Codable, Equatable, Sendable {
  case active(StudyLegacyMistakeBinding)
  case revoked(StudyLegacyMistakeBinding)
}

public struct StudyMistakeState: Sendable {
  public let accountID: String
  public let username: String
  public let values: [Int64: Int64]
  public let legacyBinding: StudyLegacyMistakeBinding?
  public let needsLegacyImport: Bool
}

extension StudyStore {
  public func mistakeState(accountID: String) throws -> StudyMistakeState {
    try Task.checkCancellation()
    try requireAccount(accountID)
    guard let state = try accountState(accountID: accountID) else {
      throw StudyStoreError.invalidIdentity
    }
    let (legacy, needsLegacyImport) = try mistakeBindingState(
      accountID: accountID, username: state.profile.username)
    let ids = Set(try catalog(accountID: accountID).map(\.id))
    var values: [Int64: Int64] = [:]
    let localTimes = state.progress.reduce(into: [String: String]()) { result, progress in
      if ids.contains(progress.subjectID), let text = progress.lastMistakeLocalTime {
        result[String(progress.subjectID)] = text
      }
    }
    if let legacy, !localTimes.isEmpty {
      let old = StudyLegacyMistakes(originals: localTimes, context: legacy.context)
      values = old.values
    }
    for progress in state.progress where ids.contains(progress.subjectID) {
      if let epoch = progress.lastMistakeAt, epoch >= 0 {
        values[progress.subjectID] = max(epoch, values[progress.subjectID] ?? epoch)
      }
    }
    return .init(
      accountID: accountID, username: state.profile.username, values: values, legacyBinding: legacy,
      needsLegacyImport: needsLegacyImport)
  }

  /// Only existing supported progress changes. No SRS, assignment, answer or upload is created.
  @discardableResult public func mergeMistakes(_ incoming: [Int64: Int64], accountID: String) throws
    -> Bool
  {
    try Task.checkCancellation()
    try requireAccount(accountID)
    guard incoming.allSatisfy({ $0.key > 0 && $0.value >= 0 }) else {
      throw StudyMistakeError.invalidArchive
    }
    guard
      let row = try modelContext.fetch(
        FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.accountID == accountID })
      ).first
    else { throw StudyStoreError.invalidIdentity }
    let ids = Set(try catalog(accountID: accountID).map(\.id))
    var state = row.state
    var changed = false
    for index in state.progress.indices where ids.contains(state.progress[index].subjectID) {
      guard let timestamp = incoming[state.progress[index].subjectID],
        timestamp > (state.progress[index].lastMistakeAt ?? -1)
      else { continue }
      state.progress[index].lastMistakeAt = timestamp
      changed = true
    }
    guard changed else { return false }
    try transaction { row.state = state }
    return true
  }

  private func mistakeBindingState(accountID: String, username: String) throws
    -> (StudyLegacyMistakeBinding?, Bool)
  {
    var active: StudyLegacyMistakeBinding?
    var unverified = false
    for receipt in try modelContext.fetch(FetchDescriptor<ImportReceipt>()) {
      guard let handoff = receipt.handoff, handoff.accountID == accountID, handoff.activated else {
        continue
      }
      guard let access = handoff.mistakeAccess else {
        unverified = true
        continue
      }
      guard case .active(let binding) = access else { continue }
      guard binding.accountID == accountID, !binding.sourceID.isEmpty, !binding.username.isEmpty,
        binding.key.utf16.count <= 128, binding.sourceDigest == receipt.digest,
        handoff.sourceID == binding.sourceID, handoff.receiptID == receipt.sourceID
      else { throw StudyStoreError.invalidIdentity }
      guard binding.username == username else {
        unverified = true
        continue
      }
      guard active == nil else { throw StudyStoreError.invalidIdentity }
      active = binding
    }
    return (active, unverified)
  }

  /// Plans only; apply inside the same transaction as the verified profile, never on a cached read.
  func legacyMistakeRevocations(accountID: String, username: String) throws
    -> [(ImportReceipt, StudyLegacyHandoff)]
  {
    guard !username.isEmpty else { throw WaniKaniClient.APIError.invalidResponse }
    return try modelContext.fetch(FetchDescriptor<ImportReceipt>()).compactMap { receipt in
      guard var handoff = receipt.handoff, handoff.accountID == accountID,
        handoff.revokeMistakes(ifUsernameChangedTo: username)
      else { return nil }
      return (receipt, handoff)
    }
  }
}
