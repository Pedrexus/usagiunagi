import CoreTransferable
import Foundation
import StudyPersistence
import UniformTypeIdentifiers

nonisolated struct ArchivedReviewTransfer: Transferable {
  let value: ArchivedStudyReview
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .json) { (item: Self) in
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      return try encoder.encode(item.value)
    }.suggestedFileName {
      "usagiunagi-answer-\($0.value.saved.subjectID)-\($0.value.id.uuidString).json"
    }
  }
}
