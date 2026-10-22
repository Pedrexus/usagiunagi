import Foundation
import StudyCore
import SwiftData

public struct StudyMistakeState: Sendable {
  public let accountID: String
  public let username: String
  public let values: [Int64: Int64]
}

extension StudyStore {
  public func mistakeState(accountID: String) throws -> StudyMistakeState {
    try Task.checkCancellation()
    try requireAccount(accountID)
    guard let state = try accountState(accountID: accountID) else {
      throw StudyStoreError.invalidIdentity
    }
    let ids = Set(try catalog(accountID: accountID).map(\.id))
    var values: [Int64: Int64] = [:]
    for progress in state.progress where ids.contains(progress.subjectID) {
      if let epoch = progress.lastMistakeAt, epoch >= 0 {
        values[progress.subjectID] = max(epoch, values[progress.subjectID] ?? epoch)
      }
    }
    return .init(accountID: accountID, username: state.profile.username, values: values)
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
      let row = try AccountRecord.fetch(in: modelContext, accountID: accountID)
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
}
