import Foundation
import StudyTestSupport
import Testing

@testable import StudyCore

private actor TokenServer {
  var requests = [URLRequest]()
  let responseURL: URL?
  let status: Int
  let message: String
  let next: String?
  let startedAt: String?
  init(
    responseURL: URL? = nil, status: Int = 200, message: String = "", next: String? = nil,
    startedAt: String? = DownloadFixture.date
  ) {
    self.responseURL = responseURL
    self.status = status
    self.message = message
    self.next = next
    self.startedAt = startedAt
  }
  func respond(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    var object: [String: Any] = DownloadFixture.user
    var user = object["data"] as! [String: Any]
    user["started_at"] = startedAt as Any? ?? NSNull()
    object["data"] = user
    if status != 200 { object = ["error": message, "code": status] }
    if request.url?.lastPathComponent == "assignments" {
      object = [
        "object": "collection", "total_count": 0, "data": [],
        "pages": ["next_url": next as Any? ?? NSNull()],
      ]
    }
    return (
      try JSONSerialization.data(withJSONObject: object),
      HTTPURLResponse(
        url: responseURL ?? request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    )
  }
  func client(_ base: String) -> WaniKaniClient {
    WaniKaniClient(baseURL: URL(string: base)!) { try await self.respond($0) }
  }
}

struct TokenClientTests {
  @Test func invalidSignupDateCannotBecomeAValidatedToken() async {
    let server = TokenServer(startedAt: "not a timestamp")
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await server.client("https://fixture.example.test/v2").account(token: "new-token")
    }
  }
  @Test(arguments: [
    "https://api.wanikani.com/v2", "http://localhost:8181/test/v2/",
    "https://fixture.example.test/api",
  ])
  func tokenValidationUsesOnlyTheConfiguredServer(base: String) async throws {
    let server = TokenServer()
    let account = try await server.client(base).account(token: "fixture")
    #expect(account.id == "fixture-user-id" && account.username == "test")
    #expect(account.startedAt == 1_792_195_200)
    let requests = await server.requests
    let request = try #require(requests.first)
    #expect(requests.count == 1 && request.httpMethod == "GET" && request.httpBody == nil)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
    #expect(
      request.url?.absoluteString == base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        + "/user")
  }
  @Test(arguments: [
    "file:///tmp/server", "https://user:secret@fixture.example.test/v2",
    "https://fixture.example.test/v2?secret=yes", "https://fixture.example.test/v2#fragment",
  ])
  func invalidServerConfigurationNeverReceivesAToken(base: String) async {
    let server = TokenServer()
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await server.client(base).account(token: "fixture")
    }
    #expect(await server.requests.isEmpty)
  }
  @Test(arguments: [
    "https://other.example.test/v2/user", "http://fixture.example.test/v2/user",
    "https://fixture.example.test:444/v2/user", "https://fixture.example.test/other/user",
  ])
  func aResponseOutsideTheConfiguredScopeIsRejected(response: String) async {
    let server = TokenServer(responseURL: URL(string: response))
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await server.client("https://fixture.example.test/v2").account(token: "fixture")
    }
    #expect(await server.requests.count == 1)
  }
  @Test func paginationCannotSendTheTokenToAnotherServer() async {
    let server = TokenServer(next: "https://other.example.test/v2/assignments?page_after_id=1")
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await server.client("https://fixture.example.test/v2").assignment(
        subjectID: 1, token: "fixture")
    }
    #expect(await server.requests.count == 1)
  }
  @Test(arguments: [401, 403])
  func hibernatingAccountsRetainTheExistingReactivationPath(status: Int) async {
    let server = TokenServer(status: status, message: "Account is HIBERNATING")
    await #expect(throws: StudySignInError.self) {
      try await server.client("https://api.wanikani.com/v2").account(token: "fixture")
    }
    #expect(await server.requests.count == 1)
  }
  @Test(arguments: [401, 403])
  func otherAuthenticationErrorsDoNotSuggestReactivation(status: Int) async {
    let server = TokenServer(status: status, message: "Unauthorized")
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await server.client("https://api.wanikani.com/v2").account(token: "fixture")
    }
  }
  @Test func hibernatingWriteIsStillDefinitelyRejectedAndNeverRetried() async {
    let server = TokenServer(status: 403, message: "Account is hibernating")
    let client = await server.client("https://api.wanikani.com/v2")
    let answer = StudyReviewSubmission(
      itemID: 0, subjectID: 1, assignmentID: 1,
      isLesson: false, meaningWrong: false, readingWrong: false, meaningWrongCount: 0,
      readingWrongCount: 0, createdAt: nil)
    do {
      _ = try await client.submit(answer, token: "fixture")
      Issue.record("A forbidden review was accepted")
    } catch WaniKaniClient.APIError.unauthorized {
    } catch { Issue.record("The outbox would not classify this as a definite rejection: \(error)") }
    #expect(await server.requests.count == 1)
  }

}
