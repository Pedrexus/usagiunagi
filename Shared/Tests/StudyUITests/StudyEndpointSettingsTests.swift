import Foundation
import StudyCore
import StudyPersistence
import StudyTestSupport
import StudyUI
import Testing

private actor EndpointModelTransport {
  private(set) var urls: [URL] = []
  let gate: StudyTaskGate?
  private var paused = false
  init(gate: StudyTaskGate? = nil) { self.gate = gate }
  func respond(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    urls.append(request.url!)
    if let gate, !paused {
      paused = true
      await gate.pause()
    }
    return try DownloadFixture.response(request)
  }
}

/// A deliberately fixed service exercises the protocol's fail-closed reconfiguration default.
private struct FixedEndpointService: WaniKaniService {
  let client: WaniKaniClient
  func account(token: String) async throws -> WaniKaniAccount {
    try await client.account(token: token)
  }
  func download(token: String) async throws -> StudyDownload {
    try await client.download(token: token)
  }
  func assignment(subjectID: Int64, token: String) async throws -> CatalogAssignment? {
    try await client.assignment(subjectID: subjectID, token: token)
  }
  func material(subjectID: Int64, token: String) async throws -> WaniKaniMaterial? {
    try await client.material(subjectID: subjectID, token: token)
  }
  func submit(_ answer: StudyReviewSubmission, token: String, now: Date) async throws
    -> CatalogAssignment
  {
    try await client.submit(answer, token: token, now: now)
  }
  func writeMaterial(_ value: StudyMaterial, serverID: Int64?, token: String) async throws
    -> WaniKaniMaterial
  {
    try await client.writeMaterial(value, serverID: serverID, token: token)
  }
}

@MainActor struct StudyEndpointSettingsTests {
  @Test func applyingAndResettingEndpointKeepsTheInjectedServiceAndLocalAccount() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let transport = EndpointModelTransport()
    let credentials = MemoryCredentials("fixture")
    let model = StudyAppModel(
      credentials: credentials, client: WaniKaniClient { try await transport.respond($0) },
      openStore: { store })
    await model.refresh()
    let original = try #require(model.snapshot)
    let count = await transport.urls.count
    try model.setAPIEndpoint(URL(string: "http://localhost:8080/api///")!)
    #expect(await transport.urls.count == count)
    #expect(model.snapshot?.accountID == original.accountID)
    #expect(model.savedWorkStore === store)
    await model.refresh()
    #expect(model.error == nil && model.snapshot?.accountID == original.accountID)
    let custom = Array(await transport.urls.dropFirst(count))
    #expect(
      !custom.isEmpty && custom.allSatisfy { $0.host == "localhost" && $0.path.hasPrefix("/api/") })
    let resetCount = await transport.urls.count
    try model.setAPIEndpoint(WaniKaniClient.defaultBaseURL)
    await model.refresh()
    #expect(model.error == nil && model.snapshot?.accountID == original.accountID)
    let reset = Array(await transport.urls.dropFirst(resetCount))
    #expect(
      !reset.isEmpty
        && reset.allSatisfy { $0.host == "api.wanikani.com" && $0.path.hasPrefix("/v2/") })
    #expect(credentials.saved.isEmpty && credentials.token == "fixture")
    #expect(try await store.savedWork(accountID: "fixture-user-id").reviews.isEmpty)
  }

  @Test func unsupportedAndInvalidChangesKeepTheExactInjectedService() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let transport = EndpointModelTransport()
    let credentials = MemoryCredentials("fixture")
    let client = FixedEndpointService(client: WaniKaniClient { try await transport.respond($0) })
    let model = StudyAppModel(credentials: credentials, client: client, openStore: { store })
    #expect(throws: WaniKaniServiceConfigurationError.invalidEndpoint) {
      try model.setAPIEndpoint(URL(string: "file:///tmp/study.store")!)
    }
    var rejected = false
    do {
      try model.setAPIEndpoint(URL(string: "http://localhost:8080/api")!)
    } catch WaniKaniServiceConfigurationError.unsupportedEndpointChange {
      rejected = true
    }
    try #require(rejected)
    #expect(await transport.urls.isEmpty)
    await model.refresh()
    #expect(model.error == nil && model.snapshot?.accountID == "fixture-user-id")
    let requests = await transport.urls
    #expect(!requests.isEmpty && requests.allSatisfy { $0.host == "api.wanikani.com" })
    #expect(credentials.saved.isEmpty && credentials.token == "fixture")
  }

  @Test func aBusyReadRejectsEndpointChangesBeforeReplacingTheInjectedService() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let gate = StudyTaskGate()
    let transport = EndpointModelTransport(gate: gate)
    let model = StudyAppModel(
      credentials: MemoryCredentials("fixture"),
      client: WaniKaniClient { try await transport.respond($0) }, openStore: { store })
    let reading = Task { await model.refresh() }
    await gate.waitForEntry()
    var rejected = false
    do {
      try model.setAPIEndpoint(URL(string: "http://localhost:8080/api")!)
    } catch StudyUploadError.alreadyRunning {
      rejected = true
    } catch { Issue.record("Unexpected endpoint rejection: \(error)") }
    await gate.resume()
    await reading.value
    try #require(rejected)
    await model.refresh()
    #expect(model.error == nil && model.snapshot?.accountID == "fixture-user-id")
    let requests = await transport.urls
    #expect(!requests.isEmpty && requests.allSatisfy { $0.host == "api.wanikani.com" })
  }
}
