import Foundation
import StudyTestSupport
import Testing

@testable import StudyCore

struct DownloadTests {
  @Test func cachedSubjectsMergeChangesAndPreserveMicrosecondWatermarks() async throws {
    let server = SubjectCacheFixture()
    let client = WaniKaniClient { try await server.respond($0) }
    let full = try await client.download(token: "fixture")
    let key = try #require(full.cursors.first { $0.value == DownloadFixture.date }?.key)
    #expect(full.subjects.count == 5 && full.cursors.count == 3)
    await server.use(.changes)
    let changed = try await client.download(
      token: "fixture", subjects: full.subjects, cursors: full.cursors)
    #expect(changed.subjects.map(\.id) == [1, 2, 3, 4, 5, 6])
    #expect(changed.subjects.first?.japanese == "更新" && changed.subjects.first?.hiddenAt != nil)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    #expect(
      try encoder.encode(full.subjects.filter { $0.id != 1 })
        == encoder.encode(changed.subjects.filter { $0.id != 1 && $0.id != 6 }))
    #expect(changed.cursors[key] == SubjectCacheFixture.changedAt)
    #expect(changed.cursors[key + ":full"] == full.cursors[key + ":full"])
    await server.use(.unchanged)
    let unchanged = try await client.download(
      token: "fixture", subjects: changed.subjects, cursors: changed.cursors)
    #expect(try encoder.encode(unchanged.subjects) == encoder.encode(changed.subjects))
    #expect(unchanged.cursors == changed.cursors)
    #expect(await server.watermarks == [nil, DownloadFixture.date, SubjectCacheFixture.changedAt])
  }

  @Test(arguments: [
    "missing", "count", "legacy", "expired", "future", "endpoint", "grant", "empty", "duplicates",
    "nonpositive",
  ])
  func invalidOrChangedCacheScopeForcesACompleteSubjectRead(_ fault: String) async throws {
    let server = SubjectCacheFixture()
    var client: any WaniKaniService = WaniKaniClient { try await server.respond($0) }
    let full = try await client.download(token: "fixture")
    let key = try #require(full.cursors.first { $0.value == DownloadFixture.date }?.key)
    var cursors = full.cursors
    var subjects = full.subjects
    if fault == "missing" { cursors[key] = nil }
    if fault == "count" { cursors[key + ":count"] = "999" }
    if fault == "legacy" { cursors = ["subjects_updated_after": DownloadFixture.date] }
    if fault == "expired" {
      subjects.append(.init(id: 999, kind: .kanji))
      cursors[key + ":count"] = String(subjects.count)
      cursors[key + ":full"] = "2000-01-01T00:00:00Z"
    }
    if fault == "future" { cursors[key + ":full"] = "2999-01-01T00:00:00Z" }
    if fault == "endpoint" {
      client = try client.reconfigured(baseURL: URL(string: "https://fixture.example/v2")!)
    }
    if fault == "grant" { await server.use(.free) }
    if fault == "empty" { subjects = [] }
    if fault == "duplicates" {
      subjects.append(subjects[0])
      cursors[key + ":count"] = String(subjects.count)
    }
    if fault == "nonpositive" { subjects[0] = .init(id: -1, kind: .kanji) }
    let result = try await client.download(token: "fixture", subjects: subjects, cursors: cursors)
    #expect(await server.watermarks == [nil, nil])
    #expect(result.subjects.map(\.id) == full.subjects.map(\.id) && result.cursors.count == 3)
  }

  @Test(arguments: [
    SubjectCacheFixture.Phase.failedPage, .laterCategoryFailure, .duplicates, .missingStamp,
    .backwardsStamp, .malformedStamp,
  ])
  func invalidPartialDownloadsNeverPublishACompleteCatalog(_ phase: SubjectCacheFixture.Phase)
    async throws
  {
    let server = SubjectCacheFixture()
    let client = WaniKaniClient { try await server.respond($0) }
    let full = try await client.download(token: "fixture")
    await server.use(phase)
    do {
      _ = try await client.download(
        token: "fixture", subjects: full.subjects, cursors: full.cursors)
      Issue.record("An incomplete or invalid download was published")
    } catch let error as URLError {
      #expect(phase == .failedPage || phase == .laterCategoryFailure)
      #expect(error.code == .networkConnectionLost)
    } catch let error as WaniKaniClient.APIError {
      #expect(phase != .failedPage && phase != .laterCategoryFailure)
      guard case .invalidResponse = error else {
        Issue.record("Unexpected API failure: \(error)")
        return
      }
    }
  }

  @Test func changingPaginationMetadataKeepsTheFirstServerWatermark() async throws {
    let server = SubjectCacheFixture()
    let client = WaniKaniClient { try await server.respond($0) }
    await server.use(.pagination)
    let full = try await client.download(token: "fixture")
    #expect(full.subjects.count == 5 && full.cursors.values.contains(DownloadFixture.date))
    #expect(!full.cursors.values.contains(SubjectCacheFixture.changedAt))
    await server.use(.unchanged)
    _ = try await client.download(token: "fixture", subjects: full.subjects, cursors: full.cursors)
    #expect(await server.watermarks == [nil, nil, DownloadFixture.date])
  }

  @Test(arguments: [
    ("2018-08-05T11:08:39.431000Z", Int64(1_533_467_319)),
    ("2018-08-05T11:08:39.431Z", 1_533_467_319),
    ("2018-08-05T11:08:39.000000Z", 1_533_467_319),
    ("2018-08-05T11:08:39.000Z", 1_533_467_319),
    ("20180805T11:08:39.431000Z", 1_533_467_319),
    ("2018-08-05T11:08:39Z", 1_533_467_319),
    ("20180805T11:08:39Z", 1_533_467_319),
    ("2018-08-05T11:08:39.431000+03:00", 1_533_456_519),
    ("2018-08-05T11:08:39.431000+0300", 1_533_456_519),
    ("2018-08-05T11:08:39.431000+03", 1_533_456_519),
    ("2018-08-05T11:08:39.431+03:00", 1_533_456_519),
    ("2018-08-05T11:08:39.431+0300", 1_533_456_519),
    ("2018-08-05T11:08:39.431+03", 1_533_456_519),
    ("2018-08-05T11:08:39+03:00", 1_533_456_519),
    ("2018-08-05T11:08:39+0300", 1_533_456_519),
    ("2018-08-05T11:08:39+03", 1_533_456_519),
  ])
  func historicalTimestampSpellingsKeepTheirWholeSecondValue(text: String, expected: Int64) throws {
    #expect(try WaniKaniClient().timestamp(text) == expected)
  }
  @Test func historicalProfileSubscriptionAndLevelDatesKeepTheirExactValues() async throws {
    let client = WaniKaniClient { request in
      if request.url?.lastPathComponent == "user" {
        var user = DownloadFixture.user
        var data = user["data"] as! [String: Any]
        data["username"] = "example_user"
        data["level"] = 5
        data["profile_url"] = "https://www.wanikani.com/users/example_user"
        data["started_at"] = "2012-05-11T00:52:18.958466Z"
        data["subscription"] = [
          "active": true, "max_level_granted": 60,
          "period_ends_at": "2018-12-11T13:32:19.485748Z",
        ]
        user["data"] = data
        return try DownloadFixture.response(request, object: user)
      }
      if request.url?.lastPathComponent == "level_progressions" {
        let row = DownloadFixture.resource(
          49392, "level_progression",
          [
            "level": 42, "created_at": "2017-03-30T08:21:51.439918Z",
            "unlocked_at": "2017-03-30T08:21:51.439918Z",
            "started_at": "2017-03-30T11:31:20.438432Z",
            "passed_at": NSNull(), "completed_at": NSNull(), "abandoned_at": NSNull(),
          ])
        return try DownloadFixture.response(request, object: DownloadFixture.collection([row]))
      }
      return try DownloadFixture.response(request)
    }
    let result = try await client.download(token: "fixture")
    #expect(result.profile.username == "example_user" && result.profile.level == 5)
    #expect(result.profile.profileURL == "https://www.wanikani.com/users/example_user")
    #expect(result.profile.subscribed && result.profile.maxLevelGranted == 60)
    #expect(
      result.profile.startedAt == 1_336_697_538
        && result.profile.subscriptionEndsAt == 1_544_535_139)
    let level = try #require(result.levels.first)
    #expect(result.levels.count == 1 && level.id == 49392 && level.level == 42)
    #expect(level.createdAt == 1_490_862_111 && level.unlockedAt == 1_490_862_111)
    #expect(level.startedAt == 1_490_873_480)
    #expect(level.passedAt == nil && level.completedAt == nil && level.abandonedAt == nil)
  }
  @Test func nanoriReadingsRetainTheirTextPrimaryFlagAndKind() async throws {
    let client = WaniKaniClient { request in
      guard request.url?.lastPathComponent == "subjects" else {
        return try DownloadFixture.response(request)
      }
      var rows = DownloadFixture.rows["subjects"]!
      var data = rows[0]["data"] as! [String: Any]
      var readings = data["readings"] as! [[String: Any]]
      readings.append([
        "reading": "かず", "primary": false, "accepted_answer": false, "type": "nanori",
      ])
      data["readings"] = readings
      rows[0]["data"] = data
      return try DownloadFixture.response(request, object: DownloadFixture.collection(rows))
    }
    let result = try await client.download(token: "fixture")
    let kanji = try #require(result.subjects.first { $0.id == 1 })
    #expect(kanji.readings.map(\.text) == ["いち", "ひと", "かず"])
    #expect(kanji.readings.map(\.kind) == [.onyomi, .kunyomi, .nanori])
    #expect(kanji.readings.map(\.isPrimary) == [true, false, false])
  }
  @Test func completeStudyContentIncludesHiddenResourcesAndSubscription() async throws {
    let result = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    #expect(
      result.profile.maxLevelGranted == 60 && result.profile.subscribed
        && result.profile.startedAt != nil)
    #expect(result.assignments.first?.level == 1 && result.assignments.first?.id == 101)
    let kanji = try #require(result.subjects.first { $0.id == 1 })
    #expect(kanji.meaningMnemonic.contains("<kanji>") && kanji.meaningHint == "Meaning hint")
    #expect(kanji.readingHint == "Reading hint" && kanji.readings.count == 2)
    #expect(
      kanji.gradingSubject.blacklistedMeanings == ["Wrong"]
        && kanji.gradingSubject.meanings.contains("Only"))
    #expect(
      kanji.componentSubjectIDs == [3] && kanji.visuallySimilarKanjiIDs == [4]
        && !kanji.visuallySimilarKanji.isEmpty)
    let kana = try #require(result.subjects.first { $0.id == 2 })
    #expect(kana.isKanaOnlyVocabulary == true && kana.readings.isEmpty)
    #expect(kana.sentences.first?.english == "Yes." && kana.audio.first?.voiceActorID == 1)
    #expect(
      kana.partOfSpeechNames == ["noun", "の adjective", "future_kind"]
        && kana.partsOfSpeech == [1, 6])
    let radical = try #require(result.subjects.first { $0.id == 3 })
    #expect(
      radical.japanese.isEmpty && radical.hasCharacterImageFile
        && radical.characterImageURL.hasSuffix(".svg"))
    #expect(result.subjects.contains { $0.id == 4 && $0.hiddenAt != nil })
    #expect(!result.snapshot.subjects.contains { $0.id == 4 })
    #expect(result.materials.first?.id == 201 && result.materials.first?.value.readingNote == "いち")
    #expect(
      result.levels.first?.completedAt != nil && result.statistics.first?.meaningMaxStreak == 5)
    #expect(result.voices.first?.description == "Tokyo accent" && result.voices.first?.gender == 2)
  }

  @Test(arguments: [
    ("milliseconds", 0.01), ("seconds", 10.0), ("minutes", 600.0), ("hours", 36000.0),
    ("days", 864000.0), ("weeks", 6048000.0),
  ])
  func systemIntervalsNormalizeToSeconds(unit: String, seconds: Double) async throws {
    let client = WaniKaniClient { request in
      if request.url?.lastPathComponent != "spaced_repetition_systems" {
        return try DownloadFixture.response(request)
      }
      var row = DownloadFixture.rows["spaced_repetition_systems"]![0]
      var data = row["data"] as! [String: Any]
      var stages = data["stages"] as! [[String: Any]]
      stages[1]["interval_unit"] = unit
      data["stages"] = stages
      row["data"] = data
      return try DownloadFixture.response(request, object: DownloadFixture.collection([row]))
    }
    let download = try await client.download(token: "fixture")
    #expect(download.systems?.first?.stages.first { $0.position == 1 }?.interval == seconds)
  }
  @Test(arguments: ["missing", "duplicate", "unit", "negative", "endpoint", "position"])
  func invalidSystemsPreventCompleteDownload(fault: String) async {
    let client = WaniKaniClient { request in
      if request.url?.lastPathComponent != "spaced_repetition_systems" {
        return try DownloadFixture.response(request)
      }
      var rows = DownloadFixture.rows["spaced_repetition_systems"]!
      var data = rows[0]["data"] as! [String: Any]
      var stages = data["stages"] as! [[String: Any]]
      if fault == "unit" { stages[1]["interval_unit"] = "months" }
      if fault == "negative" { stages[1]["interval"] = -10 }
      if fault == "endpoint" { stages[0]["interval_unit"] = "hours" }
      if fault == "position" { stages[1]["position"] = 2 }
      data["stages"] = stages
      rows[0]["data"] = data
      if fault == "missing" { rows = [] }
      if fault == "duplicate" { rows.append(rows[0]) }
      return try DownloadFixture.response(request, object: DownloadFixture.collection(rows))
    }
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await client.download(token: "fixture")
    }
  }

  @Test(arguments: [
    "count", "duplicate", "orphan", "kind", "auxiliary", "reading", "date", "image",
  ])
  func malformedFullDownloadsFailWithoutPartialResults(fault: String) async {
    let client = WaniKaniClient { request in
      let path = request.url!.lastPathComponent
      if path == "user" { return try DownloadFixture.response(request) }
      var rows = DownloadFixture.rows[path] ?? []
      if path == "subjects" {
        if fault == "duplicate" { rows.append(rows[0]) }
        if fault == "orphan" { rows.removeFirst() }
        if fault == "kind" { rows[0]["object"] = "future_subject_kind" }
        var data = rows[0]["data"] as! [String: Any]
        if fault == "auxiliary" {
          data["auxiliary_meanings"] = [["meaning": "x", "type": "unknown"]]
        }
        if fault == "reading" {
          data["readings"] = [
            ["reading": "x", "primary": true, "accepted_answer": true, "type": "unknown"]
          ]
        }
        if fault == "date" { data["hidden_at"] = "not a timestamp" }
        rows[0]["data"] = data
        if fault == "image" {
          var radical = rows[2]["data"] as! [String: Any]
          radical["character_images"] = []
          rows[2]["data"] = radical
        }
      }
      return try DownloadFixture.response(
        request,
        object: DownloadFixture.collection(
          rows,
          total: fault == "count" && path == "subjects" ? rows.count + 1 : rows.count))
    }
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await client.download(token: "fixture")
    }
  }

  @Test func olderCatalogBytesDecodeWithoutNewServerMetadata() throws {
    var subject = CatalogSubject(id: 1, kind: .kanji)
    subject.japanese = "一"
    let bytes = try JSONEncoder().encode(subject)
    let decoded = try JSONDecoder().decode(CatalogSubject.self, from: bytes)
    #expect(
      decoded.hiddenAt == nil && decoded.lessonPosition == nil
        && decoded.isKanaOnlyVocabulary == nil)
  }
  @Test func accountOnlyReadPublishesCompleteProfileAndVacationWithoutCatalogRequests() async throws
  {
    let client = WaniKaniClient { request in
      #expect(request.url?.lastPathComponent == "user")
      var user = DownloadFixture.user
      var data = user["data"] as! [String: Any]
      data["current_vacation_started_at"] = DownloadFixture.date
      user["data"] = data
      return try DownloadFixture.response(request, object: user)
    }
    let identity = try await client.account(token: "fixture")
    let profile = try #require(identity.profile)
    #expect(identity.onVacation && profile.vacationStartedAt != nil)
    #expect(profile.maxLevelGranted == 60 && profile.subscribed)
    #expect(profile.username == identity.username && profile.level == identity.level)
    #expect(profile.startedAt == identity.startedAt)
  }

}
