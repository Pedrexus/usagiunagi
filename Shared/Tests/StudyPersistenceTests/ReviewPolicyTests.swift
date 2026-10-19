import Foundation
import StudyCore
import Testing

@testable import StudyPersistence

struct ReviewPolicyTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func download() -> StudyDownload {
    var profile = StudyAccountProfile(username: "Policy fixture")
    profile.level = 3
    profile.maxLevelGranted = 60
    var download = StudyDownload(accountID: "policy", profile: profile)
    for id: Int64 in 1...3 {
      var subject = CatalogSubject(id: id, kind: .radical)
      subject.level = Int(id)
      subject.japanese = "一"
      subject.meanings = [.init("One", role: .primary)]
      subject.spacedRepetitionSystemID = 77
      var assignment = CatalogAssignment(id: 100 + id, subjectID: id, kind: .radical)
      assignment.level = subject.level
      assignment.srsStage = Int(id)
      assignment.unlockedAt = 1
      assignment.startedAt = 1
      assignment.passedAt = 1
      assignment.availableAt = Int64(now.timeIntervalSince1970) - id * 100
      download.subjects.append(subject)
      download.assignments.append(assignment)
      download.statistics.append(
        .init(
          id: id,
          answers: .init(
            subjectID: id, type: .radical, meaningIncorrect: Int(id), meaningCurrentStreak: 1)))
    }
    download.systems = [
      .init(
        id: 77, name: "Synthetic", unlockingStage: 0, startingStage: 1, passingStage: 5,
        burningStage: 9,
        stages: (0...9).map {
          .init(position: $0, interval: $0 == 0 || $0 == 9 ? nil : $0 == 3 ? 10 : 10000)
        })
    ]
    return download
  }
  private func store(at url: URL = URL(filePath: "/unused"), inMemory: Bool = true) async throws
    -> StudyStore
  {
    let store = try await StudyStore.open(at: url, inMemory: inMemory)
    _ = try await store.applyDownload(
      download(), credentialID: "policy-key", baseline: store.refreshBaseline(accountID: "policy"))
    return store
  }
  @Test func capOrdersOnlyNewScheduledQueuesAndNeverShrinksPausedWork() async throws {
    let store = try await store()
    var policy = StudyReviewPolicy()
    policy.order = .oldestAvailableFirst
    policy.limitEnabled = true
    policy.limit = 2
    #expect(try await store.homeData(accountID: "policy", now: now, policy: policy).reviews == 3)
    let opened = try await store.openReviews(accountID: "policy", now: now, policy: policy)
    #expect(
      opened.saved.session.items[0]?.subjectID == 3 && opened.saved.session.items[1]?.subjectID == 2
    )
    #expect(opened.saved.session.items.count == 2)
    policy.limit = 1
    policy.order = .newestAvailableFirst
    let resumed = try await store.openReviews(accountID: "policy", now: now, policy: policy)
    #expect(
      resumed.saved.revision == opened.saved.revision
        && resumed.saved.session.question == opened.saved.session.question
        && resumed.saved.session.options == opened.saved.session.options
        && resumed.saved.session.items.count == opened.saved.session.items.count)
    #expect(try await store.pendingReviews(accountID: "policy").isEmpty)
    try await store.endReviews(accountID: "policy", expectedRevision: resumed.saved.revision)
    let practice = try await store.openPractice(
      accountID: "policy", scope: .leeches, now: now, policy: policy)
    #expect(practice.saved.session.items.count == 3 && practice.isPractice)
    #expect(try await store.pendingReviews(accountID: "policy").isEmpty)
  }
  @Test func leechThresholdMatchesHomeAndDoesNotChangeAnExistingPractice() async throws {
    let store = try await store()
    var policy = StudyReviewPolicy()
    policy.leechThreshold = 3
    #expect(try await store.homeData(accountID: "policy", now: now, policy: policy).leeches == 1)
    let opened = try await store.openPractice(
      accountID: "policy", scope: .leeches, now: now, policy: policy)
    #expect(opened.saved.session.items.values.map(\.subjectID) == [3])
    policy.leechThreshold = 100
    let resumed = try await store.openPractice(
      accountID: "policy", scope: .leeches, now: now, policy: policy)
    #expect(resumed.saved.revision == opened.saved.revision)
  }
  @Test func metadataSurvivesReopenAndOldTypedRefreshAndInvalidDownloadsAreAtomic() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "policy.store")
    do { _ = try await store(at: url, inMemory: false) }
    let reopened = try await StudyStore.open(at: url)
    #expect(try await reopened.accountState(accountID: "policy")?.systems == download().systems)
    var oldDownload = download()
    oldDownload.systems = nil
    _ = try await reopened.applyDownload(
      oldDownload, credentialID: "policy-key",
      baseline: reopened.refreshBaseline(accountID: "policy"))
    #expect(try await reopened.accountState(accountID: "policy")?.systems == download().systems)
    var policy = StudyReviewPolicy()
    policy.order = .longestRelativeWait
    policy.limitEnabled = true
    policy.limit = 1
    let opened = try await reopened.openReviews(accountID: "policy", now: now, policy: policy)
    #expect(opened.subject?.id == 3)
    var invalid = download()
    invalid.systems = []
    await #expect(throws: WaniKaniClient.APIError.self) {
      try await reopened.applyDownload(
        invalid, credentialID: "policy-key", baseline: reopened.refreshBaseline(accountID: "policy")
      )
    }
    #expect(try await reopened.session(accountID: "policy")?.revision == opened.saved.revision)
    #expect(try await reopened.accountState(accountID: "policy")?.systems == download().systems)
    #expect(try await reopened.pendingReviews(accountID: "policy").isEmpty)
  }
  @Test func olderAccountBytesDecodeWithoutSystemDefinitions() throws {
    var object = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(StudyAccountState(download: download()))) as? [String: Any])
    object.removeValue(forKey: "systems")
    let old = try JSONDecoder().decode(
      StudyAccountState.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old.systems == nil && old.profile.username == "Policy fixture")
  }
}
