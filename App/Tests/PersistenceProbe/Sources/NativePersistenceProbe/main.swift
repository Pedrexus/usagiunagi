import Darwin
import Foundation
import StudyCore
import StudyPersistence

/// Separate-process durability check of the production store, with synthetic data only.
@main struct Probe {
  static func main() async throws {
    let args = CommandLine.arguments
    var modes = [
      "write", "read", "read-attempts", "write-catalog", "read-catalog",
    ]
    #if DEBUG
      modes += ["read-native-baseline"] + NativeStoreUpgrade.commands
    #endif
    guard args.count == 3, modes.contains(args[1]) else {
      print(
        "Usage: NativePersistenceProbe \(modes.joined(separator: "|")) /path/to/disposable/study.store"
      )
      exit(2)
    }
    #if DEBUG
      if NativeStoreUpgrade.commands.contains(args[1]) {
        try await NativeStoreUpgrade.run(args[1], url: URL(filePath: args[2]))
        return
      }
      if args[1].hasSuffix("native-baseline") {
        try await NativeStoreBaseline.run(args[1], url: URL(fileURLWithPath: args[2]))
        return
      }
    #endif
    let store = try await StudyStore.open(at: URL(fileURLWithPath: args[2]))
    if args[1].hasSuffix("catalog") {
      if args[1] == "write-catalog" {
        var profile = StudyAccountProfile(username: "upgrade")
        profile.level = 4
        profile.maxLevelGranted = 60
        var source = StudyDownload(accountID: "upgrade", profile: profile)
        var subject = CatalogSubject(id: 42, kind: .kanji)
        subject.level = 4
        subject.japanese = "猫"
        subject.meanings = [.init("Cat", role: .primary)]
        subject.meaningMnemonic = "Saved mnemonic"
        source.subjects = [subject]
        var assignment = CatalogAssignment(id: 142, subjectID: 42, kind: .kanji)
        assignment.level = 4
        assignment.srsStage = 5
        source.assignments = [assignment]
        source.materials = [
          .init(
            id: 242, value: .init(subjectID: 42, meaningNote: "pending migration note"))
        ]
        let client = ProbeServer(accountID: "upgrade", profile: profile, catalog: source)
        _ = try await store.refresh(credentialID: "upgrade", token: "fixture", client: client)
        let note = try await store.materials(accountID: "upgrade").first!
        try await store.saveMaterial(
          note.material, accountID: "upgrade", expectedRevision: note.revision)
        _ = try await store.uploadPending(accountID: "upgrade", token: "fixture", client: client)
        print("PASS: wrote production catalog, assignment and pending note")
      } else {
        let account = try await store.accountState(accountID: "upgrade")
        precondition(account?.profile.level == 4 && account?.catalogRefreshID != nil)
        let subject = try await store.catalog(accountID: "upgrade").first!
        let assignment = try await store.assignments(accountID: "upgrade").first!
        let note = try await store.materials(accountID: "upgrade").first!
        precondition(subject.japanese == "猫" && subject.meaningMnemonic == "Saved mnemonic")
        precondition(assignment.id == 142 && assignment.level == 4 && assignment.srsStage == 5)
        precondition(
          note.pending && note.material.meaningNote == "pending migration note"
            && note.serverID == 242)
        precondition(note.issue?.reason == .uncertain)
        print(
          "PASS: fresh process reopened native catalog, assignment and pending note"
        )
      }
      return
    }
    if args[1] == "write" {
      for id in ["first", "second"] {
        let snapshot = StudySnapshot(
          accountID: id, username: id, currentLevel: 1,
          assignments: [], statistics: [], levels: [], subjects: [])
        try await store.saveSnapshot(snapshot, credentialID: id)
      }
      var session = try StudySession(
        items: [
          .init(
            id: 0, subjectID: 42, assignmentID: 142,
            srsStage: 3, hasReading: false)
        ], seed: 1)
      let revision = try await store.saveSession(session, accountID: "first", expectedRevision: nil)
      let question = session.nextQuestion()!
      _ = try session.mark(.correct, for: question, now: 100)
      try await store.saveSession(session, accountID: "first", expectedRevision: revision)
      let review = try await store.pendingReviews(accountID: "first").first!
      try await store.beginReviewAttempt(review)
      try await store.saveMaterial(
        .init(subjectID: 42, meaningNote: "offline note"), accountID: "first", expectedRevision: nil
      )
      try await store.saveMaterial(
        .init(subjectID: 42, meaningNote: "other account"), accountID: "second",
        expectedRevision: nil)
      let client = ProbeServer(accountID: "first")
      do {
        _ = try await store.uploadPending(accountID: "first", token: "synthetic", client: client)
        preconditionFailure("Expected the synthetic material write to time out")
      } catch let error as URLError { precondition(error.code == .timedOut) }
      print(
        "PASS: production store saved session, uncertain review and exact attempted note revision")
    } else {
      let session = try await store.session(accountID: "first")!
      let review = try await store.pendingReviews(accountID: "first").first!
      let first = try await store.materials(accountID: "first").first!
      let second = try await store.materials(accountID: "second").first!
      precondition(session.session.completedIDs == [0])
      precondition(review.attempted && review.submission.createdAt == 100)
      precondition(first.pending && first.material.meaningNote == "offline note")
      precondition(second.pending && second.material.meaningNote == "other account")
      if args[1] == "read-attempts" {
        precondition(review.issue?.reason == .uncertain)
        precondition(first.attemptedRevision == first.revision && first.issue?.reason == .uncertain)
        precondition(first.attemptedMaterial?.meaningNote == "offline note")
        precondition(second.attemptedRevision == nil)
      }
      print("PASS: fresh process restored production models, pending work and account isolation")
    }
  }
}

/// Synthetic service only. An unexpected operation cannot contact a real account.
private actor ProbeServer: WaniKaniService {
  let accountID: String
  let profile: StudyAccountProfile
  let offline: Bool
  let catalog: StudyDownload?
  init(
    accountID: String, profile: StudyAccountProfile = .init(username: "first"),
    offline: Bool = false, catalog: StudyDownload? = nil
  ) {
    self.accountID = accountID
    self.profile = profile
    self.offline = offline
    self.catalog = catalog
  }
  func account(token: String) throws -> WaniKaniAccount {
    if offline { throw URLError(.notConnectedToInternet) }
    return .init(
      id: accountID, username: profile.username, level: profile.level,
      onVacation: profile.vacationStartedAt != nil, startedAt: profile.startedAt, profile: profile)
  }
  func download(token: String, subjects: [CatalogSubject], cursors: [String: String]) throws
    -> StudyDownload
  {
    guard let catalog else { throw WaniKaniClient.APIError.invalidPayload }
    return catalog
  }
  func assignment(subjectID: Int64, token: String) -> CatalogAssignment? { nil }
  func material(subjectID: Int64, token: String) -> WaniKaniMaterial? { nil }
  func submit(_ answer: StudyReviewSubmission, token: String, now: Date) throws -> CatalogAssignment
  { throw URLError(.timedOut) }
  func writeMaterial(_ value: StudyMaterial, serverID: Int64?, token: String) throws
    -> WaniKaniMaterial
  { throw URLError(.timedOut) }
}
