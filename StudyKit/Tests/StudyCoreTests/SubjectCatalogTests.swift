import Foundation
import StudyCore
import Testing

struct SubjectCatalogTests {
  private func item(
    _ id: Int64, japanese: String = "", meaning: String = "", reading: String = "",
    level: Int = 1, kind: SubjectKind = .kanji,
    status: SubjectCatalogItem.Status = .unassigned, excluded: Bool = false
  ) -> SubjectCatalogItem {
    var subject = CatalogSubject(id: id, kind: kind)
    subject.level = level
    subject.japanese = japanese
    subject.meanings = [.init(meaning, role: .primary)]
    if !reading.isEmpty { subject.readings = [.init(reading, isPrimary: true, kind: .unknown)] }
    return .init(subject: subject, status: status, isExcluded: excluded)
  }

  @Test func exactMatchesSurviveTheLimitBeforePrefixesAndSubstrings() async throws {
    let prefixes = (1...60).map { item(Int64($0), meaning: "One \($0)") }
    let values = prefixes + [item(99, meaning: "One", level: 60), item(100, meaning: "Someone")]
    var query = SubjectCatalogQuery()
    query.text = "  ONE\n"
    let results = try await query.results(in: values, limit: 50)
    #expect(results.count == 50 && results.first?.id == 99)
    #expect(!results.contains { $0.id == 100 })
    #expect(try await query.results(in: values).last?.id == 100)
  }

  @Test func japaneseAndRomajiExactMatchesRankBeforeLongerReadings() async throws {
    let values = [
      item(1, japanese: "私自身", meaning: "Personally", reading: "わたしじしん"),
      item(2, japanese: "私", meaning: "I", reading: "わたし", level: 2),
    ]
    for text in ["私", "watashi", "わたし"] {
      var query = SubjectCatalogQuery()
      query.text = text
      #expect(try await query.results(in: values).map(\.id) == [2, 1])
    }
    var query = SubjectCatalogQuery()
    query.text = "じしん"
    #expect(try await query.results(in: values).map(\.id) == [1])
  }

  @Test func levelKindAndProgressFiltersComposeWithoutInventingAssignments() async throws {
    let values = [
      item(1, status: .locked), item(2, status: .lesson),
      item(
        3, kind: .vocabulary, status: .studying(.apprentice4, reviewAt: nil, guruAt: nil),
        excluded: true),
      item(4, level: 2, status: .studying(.guru2, reviewAt: nil, guruAt: nil)), item(5),
    ]
    var query = SubjectCatalogQuery()
    for (scope, expected): (SubjectCatalogScope, [Int64]) in [
      (.locked, [1]), (.lessons, [2]), (.apprentice, [3]), (.guru, [4]), (.excluded, [3]),
    ] {
      query.scope = scope
      #expect(try await query.results(in: values).map(\.id) == expected)
    }
    query.scope = .all
    query.kind = .kanji
    query.level = 1
    #expect(try await query.results(in: values).map(\.id) == [1, 2, 5])
    query.text = "not present"
    #expect(try await query.results(in: values).isEmpty)
  }

  @Test func remainingOrdersDueWorkLessonsHigherStagesAndLockedItems() {
    let now = Date(timeIntervalSince1970: 100)
    let values = [
      item(1, status: .locked), item(2, status: .lesson),
      item(3, status: .studying(.apprentice1, reviewAt: now, guruAt: nil)),
      item(4, status: .studying(.apprentice4, reviewAt: now.addingTimeInterval(10), guruAt: nil)),
      item(5, status: .studying(.apprentice2, reviewAt: now.addingTimeInterval(10), guruAt: nil)),
    ]
    #expect(SubjectCatalogOrder.remaining.sorted(values, now: now).map(\.id) == [3, 2, 4, 5, 1])
    #expect(SubjectCatalogOrder.level.sorted(values, now: now).map(\.id) == [2, 3, 5, 4, 1])
    #expect(SubjectCatalogOrder.results.sorted(values, now: now).map(\.id) == values.map(\.id))
  }

  @MainActor @Test func canceledSearchDoesNotReturnStaleResults() async {
    let task = Task { try await SubjectCatalogQuery().results(in: [item(1)]) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
