import Foundation
import StudyTestSupport
import Testing

@testable import StudyCore

@Test func readerFollowsPagesAndPreservesQuestionTypes() async throws {
  let reader = WaniKaniClient { request in
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
    #expect(request.value(forHTTPHeaderField: "Wanikani-Revision") == "20170710")
    let url = request.url!
    if url.path == "/v2/subjects" {
      let second = url.query?.contains("page_after_id") == true
      let rows = DownloadFixture.rows["subjects"]!
      return try DownloadFixture.response(
        request,
        object: DownloadFixture.collection(
          second ? Array(rows.dropFirst()) : [rows[0]],
          next: second ? nil : "https://api.wanikani.com/v2/subjects?page_after_id=1",
          total: rows.count))
    }
    return try DownloadFixture.response(request)
  }
  let result = try await reader.fetch(token: "fixture-token")
  #expect(result.subjects.map(\.kind) == [.kanji, .vocabulary, .radical, .vocabulary])
  #expect(result.subjects.first?.readings == ["いち", "ひと"])
  #expect(result.assignments.first?.hasAvailableAt == true)
  #expect(result.accountID == "fixture-user-id")
  #expect(result.currentLevel == 12 && !result.onVacation && !result.isSample)
}

@Test func readerRejectsForeignPaginationBeforeSendingToken() async {
  let reader = WaniKaniClient { request in
    #expect(request.url?.host == "api.wanikani.com")
    if request.url?.path == "/v2/user" { return try DownloadFixture.response(request) }
    return try DownloadFixture.response(
      request, object: DownloadFixture.collection([], next: "https://other.invalid/v2/subjects"))
  }
  await #expect(throws: WaniKaniClient.APIError.self) {
    try await reader.fetch(token: "fixture-token")
  }
}

@Test func readerRejectsPaginationLoop() async {
  let reader = WaniKaniClient { request in
    if request.url?.path == "/v2/subjects" {
      return try DownloadFixture.response(
        request, object: DownloadFixture.collection([], next: request.url!.absoluteString))
    }
    return try DownloadFixture.response(request)
  }
  await #expect(throws: WaniKaniClient.APIError.self) {
    try await reader.fetch(token: "fixture-token")
  }
}

@Test func failedEndpointDoesNotPublishPartialSnapshot() async {
  let reader = WaniKaniClient { request in
    if request.url?.path == "/v2/assignments" {
      return try DownloadFixture.response(request, object: [:], status: 401)
    }
    return try DownloadFixture.response(request)
  }
  await #expect(throws: WaniKaniClient.APIError.self) {
    try await reader.fetch(token: "fixture-token")
  }
}

@Test func readerPreservesVacationAndRejectsMissingAccountIdentity() async throws {
  for validIdentity in [true, false] {
    let reader = WaniKaniClient { request in
      if request.url?.path == "/v2/user" {
        var user = DownloadFixture.user
        var data = user["data"] as! [String: Any]
        data["id"] = validIdentity ? "account-id" : nil
        data["current_vacation_started_at"] = DownloadFixture.date
        user["data"] = data
        return try DownloadFixture.response(request, object: user)
      }
      return try DownloadFixture.response(request)
    }
    if validIdentity {
      let snapshot = try await reader.fetch(token: "fixture-token")
      #expect(snapshot.onVacation && snapshot.accountID == "account-id")
    } else {
      await #expect(throws: (any Error).self) { try await reader.fetch(token: "fixture-token") }
    }
  }
}
