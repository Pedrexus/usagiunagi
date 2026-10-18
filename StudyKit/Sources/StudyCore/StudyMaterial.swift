import Foundation

/// Notes and synonyms remain independent of the download cache. Preserve note text verbatim.
public struct StudyMaterial: Codable, Equatable, Sendable {
  public static let exclusionMarker = "#tsurukameExclude"
  public let subjectID: Int64
  public var meaningNote: String
  public var readingNote: String
  public var meaningSynonyms: [String]
  public init(
    subjectID: Int64, meaningNote: String = "", readingNote: String = "",
    meaningSynonyms: [String] = []
  ) {
    self.subjectID = subjectID
    self.meaningNote = meaningNote
    self.readingNote = readingNote
    self.meaningSynonyms = meaningSynonyms
  }
  public var isExcluded: Bool { meaningNote.contains(Self.exclusionMarker) }
  public var meaningNoteText: String {
    meaningNote.replacingOccurrences(of: Self.exclusionMarker, with: "")
  }
  /// An untouched editor preserves the exact original bytes, including marker placement.
  public func replacingMeaningNote(_ text: String) -> Self {
    var result = self
    if text != meaningNoteText {
      result.meaningNote = text + (isExcluded ? Self.exclusionMarker : "")
    }
    return result
  }
}

/// Only editable fields participate in a replacement; account metadata and hidden notes survive.
public struct StudyMaterialChanges: Sendable {
  public var meaningNote: String?
  public var readingNote: String?
  public var meaningSynonyms: [String]?
  public init(
    meaningNote: String? = nil, readingNote: String? = nil, meaningSynonyms: [String]? = nil
  ) {
    self.meaningNote = meaningNote
    self.readingNote = readingNote
    self.meaningSynonyms = meaningSynonyms
  }
  public func applying(to material: StudyMaterial) -> StudyMaterial {
    var result = material
    if let meaningNote { result = result.replacingMeaningNote(meaningNote) }
    if let readingNote { result.readingNote = readingNote }
    if let meaningSynonyms { result.meaningSynonyms = meaningSynonyms }
    return result
  }
}

public struct StudyMaterialEdit<Version: Equatable & Sendable>: Equatable, Sendable {
  public let material: StudyMaterial
  public let version: Version?
  public init(material: StudyMaterial, version: Version?) {
    self.material = material
    self.version = version
  }
}

public struct StudyMaterialEditConflict<Version: Equatable & Sendable>: Error {
  public let current: StudyMaterialEdit<Version>
  public init(current: StudyMaterialEdit<Version>) { self.current = current }
}
