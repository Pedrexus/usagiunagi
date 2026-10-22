import CryptoKit
import Foundation
import Testing

@testable import StudyCore

@Test func currentSchoolAndJoyoTotals() throws {
  let library = try CurriculumLibrary.bundled()
  let school = library.curricula(for: .school)
  #expect(school.map { $0.characters.count } == [80, 240, 440, 642, 835, 1026])
  #expect(library.curricula(for: .joyo).map { $0.characters.count } == [2136, 1026])
  let kanken = library.curricula(for: .kanken)
  #expect(
    kanken.map { $0.characters.count } == [80, 240, 440, 642, 835, 1026, 1339, 1623, 1951, 2136])
  #expect(
    kanken.map(\.id) == [
      "kanken10", "kanken9", "kanken8", "kanken7", "kanken6", "kanken5", "kanken4", "kanken3",
      "kankenpre2", "kanken2",
    ])
  #expect(
    kanken.map(\.title) == [
      "Level 10", "Level 9", "Level 8", "Level 7", "Level 6", "Level 5", "Level 4", "Level 3",
      "Pre-2", "Level 2",
    ])
  for pair in zip(kanken, kanken.dropFirst()) {
    #expect(pair.0.characters.isSubset(of: pair.1.characters))
  }
  for pair in zip(school, school.dropFirst()) {
    #expect(pair.0.characters.isSubset(of: pair.1.characters))
  }
  for (elementary, grade) in zip(kanken.prefix(6), school) {
    #expect(elementary.characters == grade.characters)
  }
  #expect(kanken.last?.characters == library.curricula(for: .joyo).first?.characters)
}

@Test func bundledCurriculumProvenanceIsTheReviewedSnapshot() throws {
  let library = try CurriculumLibrary.bundled()
  #expect(library.version == 2)
  #expect(library.kanjidicDate == "2026-10-17")
  #expect(library.jlptRevision == "00fd7079c3890f430759536f91aa5e854ec0ca4f")
  #expect(
    library.kankenDocumentSHA256
      == "8c7513a4ecfc7d6ca2b8f8aa71313b9097e972bac7a43f8a568fe99a9a1d7285")
}

// Exact additions from the reviewed official 2020 PDF, pages 8–13. Hash sorted UTF-8
// characters with one newline each so changing membership cannot hide behind unchanged totals.
@Test(arguments: [
  (
    KankenLevel.four, 313,
    "11371818ab4bb114c5af33ae7a49c1ccc17692467847a687b9648111ddd2f9a1", "侵握麗丹僧隷"
  ),
  (
    KankenLevel.three, 284,
    "384de688a81165caf3ba690c1c0d1520c5b22ebb3f37bc6c719ee60d86a48be5", "婿哀励奪譲嫁"
  ),
  (
    KankenLevel.preTwo, 328,
    "fcab3969032bd95555e28f18531267123cbc48e9fda44088e8a1b9028e1f36b9", "詔亜寮旋朕竜"
  ),
])
func officialIntermediateKankenAllocations(
  level: KankenLevel, count: Int, digest: String, samples: String
) throws {
  let library = try CurriculumLibrary.bundled()
  let curricula = library.curricula(for: .kanken)
  let index = try #require(KankenLevel.allCases.firstIndex(of: level))
  let addition = curricula[index].characters.subtracting(curricula[index - 1].characters)
  #expect(addition.count == count)
  let canonical = addition.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    .map { "\($0)\n" }.joined()
  let actualDigest = SHA256.hash(data: Data(canonical.utf8))
    .map { String(format: "%02x", $0) }.joined()
  #expect(actualDigest == digest)
  for character in samples.map(String.init) {
    #expect(library.entries[character]?.kanken == level)
    #expect(addition.contains(character))
  }
  for character in ["鬱", "𠮟"] {
    #expect(library.entries[character]?.kanken == .two)
    #expect(!curricula[index].characters.contains(character))
  }
}

@Test func jlptIncludesEasierLevels() throws {
  let sets = try CurriculumLibrary.bundled().curricula(for: .jlpt)
  #expect(sets.map(\.title) == ["N5", "N4", "N3", "N2", "N1"])
  #expect(sets.map { $0.characters.count } == [79, 245, 612, 979, 2211])
  for pair in zip(sets, sets.dropFirst()) {
    #expect(pair.0.characters.isSubset(of: pair.1.characters))
  }
}

@Test func coverageIncludesOutsideCatalogAndIgnoresVocabulary() {
  let curriculum = Curriculum(id: "test", title: "Test", characters: ["一", "二", "三", "四"])
  let subjects = [
    StudySubject(id: 1, characters: "一", meaning: "One"),
    StudySubject(id: 2, characters: "二", meaning: "Two"),
    StudySubject(id: 3, characters: "三", meaning: "Three"),
    StudySubject(id: 4, characters: "四", meaning: "Four", kind: .vocabulary),
  ]
  let assignments = [
    StudyAssignment(subjectID: 1, srsStageNumber: 5),
    StudyAssignment(subjectID: 2, srsStageNumber: 1),
    StudyAssignment(subjectID: 4, srsStageNumber: 9),
  ]
  let result = CurriculumCoverage(
    curriculum: curriculum, subjects: subjects, assignments: assignments)
  #expect(
    result.reached == 1 && result.learning == 1 && result.notStarted == 1
      && result.outsideCatalog == 1)
  #expect(result.fraction == 0.25)
  #expect(Set(result.remaining) == ["二", "三", "四"])
  let burned = CurriculumCoverage(
    curriculum: curriculum, subjects: subjects, assignments: assignments, threshold: 9)
  #expect(burned.reached == 0 && burned.learning == 2)
}

@Test(arguments: [(1, 4, 0), (5, 3, 1), (7, 2, 2), (9, 1, 3)])
func officialKankenCoverageKeepsFullScopeAtEveryMilestone(
  threshold: Int, reached: Int, learning: Int
) throws {
  let curriculum = try #require(
    CurriculumLibrary.bundled().curricula(for: .kanken).first { $0.id == "kanken4" })
  let result = CurriculumCoverage(
    curriculum: curriculum,
    subjects: [
      .init(id: 1, characters: "一", meaning: "One"),
      .init(id: 2, characters: "侵", meaning: "Invade"),
      .init(id: 3, characters: "握", meaning: "Grip"),
      .init(id: 4, characters: "麗", meaning: "Lovely"),
      .init(id: 5, characters: "僧", meaning: "Priest"),
      .init(id: 6, characters: "丹", meaning: "Rust colored", kind: .vocabulary),
      .init(id: 7, characters: "隷", meaning: "Servant", kind: .radical),
      .init(id: 8, characters: "婿", meaning: "Bridegroom"),
    ],
    assignments: [
      .init(subjectID: 1, srsStageNumber: 1),
      .init(subjectID: 2, srsStageNumber: 5),
      .init(subjectID: 3, srsStageNumber: 7),
      .init(subjectID: 4, srsStageNumber: 9),
      .init(subjectID: 6, srsStageNumber: 9),
      .init(subjectID: 7, srsStageNumber: 9),
      .init(subjectID: 8, srsStageNumber: 9),
    ], threshold: threshold)
  #expect(result.total == 1339)
  #expect(result.reached == reached)
  #expect(result.learning == learning)
  #expect(result.notStarted == 1)
  #expect(result.outsideCatalog == 1334)
  #expect(result.remaining.count == 1339 - reached)
  #expect(result.remaining.contains("丹") && result.remaining.contains("隷"))
  #expect(!result.remaining.contains("婿"))
}

@Test func duplicateAssignmentsAndCanonicalVariantsCountOnce() {
  let curriculum = Curriculum(id: "variant", title: "Variant", characters: ["神", "神"])
  let subjects = [
    StudySubject(id: 1, characters: "神", meaning: "God"),
    StudySubject(id: 2, characters: "神", meaning: "God"),
  ]
  let result = CurriculumCoverage(
    curriculum: curriculum, subjects: subjects,
    assignments: [
      .init(subjectID: 1, srsStageNumber: 2), .init(subjectID: 1, srsStageNumber: 9),
      .init(subjectID: 2, srsStageNumber: 5),
    ])
  #expect(result.total == 1 && result.reached == 1 && result.remaining.isEmpty)
}

@Test func curriculumCoverageRejectsUnsupportedStagesBeforeCombiningDuplicates() {
  let result = CurriculumCoverage(
    curriculum: Curriculum(id: "stages", title: "Stages", characters: ["一", "二", "三", "四", "五"]),
    subjects: [
      .init(id: 1, characters: "一", meaning: "One"),
      .init(id: 2, characters: "二", meaning: "Two"),
      .init(id: 3, characters: "三", meaning: "Three"),
      .init(id: 4, characters: "四", meaning: "Four"),
      .init(id: 5, characters: "五", meaning: "Five"),
    ],
    assignments: [
      .init(subjectID: 1, srsStageNumber: -1),
      .init(subjectID: 2, srsStageNumber: 0),
      .init(subjectID: 3, srsStageNumber: 10),
      .init(subjectID: 4, srsStageNumber: 3),
      .init(subjectID: 4, srsStageNumber: Int.max),
      .init(subjectID: 5, srsStageNumber: 9),
    ])
  #expect(result.reached == 1)
  #expect(result.learning == 1)
  #expect(result.notStarted == 3)
  #expect(result.outsideCatalog == 0)
  #expect(result.remaining == ["一", "三", "二", "四"].sorted())
  #expect(result.fraction == 0.2)
}

@Test(arguments: [Int.min, 0, 1, 5, 7, 9, 10, Int.max])
func curriculumCoverageThresholdUsesOnlyStudyMilestones(_ threshold: Int) {
  let result = CurriculumCoverage(
    curriculum: Curriculum(id: "bounds", title: "Bounds", characters: ["一", "二", "三", "四"]),
    subjects: [
      .init(id: 1, characters: "一", meaning: "One"),
      .init(id: 2, characters: "二", meaning: "Two"),
      .init(id: 3, characters: "三", meaning: "Three"),
    ],
    assignments: [
      .init(subjectID: 1, srsStageNumber: 1),
      .init(subjectID: 2, srsStageNumber: 9),
    ], threshold: threshold)
  #expect(result.reached == (threshold <= 1 ? 2 : 1))
  #expect(result.learning == (threshold <= 1 ? 0 : 1))
  #expect(result.notStarted == 1)
  #expect(result.outsideCatalog == 1)
  #expect(result.remaining.contains("三") && result.remaining.contains("四"))
  #expect(
    result.reached + result.learning + result.notStarted + result.outsideCatalog == result.total)
}

@Test func emptyReferenceDoesNotDivideByZero() {
  let result = CurriculumCoverage(
    curriculum: Curriculum(id: "empty", title: "Empty", characters: []), subjects: [],
    assignments: [])
  #expect(result.fraction == 0)
}

@Test func coverageKeepsPendingKanjiDistinctUntilSyncConfirmsTheirStage() throws {
  let curriculum = Curriculum(id: "pending", title: "Pending", characters: ["一", "二", "三", "四"])
  let subjects = [
    StudySubject(id: 1, characters: "一", meaning: "One"),
    StudySubject(id: 2, characters: "二", meaning: "Two"),
    StudySubject(id: 3, characters: "三", meaning: "Three"),
    StudySubject(id: 4, characters: "四", meaning: "Four", kind: .vocabulary),
    StudySubject(id: 5, characters: "五", meaning: "Five"),
  ]
  let pending = CurriculumCoverage(
    curriculum: curriculum, subjects: subjects,
    assignments: [.init(subjectID: 3, srsStageNumber: 2)], pendingSubjectIDs: [1, 4, 5])
  #expect(pending.awaitingSync == 1)
  #expect(pending.notStarted == 1 && pending.learning == 1 && pending.outsideCatalog == 1)
  #expect(pending.reached == 0 && pending.remaining.count == 4)
  #expect(
    pending.awaitingSync + pending.notStarted + pending.learning + pending.outsideCatalog
      == pending.total)
  let synced = CurriculumCoverage(
    curriculum: curriculum, subjects: subjects,
    assignments: [.init(subjectID: 1, srsStageNumber: 5), .init(subjectID: 3, srsStageNumber: 2)])
  #expect(synced.awaitingSync == 0 && synced.reached == 1 && synced.notStarted == 1)
  #expect(!synced.remaining.contains("一"))
}

@Test func pendingSubjectProjectionDoesNotChangePersistedSnapshotPayload() throws {
  func snapshot(pending: Set<Int64>) -> StudySnapshot {
    StudySnapshot(
      username: "Fixture", currentLevel: 1, assignments: [], statistics: [], levels: [],
      subjects: [], savedAt: Date(timeIntervalSince1970: 0), pendingReviews: 1,
      pendingSubjectIDs: pending)
  }
  let encoder = JSONEncoder()
  encoder.outputFormatting = .sortedKeys
  let encoded = try encoder.encode(snapshot(pending: [1]))
  #expect(encoded == (try encoder.encode(snapshot(pending: []))))
  #expect(try JSONDecoder().decode(StudySnapshot.self, from: encoded).pendingSubjectIDs.isEmpty)
}
