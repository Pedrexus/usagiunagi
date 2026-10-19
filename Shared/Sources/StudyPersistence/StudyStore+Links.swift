import Foundation
import StudyCore
import SwiftData

extension StudyStore {
  /// Resolve only this account's visible, accessible catalog. Opening a link never starts study.
  public func linkedSubjectID(_ reference: StudyLink.Subject, accountID: String) throws -> Int64 {
    try requireAccount(accountID)
    let id: Int64
    switch reference {
    case .id(let value): id = value
    case .japanese(let kind, let text):
      guard let profile = try accountState(accountID: accountID)?.profile else {
        throw StudyStoreError.invalidIdentity
      }
      let records = try modelContext.fetch(
        FetchDescriptor<CatalogRecord>(
          predicate: #Predicate {
            $0.accountID == accountID && $0.japanese == text
          }))
      guard
        let subject = records.map(\.subject).filter({
          $0.kind == kind && $0.hiddenAt == nil && $0.level <= profile.maxLevelGranted
        }).min(by: { $0.id < $1.id })
      else { throw SubjectDetailsError.unavailable }
      id = subject.id
    }
    return try subjectDetails(subjectID: id, accountID: accountID).subject.id
  }
}
