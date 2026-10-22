import Foundation
import StudyCore
import Testing

struct StudyMistakeArchiveTests {
  @Test func cloudWindowExpiresOnlyOldHintsAtTheExactBoundary() {
    let now = Date(timeIntervalSince1970: 1_792_497_600)
    let values: [Int64: Int64] = [
      1: 1_792_411_199, 2: 1_792_411_200, 3: 1_792_497_601, 4: Int64.max,
    ]
    #expect(
      StudyMistakeArchive.recentValues(values, now: now) == [
        2: 1_792_411_200, 3: 1_792_497_601, 4: Int64.max,
      ])
  }
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
  @Test func futureEpochsAndClockRollbackDoNotBecomeFreshMistakes() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    var source = StudyDownload(accountID: "fixture", profile: .init(username: "fixture"))
    var progress: [SubjectProgress] = []
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
      progress.append(
        .init(
          subjectID: id, level: 1, srsStage: 3, kind: .kanji,
          lastMistakeAt: timestamp))
    }
    let availability = StudyAvailability(
      account: .init(download: source, progress: progress), subjects: source.subjects,
      assignments: source.assignments, now: now)
    #expect(availability.practice(.recentMistakes).map(\.subjectID) == [1])
    let rollback = StudyAvailability(
      account: .init(download: source, progress: progress), subjects: source.subjects,
      assignments: source.assignments, now: now.addingTimeInterval(-172_800))
    #expect(rollback.practice(.recentMistakes).isEmpty)
  }
}
