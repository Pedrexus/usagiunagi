import Foundation
import StudyTestSupport
import Testing

@testable import StudyCore

struct DownloadTests {
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
