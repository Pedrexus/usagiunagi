import Testing

@testable import StudyCore

struct StudyLevelProgressTests {
  @Test func mixedStagesPreserveEveryAssignment() {
    let progress = StudyLevelProgress(
      kind: .kanji,
      stages: [
        (nil, false), (nil, true), (0, false), (0, true),
        (1, true), (4, true), (5, true), (6, true), (9, true),
      ])
    #expect(progress.id == .kanji)
    #expect(progress.locked == 2)
    #expect(progress.lessons == 1)
    #expect(progress.apprentice == 3)
    #expect(progress.guru == 3)
    #expect(progress.total == 9)
  }

  @Test(arguments: [SubjectKind.radical, .kanji, .vocabulary])
  func emptySubjectsStayEmpty(_ kind: SubjectKind) {
    let progress = StudyLevelProgress(kind: kind, stages: [])
    #expect(progress.kind == kind)
    #expect(progress.total == 0)
  }

  @Test(arguments: 1...9)
  func guruBoundaryMatchesWaniKani(_ stage: Int) {
    let progress = StudyLevelProgress(kind: .vocabulary, stages: [(stage, true)])
    #expect(progress.apprentice == (stage < 5 ? 1 : 0))
    #expect(progress.guru == (stage >= 5 ? 1 : 0))
    #expect(progress.total == 1)
  }
}
