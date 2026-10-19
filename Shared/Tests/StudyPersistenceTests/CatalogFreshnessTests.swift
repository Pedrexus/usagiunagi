import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

struct CatalogFreshnessTests {
  private let account = "fixture-user-id"
  private let credential = StudyCredentialID.forToken("fixture")
  private let client = WaniKaniClient(transport: DownloadFixture.response)
  private func prepare(_ store: StudyStore) async throws -> SavedReview {
    _ = try await store.synchronize(credentialID: credential, token: "fixture", client: client)
    let assignment = try #require(await store.assignments(accountID: account).first)
    var session = try StudySession(items: [assignment.sessionItem(id: 0, isLesson: false)], seed: 1)
    while let question = session.nextQuestion() {
      _ = try session.mark(.correct, for: question, now: Int64(Date().timeIntervalSince1970))
    }
    try await store.saveSession(session, accountID: account, expectedRevision: nil)
    return try #require(await store.pendingReviews(accountID: account).first)
  }
  @Test func anAcknowledgedStudyKeepsItsReadMarkerAcrossStoreReopening() async throws {
    let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let store = try await StudyStore.open(at: url)
    let review = try await prepare(store)
    try await store.beginReviewAttempt(review)
    let attempted = try #require(await store.accountState(accountID: account)?.catalogRefreshID)
    try await store.acknowledgeReview(review)
    let acknowledged = try #require(await store.accountState(accountID: account)?.catalogRefreshID)
    #expect(acknowledged != attempted)
    let reopened = try await StudyStore.open(at: url)
    #expect(try await reopened.pendingReviews(accountID: account).isEmpty)
    #expect(try await reopened.accountState(accountID: account)?.catalogRefreshID == acknowledged)
    _ = try await reopened.synchronize(credentialID: credential, token: "fixture", client: client)
    #expect(try await reopened.accountState(accountID: account)?.catalogRefreshID == nil)
  }
  @Test func aReadCanOnlyConsumeTheMarkerItCapturedBeforeDownloading() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    let review = try await prepare(store)
    let beforeAttempt = try await store.refreshBaseline(accountID: account)
    let download = try await client.download(token: "fixture")
    try await store.beginReviewAttempt(review)
    let attempted = try #require(await store.accountState(accountID: account)?.catalogRefreshID)
    _ = try await store.applyDownload(download, credentialID: credential, baseline: beforeAttempt)
    #expect(try await store.accountState(accountID: account)?.catalogRefreshID == attempted)
    let beforeAcknowledgement = try await store.refreshBaseline(accountID: account)
    try await store.acknowledgeReview(review)
    let acknowledged = try #require(await store.accountState(accountID: account)?.catalogRefreshID)
    _ = try await store.applyDownload(
      download, credentialID: credential, baseline: beforeAcknowledgement)
    #expect(try await store.accountState(accountID: account)?.catalogRefreshID == acknowledged)
    let current = try await store.refreshBaseline(accountID: account)
    _ = try await store.applyDownload(download, credentialID: credential, baseline: current)
    #expect(try await store.accountState(accountID: account)?.catalogRefreshID == nil)
  }
}
