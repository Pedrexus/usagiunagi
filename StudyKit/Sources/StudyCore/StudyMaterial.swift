import Foundation

/// Notes and synonyms remain independent of the download cache. Preserve note text verbatim.
public struct StudyMaterial: Codable, Equatable, Sendable {
    public let subjectID: Int64
    public var meaningNote: String
    public var readingNote: String
    public var meaningSynonyms: [String]
    public init(subjectID: Int64, meaningNote: String = "", readingNote: String = "", meaningSynonyms: [String] = []) {
        self.subjectID = subjectID; self.meaningNote = meaningNote
        self.readingNote = readingNote; self.meaningSynonyms = meaningSynonyms
    }
}
