import Foundation
import Testing
@testable import StudyCore

@Test func currentSchoolAndJoyoTotals() throws {
    let library = try CurriculumLibrary.bundled()
    let school = library.curricula(for: .school)
    #expect(school.map { $0.characters.count } == [80, 240, 440, 642, 835, 1026])
    #expect(library.curricula(for: .joyo).map { $0.characters.count } == [2136, 1026])
    #expect(library.curricula(for: .kanken).map { $0.characters.count } == [80, 240, 440, 642, 835, 1026, 2136])
    for pair in zip(school, school.dropFirst()) { #expect(pair.0.characters.isSubset(of: pair.1.characters)) }
}

@Test func jlptIncludesEasierLevels() throws {
    let sets = try CurriculumLibrary.bundled().curricula(for: .jlpt)
    #expect(sets.map(\.title) == ["N5", "N4", "N3", "N2", "N1"])
    #expect(sets.map { $0.characters.count } == [79, 245, 612, 979, 2211])
    for pair in zip(sets, sets.dropFirst()) { #expect(pair.0.characters.isSubset(of: pair.1.characters)) }
}

@Test func coverageIncludesOutsideCatalogAndIgnoresVocabulary() {
    let curriculum = Curriculum(id: "test", title: "Test", characters: ["一", "二", "三", "四"])
    let subjects = [StudySubject(id: 1, characters: "一", meaning: "One"),
                    StudySubject(id: 2, characters: "二", meaning: "Two"),
                    StudySubject(id: 3, characters: "三", meaning: "Three"),
                    StudySubject(id: 4, characters: "四", meaning: "Four", kind: .vocabulary)]
    let assignments = [StudyAssignment(subjectID: 1, srsStageNumber: 5), StudyAssignment(subjectID: 2, srsStageNumber: 1), StudyAssignment(subjectID: 4, srsStageNumber: 9)]
    let result = CurriculumCoverage(curriculum: curriculum, subjects: subjects, assignments: assignments)
    #expect(result.reached == 1 && result.learning == 1 && result.notStarted == 1 && result.outsideCatalog == 1)
    #expect(result.fraction == 0.25)
    #expect(Set(result.remaining) == ["二", "三", "四"])
    let burned = CurriculumCoverage(curriculum: curriculum, subjects: subjects, assignments: assignments, threshold: 9)
    #expect(burned.reached == 0 && burned.learning == 2)
}

@Test func duplicateAssignmentsAndCanonicalVariantsCountOnce() {
    let curriculum = Curriculum(id: "variant", title: "Variant", characters: ["神", "神"])
    let subjects = [StudySubject(id: 1, characters: "神", meaning: "God"), StudySubject(id: 2, characters: "神", meaning: "God")]
    let result = CurriculumCoverage(curriculum: curriculum, subjects: subjects,
        assignments: [.init(subjectID: 1, srsStageNumber: 2), .init(subjectID: 1, srsStageNumber: 9), .init(subjectID: 2, srsStageNumber: 5)])
    #expect(result.total == 1 && result.reached == 1 && result.remaining.isEmpty)
}

@Test func emptyReferenceDoesNotDivideByZero() {
    let result = CurriculumCoverage(curriculum: Curriculum(id: "empty", title: "Empty", characters: []), subjects: [], assignments: [])
    #expect(result.fraction == 0)
}
