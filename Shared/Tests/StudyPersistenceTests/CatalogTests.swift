import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

struct CatalogTests {
  private let account = "fixture-user-id"
  @Test func savedCatalogFiltersAccessAndHiddenContentAndKeepsProgressAndExclusions() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    var download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    download.profile.maxLevelGranted = 3
    download.subjects[1].level = 4
    let baseline = try await store.refreshBaseline(accountID: account)
    _ = try await store.applyDownload(download, credentialID: "credential", baseline: baseline)
    let details = try await store.subjectDetails(subjectID: 5, accountID: account)
    try await store.saveSubjectMaterial(
      .init(subjectID: 5, meaningNote: StudyMaterial.exclusionMarker), accountID: account,
      expectedRevision: details.savedMaterial?.revision)
    let catalog = try await store.subjectCatalog(accountID: account)
    #expect(catalog.items.map(\.id) == [1, 3, 5])
    #expect(catalog.items.first?.status.stage == .guru1)
    #expect(catalog.items.first { $0.id == 5 }?.isExcluded == true)
    #expect(SubjectCatalogScope.locked.contains(try #require(catalog.items.first { $0.id == 3 })))
    #expect(catalog.pendingCount == 0 && !catalog.requiresAssignmentRefresh)
    await #expect(throws: StudyStoreError.self) {
      try await store.subjectCatalog(accountID: "different")
    }
    try await store.removeSnapshot(credentialID: "credential")
    await #expect(throws: StudyStoreError.self) {
      try await store.subjectCatalog(accountID: account)
    }
  }

  @Test func pendingAnswersAreNotCountedAsSyncedCatalogStages() async throws {
    let store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
    _ = try await store.refresh(
      credentialID: "credential", token: "fixture",
      client: WaniKaniClient(transport: DownloadFixture.response))
    var state = try await store.openReviews(
      accountID: account, now: .init(timeIntervalSince1970: 2_000_000_000))
    for _ in 0..<2 {
      let question = try #require(state.question)
      state = try await store.answerReview(
        question.kind == .meaning ? "one" : "いち", question: question,
        accountID: account, expectedRevision: state.saved.revision
      ).state
    }
    let catalog = try await store.subjectCatalog(accountID: account)
    let item = try #require(catalog.items.first { $0.id == 1 })
    #expect(catalog.pendingCount == 1 && item.status.stage == nil)
    if case .pending = item.status {
    } else {
      Issue.record("Pending review was shown as synced progress")
    }
    #expect(!SubjectCatalogScope.guru.contains(item))
    #expect(try await store.pendingReviews(accountID: account).count == 1)
  }
}
