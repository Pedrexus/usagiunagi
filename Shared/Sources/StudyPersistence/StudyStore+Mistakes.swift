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

public struct StudyMistakeState: Sendable {
  public let accountID: String
  public let username: String
  public let values: [Int64: Int64]
  public let legacyBinding: StudyLegacyMistakeBinding?
}

extension StudyStore {
  public func mistakeState(
    accountID: String, legacyBinding binding: StudyLegacyMistakeBinding? = nil
  ) throws -> StudyMistakeState {
    try Task.checkCancellation()
    try requireAccount(accountID)
    guard let state = try accountState(accountID: accountID) else {
      throw StudyStoreError.invalidIdentity
    }
    let legacy = try validatedMistakeBinding(
      binding, accountID: accountID, username: state.profile.username)
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
      accountID: accountID, username: state.profile.username, values: values, legacyBinding: legacy)
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

  private func validatedMistakeBinding(
    _ binding: StudyLegacyMistakeBinding?, accountID: String, username: String
  ) throws -> StudyLegacyMistakeBinding? {
    guard let binding else { return nil }
    guard binding.accountID == accountID, binding.username == username, !username.isEmpty,
      binding.key.utf16.count <= 128
    else { return nil }
    let sourceID = "ios:" + accountID + ":" + binding.sourceID
    guard
      let receipt = try modelContext.fetch(
        FetchDescriptor<ImportReceipt>(predicate: #Predicate { $0.sourceID == sourceID })
      ).first, receipt.digest == binding.sourceDigest,
      let handoff = receipt.handoff, handoff.activated, handoff.accountID == accountID,
      handoff.sourceID == binding.sourceID, handoff.receiptID == receipt.sourceID
    else { return nil }
    return binding
  }
}
