import Foundation
import StudyCore
import Testing

struct StudyMistakeArchiveTests {
  @Test func nativeRoundTripUsesStableIdentityAndCanonicalMaximums() throws {
    let values: [Int64: Int64] = [2: 2_000_000_000, 1: 1_999_999_999, 999_999: Int64.max]
    let archive = try StudyMistakeArchive(accountID: "verified-account", values: values)
    let data = try archive.encoded()
    #expect(data.starts(with: Data("bplist00".utf8)))
    #expect(try StudyMistakeArchive(data: data, accountID: "verified-account") == archive)
    #expect(StudyMistakeArchive.merge(values, [1: 7, 2: 2_000_000_001])[2] == 2_000_000_001)
    #expect(StudyMistakeArchive.merge(values, [1: 7])[1] == 1_999_999_999)
    #expect(
      try StudyMistakeArchive.key(accountID: "verified-account")
        == "usagiunagi.mistakes.v1.verified-account")
    #expect(throws: StudyMistakeError.self) {
      try StudyMistakeArchive(data: data, accountID: "other")
    }
    #expect(throws: StudyMistakeError.self) { try StudyMistakeArchive.key(accountID: "") }
    #expect(throws: StudyMistakeError.self) {
      try StudyMistakeArchive.key(accountID: String(repeating: "🐰", count: 70))
    }
  }
  @Test func malformedFutureDuplicateAndOversizedDocumentsNeverBecomeEmptyHistory() throws {
    let invalid: [[String: Any]] = [
      ["formatVersion": 2, "accountID": "a", "entries": []],
      ["formatVersion": 1, "accountID": "a", "entries": [["subjectID": 1, "timestamp": -1]]],
      ["formatVersion": 1, "accountID": "a", "entries": [["subjectID": 0, "timestamp": 1]]],
      [
        "formatVersion": 1, "accountID": "a",
        "entries": [["subjectID": 1, "timestamp": 1], ["subjectID": 1, "timestamp": 2]],
      ],
      ["formatVersion": 1, "entries": []],
    ]
    for value in invalid {
      let data = try PropertyListSerialization.data(
        fromPropertyList: value, format: .binary, options: 0)
      #expect(throws: (any Error).self) { try StudyMistakeArchive(data: data, accountID: "a") }
    }
    #expect(throws: (any Error).self) {
      try StudyMistakeArchive(data: Data("broken".utf8), accountID: "a")
    }
    #expect(throws: StudyMistakeError.self) {
      try StudyMistakeArchive(
        data: Data(repeating: 0, count: StudyMistakeArchive.maximumBytes + 1), accountID: "a")
    }
  }
  @Test func unknownNativeFieldsAtEveryObjectLevelRejectTheWholeDocument() throws {
    let entry: [String: Any] = ["subjectID": 1, "timestamp": 10]
    let valid: [String: Any] = ["formatVersion": 1, "accountID": "a", "entries": [entry]]
    var top = valid
    top["futureField"] = ["nested": [1, 2, 3]]
    var first = entry
    first["futureField"] = "unrecognized"
    var second = entry
    second["subjectID"] = 2
    second["futureField"] = ["nested": "retained source"]
    let unknown: [[String: Any]] = [
      top,
      ["formatVersion": 1, "accountID": "a", "entries": [first]],
      ["formatVersion": 1, "accountID": "a", "entries": [entry, second]],
    ]
    for value in unknown {
      let data = try PropertyListSerialization.data(
        fromPropertyList: value, format: .binary, options: 0)
      #expect(throws: StudyMistakeError.self) {
        try StudyMistakeArchive(data: data, accountID: "a")
      }
      #expect(throws: StudyMistakeError.self) {
        try PropertyListDecoder().decode(StudyMistakeArchive.self, from: data)
      }
    }
    let data = try PropertyListSerialization.data(
      fromPropertyList: valid, format: .binary, options: 0)
    #expect(try StudyMistakeArchive(data: data, accountID: "a").values == [1: 10])
  }
  @Test func legacyInterpretationKeepsTimeZoneCalendarAndUnresolvedSourceTextExplicit() throws {

    let text = "2026-10-20 12:00:00"
    let utc = context(zone: "UTC")
    let tokyo = context(zone: "Asia/Tokyo")
    let a = StudyLegacyMistakes(originals: ["1": text], context: utc)
    let b = StudyLegacyMistakes(originals: ["1": text], context: tokyo)
    #expect(try #require(a.values[1]) - #require(b.values[1]) == 9 * 3600)
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = TimeZone(secondsFromGMT: 0)!
    let old = StudyLegacyMistakes(
      originals: ["1": "2569-10-20 12:00:00"],
      context: .init(locale: Locale(identifier: "en_US"), calendar: buddhist))
    #expect(old.values == a.values)
    let raw = ["1": "not a date", "future-kind": text, "2147483648": text]
    let unresolved = StudyLegacyMistakes(originals: raw, context: utc)
    #expect(unresolved.originals == raw && unresolved.unresolvedKeys.count == 3)
    let updated = try #require(
      try unresolved.updatedData(merging: [1: 2_000_000_000, 2: 2_000_000_000]))
    let restored = try StudyLegacyMistakes(data: updated, context: utc)
    #expect(restored.originals["1"] == "not a date" && restored.originals["future-kind"] == text)
    #expect(restored.originals["2147483648"] == text && restored.values[2] == 2_000_000_000)
    #expect(throws: (any Error).self) {
      try StudyLegacyMistakes(data: Data("broken".utf8), context: utc)
    }
  }
  @Test func sameSecondTiesDSTAndFutureHintsDoNotBecomeFreshMistakes() throws {
    let utc = context(zone: "UTC")
    let legacy = StudyLegacyMistakes(originals: ["1": "2026-10-20 12:00:00"], context: utc)
    #expect(try legacy.updatedData(merging: legacy.values) == nil)
    #expect(try legacy.updatedData(merging: [1: Int64.max]) == nil)
    let gap = StudyLegacyMistakes(
      originals: ["1": "2026-03-08 02:30:00"], context: context(zone: "America/New_York"))
    #expect(gap.unresolvedKeys == ["1"])
    let fold = StudyLegacyMistakes(
      originals: ["1": "2026-11-01 01:30:00"], context: context(zone: "America/New_York"))
    #expect(fold.originals["1"] == "2026-11-01 01:30:00")
    #expect(fold.values[1] != nil)
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    var source = LegacyStudyExport(schemaVersion: 15, profile: .init(username: "fixture"))
    source.profile.level = 1
    source.profile.maxLevelGranted = 3
    for (id, timestamp) in [
      (Int64(1), Int64(2_000_000_000 - 86_400)), (2, 2_000_000_000 - 86_401), (3, 2_000_000_001),
    ] {
      var subject = CatalogSubject(id: id, kind: .kanji)
      subject.level = 1
      var assignment = CatalogAssignment(id: id + 100, subjectID: id, kind: .kanji)
      assignment.startedAt = 1
      assignment.availableAt = 1
      assignment.srsStage = 3
      source.subjects.append(subject)
      source.assignments.append(assignment)
      source.progress.append(
        .init(
          subjectID: id, level: 1, srsStage: 3, kind: .kanji,
          lastMistakeLocalTime: nil, legacyRevision: 0, lastMistakeAt: timestamp))
    }
    for zone in ["UTC", "America/New_York", "Asia/Tokyo"] {
      let availability = StudyAvailability(
        account: .init(legacy: source), subjects: source.subjects,
        assignments: source.assignments, now: now, calendar: context(zone: zone).calendar)
      #expect(availability.practice(.recentMistakes).map(\.subjectID) == [1])
    }
    let rollback = StudyAvailability(
      account: .init(legacy: source), subjects: source.subjects,
      assignments: source.assignments, now: now.addingTimeInterval(-172_800))
    #expect(rollback.practice(.recentMistakes).isEmpty)
  }
  private func context(zone: String) -> StudyLegacyMistakeContext {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return .init(locale: Locale(identifier: "en_US_POSIX"), calendar: calendar)
  }
}
