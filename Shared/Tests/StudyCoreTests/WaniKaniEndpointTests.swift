import Foundation
import StudyCore
import StudyTestSupport
import Testing

private actor EndpointTransport {
  private(set) var urls: [URL] = []
  func respond(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
    urls.append(request.url!)
    return try DownloadFixture.response(request)
  }
}

struct WaniKaniEndpointTests {
  @Test func endpointChangesAndResetRetainTheInjectedTransport() async throws {
    let transport = EndpointTransport()
    let original = WaniKaniClient { try await transport.respond($0) }
    let custom = try original.reconfigured(baseURL: URL(string: "http://localhost:8080/api///")!)
    #expect(try await custom.account(token: "fixture").id == "fixture-user-id")
    let reset = try custom.reconfigured(baseURL: WaniKaniClient.defaultBaseURL)
    #expect(try await reset.account(token: "fixture").id == "fixture-user-id")
    #expect(try await original.account(token: "fixture").id == "fixture-user-id")
    #expect(
      await transport.urls == [
        URL(string: "http://localhost:8080/api/user")!,
        WaniKaniClient.defaultBaseURL.appending(path: "user"),
        WaniKaniClient.defaultBaseURL.appending(path: "user"),
      ])
  }

  @Test(arguments: ["file:///tmp/study.store", "ftp://localhost/api"])
  func invalidEndpointsRejectBeforeUsingTheTransport(_ address: String) async throws {
    let transport = EndpointTransport()
    let original = WaniKaniClient { try await transport.respond($0) }
    #expect(throws: WaniKaniServiceConfigurationError.invalidEndpoint) {
      try original.reconfigured(baseURL: URL(string: address)!)
    }
    #expect(await transport.urls.isEmpty)
    #expect(try await original.account(token: "fixture").id == "fixture-user-id")
    #expect(await transport.urls == [WaniKaniClient.defaultBaseURL.appending(path: "user")])
  }
}
