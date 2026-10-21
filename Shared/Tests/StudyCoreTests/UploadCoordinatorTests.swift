import Foundation
import Testing

@testable import StudyCore

struct UploadCoordinatorTests {
  private let material = PendingUploadKey(kind: .studyMaterial, subjectID: 42)
  private let review = PendingUploadKey(kind: .progress, subjectID: 42)

  @Test func serializesBothKindsAndReloadsQueuedEdits() async throws {
    let queue = UploadCoordinator()
    let store = ControlledUploads()
    await store.put(material, "old")
    await store.put(review, "review")
    let repository = await store.repository()
    let first = await queue.enqueue([material], repository: repository)
    await store.waitForFirstSend()
    // Both sync and an immediate save may have already selected this subject.
    let second = await queue.enqueue([review, material], repository: repository)
    let redundant = await queue.enqueue([material], repository: repository)
    await store.put(material, "new")
    await store.releaseFirstSend()
    try await first.value
    try await second.value
    try await redundant.value
    #expect(await store.sent == ["old", "review", "new"])
    #expect(await store.maximumConcurrentSends == 1)
    #expect(await store.pending.isEmpty)
  }

  @Test func failedWriteStaysPendingAndDoesNotPoisonFollowingWork() async throws {
    let queue = UploadCoordinator()
    let store = ControlledUploads(failFirst: true)
    await store.put(material, "note")
    await store.put(review, "review")
    let repository = await store.repository()
    let first = await queue.enqueue([material], repository: repository)
    await store.waitForFirstSend()
    let second = await queue.enqueue([review], repository: repository)
    await store.releaseFirstSend()
    await #expect(throws: ControlledUploads.Failure.self) { try await first.value }
    try await second.value
    #expect(await store.pending[material] == Data("note".utf8))
    #expect(await store.acknowledged == [review])
    let retry = await queue.enqueue([material], repository: repository)
    try await retry.value
    #expect(await store.pending.isEmpty)
  }

  @Test func invalidatedLifetimeRejectsQueuedJobsAndLateAcknowledgement() async throws {
    let queue = UploadCoordinator()
    let store = ControlledUploads()
    await store.put(material, "old account")
    await store.put(review, "review")
    let repository = await store.repository()
    let first = await queue.enqueue([material], repository: repository)
    await store.waitForFirstSend()
    let second = await queue.enqueue([review], repository: repository)
    repository.lifetime.invalidate()
    await store.releaseFirstSend()
    await #expect(throws: CancellationError.self) { try await first.value }
    await #expect(throws: CancellationError.self) { try await second.value }
    #expect(await store.sent == ["old account"])
    #expect(await store.acknowledged.isEmpty)
    #expect(await store.pending.count == 2)
    #expect(throws: CancellationError.self) {
      try repository.lifetime.withActive { Issue.record("Expired store accessed") }
    }
  }

  @Test func removedPendingRowIsNeverResubmitted() async throws {
    let queue = UploadCoordinator()
    let store = ControlledUploads()
    let repository = await store.repository()
    let job = await queue.enqueue([material, review], repository: repository)
    try await job.value
    #expect(await store.sent.isEmpty)
    #expect(await store.acknowledged.isEmpty)
  }
}

private actor ControlledUploads {
  struct Failure: Error {}
  var pending: [PendingUploadKey: Data] = [:]
  var sent: [String] = []
  var acknowledged: [PendingUploadKey] = []
  var maximumConcurrentSends = 0
  private var activeSends = 0
  private var firstStarted = false
  private var firstWaiter: CheckedContinuation<Void, Never>?
  private var release: CheckedContinuation<Void, Never>?
  private let failFirst: Bool
  init(failFirst: Bool = false) { self.failFirst = failFirst }
  func put(_ key: PendingUploadKey, _ text: String) { pending[key] = Data(text.utf8) }
  func repository() -> UploadRepository {
    UploadRepository(
      lifetime: UploadLifetime(), load: { await self.pending[$0] },
      send: { try await self.send($0, payload: $1) },
      acknowledge: { await self.acknowledge($0, payload: $1) })
  }
  func waitForFirstSend() async {
    if firstStarted { return }
    await withCheckedContinuation { firstWaiter = $0 }
  }
  func releaseFirstSend() {
    release?.resume()
    release = nil
  }
  private func send(_ key: PendingUploadKey, payload: Data) async throws {
    activeSends += 1
    maximumConcurrentSends = max(maximumConcurrentSends, activeSends)
    defer { activeSends -= 1 }
    sent.append(String(decoding: payload, as: UTF8.self))
    if !firstStarted {
      firstStarted = true
      await withCheckedContinuation { continuation in
        release = continuation
        firstWaiter?.resume()
        firstWaiter = nil
      }
      if failFirst { throw Failure() }
    }
  }
  private func acknowledge(_ key: PendingUploadKey, payload: Data) {
    acknowledged.append(key)
    if pending[key] == payload { pending[key] = nil }
  }
}
