import Darwin
import Foundation
import StudyCore
import StudyPersistence

/// Separate-process durability check of the production store, with synthetic data only.
@main struct Probe {
  static func main() async throws {
    let args = CommandLine.arguments
    var modes = [
      "write", "read", "read-attempts", "write-catalog", "read-catalog", "import-handoff",
      "save-handoff", "activate-handoff", "edit-handoff", "read-handoff", "rollback-handoff",
      "verify-rollback-handoff", "write-native-selection", "read-native-selection",
    ]
    #if DEBUG
      modes += ["write-native-baseline", "read-native-baseline"] + NativeStoreUpgrade.commands
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
    if args[1].hasSuffix("native-selection") {
      try await nativeSelection(args[1], store: store, url: URL(filePath: args[2]))
      return
    }
    if args[1].hasSuffix("-handoff") {
      try await handoff(args[1], store: store, url: URL(filePath: args[2]))
      return
    }

    if args[1].hasSuffix("catalog") {
      if args[1] == "write-catalog" {
        var profile = StudyAccountProfile(username: "upgrade")
        profile.level = 4
        profile.maxLevelGranted = 60
        var source = LegacyStudyExport(schemaVersion: 15, profile: profile)
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
            serverID: 242, value: .init(subjectID: 42, meaningNote: "pending migration note"),
            pending: true, legacyRevision: 2)
        ]
        try await store.importLegacyAccount(
          source, sourceID: "fixture", verifiedAccountID: "upgrade", verifiedUsername: "upgrade",
          credentialID: "upgrade")
        print("PASS: wrote production catalog, assignment and pending note")
      } else {
        let account = try await store.accountState(accountID: "upgrade")
        precondition(account?.profile.level == 4 && account?.catalogRefreshID == nil)
        let subject = try await store.catalog(accountID: "upgrade").first!
        let assignment = try await store.assignments(accountID: "upgrade").first!
        let note = try await store.materials(accountID: "upgrade").first!
        precondition(subject.japanese == "猫" && subject.meaningMnemonic == "Saved mnemonic")
        precondition(assignment.id == 142 && assignment.level == 4 && assignment.srsStage == 5)
        precondition(
          note.pending && note.material.meaningNote == "pending migration note"
            && note.serverID == 242)
        precondition(note.issue?.reason == .uncertain)
        let handoff = try await store.legacyHandoff(sourceID: "fixture")
        precondition(handoff == nil)
        print(
          "PASS: fresh process reopened catalog, assignment and pending note; old receipt cannot select a writer"
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
  init(
    accountID: String, profile: StudyAccountProfile = .init(username: "first"),
    offline: Bool = false
  ) {
    self.accountID = accountID
    self.profile = profile
    self.offline = offline
  }
  func account(token: String) throws -> WaniKaniAccount {
    if offline { throw URLError(.notConnectedToInternet) }
    return .init(
      id: accountID, username: profile.username, level: profile.level,
      onVacation: profile.vacationStartedAt != nil, startedAt: profile.startedAt, profile: profile)
  }
  func download(token: String) throws -> StudyDownload {
    throw WaniKaniClient.APIError.invalidPayload
  }
  func assignment(subjectID: Int64, token: String) -> CatalogAssignment? { nil }
  func material(subjectID: Int64, token: String) -> WaniKaniMaterial? { nil }
  func submit(_ answer: StudyReviewSubmission, token: String, now: Date) throws -> CatalogAssignment
  { throw URLError(.timedOut) }
  func writeMaterial(_ value: StudyMaterial, serverID: Int64?, token: String) throws
    -> WaniKaniMaterial
  { throw URLError(.timedOut) }
}

/// A disposable defaults domain that can terminate before the first native preference write.
private final class ProbeDefaults: UserDefaults, @unchecked Sendable {
  private let crashBeforeHydration: Bool
  init?(suite: String, crashBeforeHydration: Bool) {
    self.crashBeforeHydration = crashBeforeHydration
    super.init(suiteName: suite)
  }
  override func set(_ value: Any?, forKey key: String) {
    if crashBeforeHydration && key == "native.reviewPreferences" {
      FileHandle.standardOutput.write(
        Data("CHECKPOINT: activated writer before preference hydration\n".utf8))
      _exit(86)
    }
    super.set(value, forKey: key)
  }
}

@MainActor private struct ProbeCredentials: StudyCredentialStore {
  let url: URL
  let command: String
  func load() throws -> String? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try String(contentsOf: url, encoding: .utf8)
  }
  func save(_ token: String) throws {
    if command == "import-handoff" { crash("prepared import before credential write") }
    // A disposable synthetic file, never the user's Keychain or defaults.
    try Data(token.utf8).write(to: url, options: .atomic)
    if command == "save-handoff" { crash("saved credential before writer activation") }
  }
  func remove() throws { try FileManager.default.removeItem(at: url) }
  func crash(_ message: String) -> Never {
    FileHandle.standardOutput.write(Data("CHECKPOINT: \(message)\n".utf8))
    _exit(86)  // Skip SwiftData/Swift teardown to exercise committed durability.
  }
}

extension Probe {
  @MainActor private static func handoff(_ command: String, store: StudyStore, url: URL)
    async throws
  {
    var profile = StudyAccountProfile(username: "handoff-fixture")
    profile.level = 1
    profile.startedAt = 100
    profile.maxLevelGranted = 60
    var source = LegacyStudyExport(schemaVersion: 15, profile: profile)
    var subject = CatalogSubject(id: 42, kind: .kanji)
    subject.level = 1
    subject.japanese = "猫"
    subject.meanings = [.init("cat", role: .primary)]
    source.subjects = [subject]
    var assignment = CatalogAssignment(id: 142, subjectID: 42, kind: .kanji)
    assignment.level = 1
    assignment.srsStage = 3
    assignment.availableAt = 100
    source.assignments = [assignment]
    source.pendingReviews = [
      .init(
        assignment: assignment,
        submission: .init(
          itemID: 0,
          subjectID: 42, assignmentID: 142, isLesson: false, meaningWrong: true,
          readingWrong: false,
          meaningWrongCount: 2, readingWrongCount: 0, createdAt: 120))
    ]
    source.materials = [
      .init(
        serverID: 242,
        value: .init(
          subjectID: 42,
          meaningNote: "offline\u{0000}note\n猫", meaningSynonyms: ["kitty"]), pending: true,
        legacyRevision: 9)
    ]
    if command == "rollback-handoff" {
      source.pendingReviews = [
        .init(
          assignment: assignment,
          submission: .init(
            itemID: 0,
            subjectID: 42, assignmentID: 999, isLesson: false, meaningWrong: false,
            readingWrong: false,
            meaningWrongCount: 0, readingWrongCount: 0, createdAt: 120))
      ]
    }
    let sourceBefore = try sourceBytes(source)
    let frozen = source
    let credentials = ProbeCredentials(
      url: url.appendingPathExtension("synthetic-credential"), command: command)
    let before = try await store.legacyHandoff(sourceID: "ios-main")
    let server = ProbeServer(
      accountID: "handoff-account", profile: profile,
      offline: command != "import-handoff" && command != "rollback-handoff")
    let preferenceDomain = "usagi-probe-" + StudyCredentialID.forToken(url.path)
    let defaults = ProbeDefaults(
      suite: preferenceDomain, crashBeforeHydration: command == "activate-handoff")!
    if command == "import-handoff" || command == "rollback-handoff" {
      defaults.removePersistentDomain(forName: preferenceDomain)
    }
    let bootstrap = StudyLegacyBootstrap(
      store: store, sourceID: "ios-main", credentials: credentials,
      preferences: .init(defaults: defaults), client: { _ in server },
      readLegacy: {
        precondition(
          command != "read-handoff" && command != "edit-handoff", "Retired source was accessed")
        return .init(token: "synthetic-handoff-token", account: frozen, preferences: .init())
      })
    let savedCredential = try credentials.load()
    if command == "verify-rollback-handoff" {
      let catalog = try await store.catalog(accountID: "handoff-account")
      let account = try await store.accountState(accountID: "handoff-account")
      let reviews = try await store.pendingReviews(accountID: "handoff-account")
      let materials = try await store.materials(accountID: "handoff-account")
      let snapshot = try await store.snapshot(
        credentialID: StudyCredentialID.forToken("synthetic-handoff-token"))
      precondition(before == nil && savedCredential == nil && account == nil && snapshot == nil)
      precondition(catalog.isEmpty && reviews.isEmpty && materials.isEmpty)
      print(
        "PASS: fresh process found no partial import, binding, credential or upload after rollback")
      return
    }
    if command == "rollback-handoff" {
      precondition(before == nil && savedCredential == nil)
      do {
        _ = try await bootstrap.activate()
        preconditionFailure("Malformed import unexpectedly activated")
      } catch LegacyImportError.invalidData {
        let sourceAfter = try sourceBytes(frozen)
        precondition(sourceAfter == sourceBefore)
        credentials.crash("failed import rolled back before credential write")
      }
    }
    if command == "import-handoff" {
      precondition(before == nil && savedCredential == nil)
    } else if command == "save-handoff" {
      precondition(before?.activated == false && savedCredential == nil)
    } else if command == "activate-handoff" {
      precondition(before?.activated == false && savedCredential == "synthetic-handoff-token")
    } else {
      precondition(before?.activated == true)
    }
    let result = try await bootstrap.activate()
    precondition(result.activated && result.accountID == "handoff-account")
    precondition(
      result.preferences == LegacyStudyPreferences() && result.mediaLayout == .legacyDocuments)
    let preferences = try JSONDecoder().decode(
      ReviewPreferences.self, from: defaults.data(forKey: "native.reviewPreferences")!)
    precondition(preferences == LegacyStudyPreferences().review)
    precondition(defaults.object(forKey: "userApiToken") == nil)

    let sourceAfter = try sourceBytes(frozen)
    precondition(sourceAfter == sourceBefore)
    if command == "activate-handoff" {
      credentials.crash("native writer selected before process exit")
    }
    if command == "edit-handoff" {
      let review = try await store.pendingReviews(accountID: result.accountID).first!
      precondition(review.attempted && review.submission == frozen.pendingReviews[0].submission)
      let note = try await store.materials(accountID: result.accountID).first!
      precondition(
        note.pending && note.issue?.reason == .uncertain
          && note.material == frozen.materials[0].value)
      try await store.acknowledgeReview(review)
      try await store.saveMaterial(
        .init(subjectID: 42, meaningNote: "new native work"),
        accountID: result.accountID, expectedRevision: note.revision)
      try await store.removeSnapshot(credentialID: result.credentialID)
      try credentials.remove()  // Simulated logout; the retired writer must stay retired.
      print("PASS: native work changed after activation; synthetic credential and snapshot removed")
    } else if command == "read-handoff" {
      let reviews = try await store.pendingReviews(accountID: result.accountID)
      let notes = try await store.materials(accountID: result.accountID)
      let snapshot = try await store.snapshot(credentialID: result.credentialID)
      let credential = try credentials.load()
      precondition(reviews.isEmpty && notes.first?.material.meaningNote == "new native work")
      precondition(snapshot == nil && credential == nil)
      print(
        "PASS: restarted offline after logout without reading retired data or resurrecting old work"
      )
    } else {
      preconditionFailure("Expected an abrupt checkpoint exit")
    }
  }
  private static func sourceBytes(_ source: LegacyStudyExport) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(source)
  }
}

extension Probe {
  @MainActor private static func nativeSelection(_ command: String, store: StudyStore, url: URL)
    async throws
  {
    let suite = "native-selection-probe-" + StudyCredentialID.forToken(url.path)
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let credentials = ProbeCredentials(
      url: url.appendingPathExtension("synthetic-token"), command: command)
    let bootstrap = StudyLegacyBootstrap(
      store: store, sourceID: "fresh-native-app",
      credentials: credentials, preferences: .init(defaults: defaults),
      readLegacy: {
        throw CocoaError(.fileReadNoPermission)
      })
    let result = try await bootstrap.prepareApplication(legacyToken: {
      if command == "write-native-selection" { return "" }
      throw CocoaError(.fileReadNoPermission)
    })
    precondition(result == .native)
    let previous = try await store.legacyHandoff(sourceID: "fresh-native-app")
    precondition(previous == nil)
    if command == "write-native-selection" {
      credentials.crash("selected native writer without a legacy account")
    }
    print(
      "PASS: fresh process retained native writer selection without inspecting retired credentials or source"
    )
  }
}
