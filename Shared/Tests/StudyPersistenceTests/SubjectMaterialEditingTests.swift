import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

struct SubjectMaterialEditingTests {
  private let account = "fixture-user-id"
  private func store(at url: URL = URL(filePath: "/unused")) async throws -> StudyStore {
    let store = try await StudyStore.open(at: url, inMemory: url.path == "/unused")
    _ = try await store.refresh(
      credentialID: "credential", token: "fixture",
      client: WaniKaniClient(transport: DownloadFixture.response))
    return store
  }

  @Test func editedTextAndQueueSurviveReopening() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "study.store")
    let edited = StudyMaterial(
      subjectID: 1, meaningNote: "  🐰 一\nSecond line\n", readingNote: "\nいち  ",
      meaningSynonyms: ["One, alone", "First\nonly", "一"])
    do {
      let store = try await store(at: url)
      let before = try await store.subjectDetails(subjectID: 1, accountID: account)
      try await store.saveSubjectMaterial(
        edited, accountID: account, expectedRevision: before.savedMaterial?.revision)
      let saved = try await store.subjectDetails(subjectID: 1, accountID: account)
      #expect(saved.savedMaterial?.pending == true)
      #expect(saved.savedMaterial?.revision != before.savedMaterial?.revision)
      #expect(saved.savedMaterial?.serverID == before.savedMaterial?.serverID)
    }
    let reopened = try await StudyStore.open(at: url)
    let restored = try await reopened.subjectDetails(subjectID: 1, accountID: account)
    #expect(restored.material == edited && restored.savedMaterial?.pending == true)
  }

  @Test func unchangedAndEmptyContentDoesNotCreateUploadsOrRevisions() async throws {
    let store = try await store()
    let original = try await store.subjectDetails(subjectID: 1, accountID: account)
    try await store.saveSubjectMaterial(
      #require(original.material), accountID: account,
      expectedRevision: original.savedMaterial?.revision)
    let unchanged = try await store.subjectDetails(subjectID: 1, accountID: account)
    #expect(unchanged.savedMaterial?.revision == original.savedMaterial?.revision)
    #expect(unchanged.savedMaterial?.pending == false)
    try await store.saveSubjectMaterial(
      .init(subjectID: 2), accountID: account, expectedRevision: nil)
    #expect(try await store.subjectDetails(subjectID: 2, accountID: account).savedMaterial == nil)
    try await store.saveSubjectMaterial(
      .init(subjectID: 2, meaningNote: "Created offline"), accountID: account, expectedRevision: nil
    )
    let new = try await store.subjectDetails(subjectID: 2, accountID: account)
    #expect(new.savedMaterial?.pending == true)
    try await store.saveSubjectMaterial(
      .init(subjectID: 2), accountID: account, expectedRevision: new.savedMaterial?.revision)
    let cleared = try await store.subjectDetails(subjectID: 2, accountID: account)
    #expect(
      cleared.material == StudyMaterial(subjectID: 2) && cleared.savedMaterial?.pending == true)
  }

  @Test(arguments: [Int64(1), Int64(2)]) func staleEditorsCannotOverwriteEvenIdenticalContent(
    subjectID: Int64
  ) async throws {
    let store = try await store()
    let old = try await store.subjectDetails(subjectID: subjectID, accountID: account)
    let first = StudyMaterial(subjectID: subjectID, meaningNote: "First window")
    try await store.saveSubjectMaterial(
      first, accountID: account, expectedRevision: old.savedMaterial?.revision)
    for value in [first, StudyMaterial(subjectID: subjectID, meaningNote: "Stale window")] {
      await #expect(throws: StudyStoreError.self) {
        try await store.saveSubjectMaterial(
          value, accountID: account, expectedRevision: old.savedMaterial?.revision)
      }
    }
    let latest = try await store.subjectDetails(subjectID: subjectID, accountID: account)
    #expect(latest.material == first)
    let replacement = StudyMaterial(subjectID: subjectID, meaningNote: "Explicit replacement")
    try await store.saveSubjectMaterial(
      replacement, accountID: account, expectedRevision: latest.savedMaterial?.revision)
    #expect(
      try await store.subjectDetails(subjectID: subjectID, accountID: account).material
        == replacement)
  }

  @Test func currentAccessIsRevalidatedBeforeEverySave() async throws {
    let store = try await store()
    let old = try await store.subjectDetails(subjectID: 1, accountID: account)
    for subjectID: Int64 in [4, 99999] {
      await #expect(throws: SubjectDetailsError.self) {
        try await store.saveSubjectMaterial(
          .init(subjectID: subjectID, meaningNote: "hidden"), accountID: account,
          expectedRevision: nil)
      }
    }
    var download = try await WaniKaniClient(transport: DownloadFixture.response).download(
      token: "fixture")
    download.profile.maxLevelGranted = 0
    _ = try await store.applyDownload(
      download, credentialID: "credential", baseline: store.refreshBaseline(accountID: account))
    await #expect(throws: SubjectDetailsError.self) {
      try await store.saveSubjectMaterial(
        .init(subjectID: 1, meaningNote: "locked"), accountID: account,
        expectedRevision: old.savedMaterial?.revision)
    }
    try await store.removeSnapshot(credentialID: "credential")
    await #expect(throws: StudyStoreError.self) {
      try await store.saveSubjectMaterial(
        .init(subjectID: 1, meaningNote: "disconnected"), accountID: account,
        expectedRevision: old.savedMaterial?.revision)
    }
    #expect(try await store.materials(accountID: account).allSatisfy { !$0.pending })
  }

  @Test func editingDoesNotClearAnUncertainUploadOrResendIt() async throws {
    let store = try await store()
    let original = try await store.subjectDetails(subjectID: 1, accountID: account)
    let first = StudyMaterial(subjectID: 1, meaningNote: "First attempt")
    try await store.saveSubjectMaterial(
      first, accountID: account, expectedRevision: original.savedMaterial?.revision)
    let interrupted = WaniKaniClient { request in
      if request.httpMethod != "GET" { throw URLError(.timedOut) }
      return try DownloadFixture.response(request)
    }
    await #expect(throws: URLError.self) {
      try await store.uploadPending(accountID: account, token: "fixture", client: interrupted)
    }
    let uncertain = try await store.subjectDetails(subjectID: 1, accountID: account)
    let changed = StudyMaterial(subjectID: 1, meaningNote: "Newer draft")
    try await store.saveSubjectMaterial(
      changed, accountID: account, expectedRevision: uncertain.savedMaterial?.revision)
    let current = try await store.subjectDetails(subjectID: 1, accountID: account)
    #expect(current.material == changed && current.savedMaterial?.pending == true)
    #expect(current.savedMaterial?.attemptedMaterial == first)
    #expect(current.savedMaterial?.attemptedRevision == uncertain.savedMaterial?.attemptedRevision)
    #expect(current.savedMaterial?.issue?.reason == .uncertain)
    let readOnly = WaniKaniClient { request in
      #expect(request.httpMethod == "GET")
      return try DownloadFixture.response(request)
    }
    let report = try await store.uploadPending(
      accountID: account, token: "fixture", client: readOnly)
    #expect(report.uploadedMaterials == 0 && report.materialsNeedingAttention == 1)
  }

  @Test func newSynonymIsUsedByAnAlreadyOpenReview() async throws {
    let store = try await store()
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    var review = try await store.openReviews(accountID: account, now: now)
    if let question = review.question, question.kind == .reading {
      review = try await store.answerReview(
        "いち", question: question, accountID: account, expectedRevision: review.saved.revision,
        now: now
      ).state
    }
    let question = try #require(review.question)
    #expect(question.kind == .meaning)
    let before = try await store.subjectDetails(subjectID: 1, accountID: account)
    var material = try #require(before.material)
    material.meaningSynonyms.append("solitary example")
    try await store.saveSubjectMaterial(
      material, accountID: account, expectedRevision: before.savedMaterial?.revision)
    let result = try await store.answerReview(
      "solitary example", question: question, accountID: account,
      expectedRevision: review.saved.revision, now: now)
    #expect(result.grade == .precise)
    #expect(try await store.materials(accountID: account).first?.pending == true)
  }
}
