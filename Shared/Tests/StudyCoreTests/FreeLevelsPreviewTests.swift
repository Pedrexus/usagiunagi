import Foundation
import Testing

@testable import StudyCore

@Suite struct FreeLevelsPreviewTests {
  @Test func referenceCatalogStaysDisplayOnlyAndSeparateFromAccountWork() throws {
    let preview = try StudySnapshot.freeLevelsPreview(now: Date(timeIntervalSince1970: 1))
    #expect(preview.isSample && preview.accountID == nil)
    #expect(preview.assignments.isEmpty && preview.statistics.isEmpty && preview.levels.isEmpty)
    #expect(preview.pendingReviews == 0)
    #expect(preview.subjects.count == 357)
    #expect(Set(preview.subjects.map(\.id)).count == 357)
    #expect(preview.subjects.allSatisfy { $0.id < 0 && (1...3).contains($0.level) })
    #expect(preview.subjects.allSatisfy { !$0.characters.isEmpty && !$0.meaning.isEmpty })
    #expect(
      [1, 2, 3].map { level in preview.subjects.filter { $0.level == level }.count } == [
        80, 147, 130,
      ])
    #expect(preview.metrics().dueNow == 0)
  }
  @Test func readingAndMeaningStayAttachedToTheRightSubjectKind() throws {
    let subjects = try StudySnapshot.freeLevelsPreview().subjects
    let one = try #require(subjects.first { $0.characters == "一" && $0.kind == .kanji })
    let ground = try #require(subjects.first { $0.characters == "一" && $0.kind == .radical })
    #expect(one.meaning == "One" && one.readings == ["いち"])
    #expect(ground.meaning == "Ground" && ground.readings.isEmpty)
    #expect(
      subjects.contains {
        $0.kind == .vocabulary && $0.characters == "大人" && $0.readings == ["おとな"]
      })
    #expect(try StudySnapshot.freeLevelsPreview().subjects.map(\.id) == subjects.map(\.id))
  }
}
