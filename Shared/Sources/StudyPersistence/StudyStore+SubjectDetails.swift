import Foundation
import StudyCore
import SwiftData

public struct StudySubjectDetails: Sendable {
  public let subject: CatalogSubject
  public let currentLevel: Int
  public let assignment: CatalogAssignment?
  public let savedMaterial: SavedStudyMaterial?
  public var material: StudyMaterial? { savedMaterial?.material }
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
  case vocabularyRequired
  case subscriptionLimit(Int)
  public var errorDescription: String? {
    switch self {
    case .vocabularyRequired: "Only vocabulary items can be excluded."
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
      let subject = try CatalogRecord.fetch(
        in: modelContext, accountID: accountID, subjectID: subjectID)?.subject,
      subject.hiddenAt == nil
    else { throw SubjectDetailsError.unavailable }
    guard subject.level <= profile.maxLevelGranted else {
      throw SubjectDetailsError.subscriptionLimit(profile.maxLevelGranted)
    }
    let forms = subject.kind == .kanji ? subject.visuallySimilarKanji.map(String.init) : []
    let ids = Array(
      Set(
        subject.componentSubjectIDs + subject.amalgamationSubjectIDs
          + subject.visuallySimilarKanjiIDs))
    let related = try modelContext.fetch(
      FetchDescriptor<CatalogRecord>(
        predicate: #Predicate {
          $0.accountID == accountID && (ids.contains($0.subjectID) || forms.contains($0.japanese))
        })
    ).map(\.subject).filter { $0.hiddenAt == nil && $0.level <= profile.maxLevelGranted }
    let byID = Dictionary(uniqueKeysWithValues: related.map { ($0.id, $0) })
    let formIDs = forms.compactMap { form in
      related.filter { $0.kind == .kanji && $0.japanese == form }.map(\.id).min()
    }
    let assignment = try AssignmentRecord.fetch(
      in: modelContext, accountID: accountID, subjectID: subjectID)?.assignment
    var displayedSubject = subject
    displayedSubject.visuallySimilarKanji = ""
    func ordered(_ ids: [Int64]) -> [CatalogSubject] {
      var seen = Set<Int64>()
      return ids.filter { seen.insert($0).inserted }.compactMap { byID[$0] }
    }
    let material = try MaterialRecord.fetch(
      in: modelContext, accountID: accountID, subjectID: subjectID)?.saved
    return StudySubjectDetails(
      subject: displayedSubject, currentLevel: profile.level, assignment: assignment,
      savedMaterial: material,
      components: ordered(subject.componentSubjectIDs),
      combinations: ordered(subject.amalgamationSubjectIDs),
      similar: ordered(subject.visuallySimilarKanjiIDs + formIDs))
  }

  /// Read the latest material on the actor so a toggle cannot replace newer notes or synonyms.
  @discardableResult public func setSubjectExcluded(
    subjectID: Int64, accountID: String, excluded: Bool
  ) throws -> StudySubjectDetails {
    let current = try subjectDetails(subjectID: subjectID, accountID: accountID)
    guard current.subject.kind == .vocabulary else { throw SubjectDetailsError.vocabularyRequired }
    var material = current.material ?? StudyMaterial(subjectID: subjectID)
    material.isExcluded = excluded
    try saveSubjectMaterial(
      material, accountID: accountID, expectedRevision: current.savedMaterial?.revision)
    return try subjectDetails(subjectID: subjectID, accountID: accountID)
  }

  /// Revalidate access and the editor's revision on the store actor before queuing a local edit.
  /// Opening and saving unchanged content must not create an upload or disturb an existing one.
  public func saveSubjectMaterial(
    _ material: StudyMaterial, accountID: String, expectedRevision: UUID?
  ) throws {
    try transaction {
      try writeSubjectMaterial(material, accountID: accountID, expectedRevision: expectedRevision)
    }
  }

  /// Caller owns the transaction; retain access checks and unchanged-edit semantics.
  func writeSubjectMaterial(_ material: StudyMaterial, accountID: String, expectedRevision: UUID?)
    throws
  {
    let details = try subjectDetails(subjectID: material.subjectID, accountID: accountID)
    guard details.savedMaterial?.revision == expectedRevision else {
      throw StudyStoreError.staleMaterial
    }
    guard material != (details.material ?? StudyMaterial(subjectID: material.subjectID)) else {
      return
    }
    _ = try writeMaterial(material, accountID: accountID, expectedRevision: expectedRevision)
  }
}
