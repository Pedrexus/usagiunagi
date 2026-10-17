import Foundation
import StudyCore
import SwiftData

public struct StudySubjectDetails: Sendable {
  public let subject: CatalogSubject
  public let material: StudyMaterial?
  public let components: [CatalogSubject]
  public let combinations: [CatalogSubject]
  public let similar: [CatalogSubject]
  public var unavailableRelatedCount: Int {
    let requested = Set(
      subject.componentSubjectIDs + subject.amalgamationSubjectIDs + subject.visuallySimilarKanjiIDs
    )
    let available = Set((components + combinations + similar).map(\.id))
    return requested.subtracting(available).count
  }
}

public enum SubjectDetailsError: Error, LocalizedError {
  case unavailable
  case subscriptionLimit(Int)
  public var errorDescription: String? {
    switch self {
    case .unavailable: "This subject is not in the available saved catalog. Refresh study content."
    case .subscriptionLimit(let level):
      "Your verified content access extends through level \(level)."
    }
  }
}

extension StudyStore {
  /// One account-bound read, including unsent local notes and only accessible related content.
  public func subjectDetails(subjectID: Int64, accountID: String) throws -> StudySubjectDetails {
    try requireAccount(accountID)
    guard let profile = try accountState(accountID: accountID)?.profile,
      let subject = try modelContext.fetch(
        FetchDescriptor<CatalogRecord>(
          predicate: #Predicate {
            $0.accountID == accountID && $0.subjectID == subjectID
          })
      ).first?.subject, subject.hiddenAt == nil
    else { throw SubjectDetailsError.unavailable }
    guard subject.level <= profile.maxLevelGranted else {
      throw SubjectDetailsError.subscriptionLimit(profile.maxLevelGranted)
    }
    let ids = Array(
      Set(
        subject.componentSubjectIDs + subject.amalgamationSubjectIDs
          + subject.visuallySimilarKanjiIDs))
    let related = try modelContext.fetch(
      FetchDescriptor<CatalogRecord>(
        predicate: #Predicate {
          $0.accountID == accountID && ids.contains($0.subjectID)
        })
    ).map(\.subject).filter { $0.hiddenAt == nil && $0.level <= profile.maxLevelGranted }
    let byID = Dictionary(uniqueKeysWithValues: related.map { ($0.id, $0) })
    func ordered(_ ids: [Int64]) -> [CatalogSubject] {
      var seen = Set<Int64>()
      return ids.filter { seen.insert($0).inserted }.compactMap { byID[$0] }
    }
    let material = try modelContext.fetch(
      FetchDescriptor<MaterialRecord>(
        predicate: #Predicate {
          $0.accountID == accountID && $0.subjectID == subjectID
        })
    ).first?.material
    return StudySubjectDetails(
      subject: subject, material: material,
      components: ordered(subject.componentSubjectIDs),
      combinations: ordered(subject.amalgamationSubjectIDs),
      similar: ordered(subject.visuallySimilarKanjiIDs))
  }
}
