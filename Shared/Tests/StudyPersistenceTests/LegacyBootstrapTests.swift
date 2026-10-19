import Foundation
import StudyCore
import StudyTestSupport
import Testing

@testable import StudyPersistence

private actor BootstrapServer: WaniKaniAccountReader {
  var identity: WaniKaniAccount
  var offline = false
  var gate: StudyTaskGate?
  private(set) var reads = 0
  init(_ profile: StudyAccountProfile) {
    var fresh = profile
    fresh.level = 13
    fresh.maxLevelGranted = 3
    fresh.vacationStartedAt = 200
    identity = .init(
      id: "migration-account", username: profile.username, level: fresh.level,
      onVacation: true, startedAt: profile.startedAt, profile: fresh)
  }
  func configure(offline: Bool = false, gate: StudyTaskGate? = nil) {
    self.offline = offline
    self.gate = gate
  }
  func replaceIdentity(_ value: WaniKaniAccount) { identity = value }
  func account(token: String) async throws -> WaniKaniAccount {
    reads += 1
    if let gate {
      self.gate = nil
      await gate.pause()
    }
    if offline { throw URLError(.notConnectedToInternet) }
    return identity
  }

}

@MainActor private final class BootstrapCredentials: StudyCredentialStore {
  enum Fault: CaseIterable { case beforeSave, afterSave, discardSave }
  var token: String?
  var fault: Fault?
  var failLoads = false
  private(set) var saves = 0
  func load() throws -> String? {
    if failLoads { throw CocoaError(.fileReadNoPermission) }
    return token
  }
  func save(_ token: String) throws {
    saves += 1
    if fault == .beforeSave { throw CocoaError(.fileWriteNoPermission) }
    if fault != .discardSave { self.token = token }
    if fault == .afterSave { throw CocoaError(.fileWriteNoPermission) }
  }
  func remove() { token = nil }
}

@MainActor private final class BootstrapInput {
  var source: StudyLegacySource
  var fail = false
  private(set) var reads = 0
  init() {
    var profile = StudyAccountProfile(username: "migration-fixture")
    profile.level = 12
    profile.startedAt = 100
    profile.maxLevelGranted = 60
    var account = LegacyStudyExport(schemaVersion: 15, profile: profile)
    var subject = CatalogSubject(id: 42, kind: .kanji)
    subject.level = 12
    subject.japanese = "猫"
    subject.meanings = [.init("cat", role: .primary)]
    account.subjects = [subject]
    var assignment = CatalogAssignment(id: 142, subjectID: 42, kind: .kanji)
    assignment.level = 12
    assignment.srsStage = 3
    assignment.availableAt = 100
    account.assignments = [assignment]
    account.pendingReviews = [
      .init(
        assignment: assignment,
        submission: .init(
          itemID: 0,
          subjectID: 42, assignmentID: 142, isLesson: false, meaningWrong: true,
          readingWrong: false,
          meaningWrongCount: 2, readingWrongCount: 0, createdAt: 120))
    ]
    account.materials = [
      .init(
        serverID: 242,
        value: .init(
          subjectID: 42,
          meaningNote: "offline\u{0000}note\n猫", meaningSynonyms: ["kitty"]), pending: true,
        legacyRevision: 9)
    ]
    source = .init(token: "synthetic-migration-token", account: account, preferences: .init())
  }
  func read() throws -> StudyLegacySource {
    reads += 1
    if fail { throw CocoaError(.fileReadNoSuchFile) }
    return source
  }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct LegacyBootstrapTests {
  @MainActor private final class Environment {
    let domain = "usagi-bootstrap-" + UUID().uuidString
    let defaults: UserDefaults
    let store: StudyStore
    let input = BootstrapInput()
    let credentials = BootstrapCredentials()
    let server: BootstrapServer
    deinit { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
    init() async throws {
      defaults = UserDefaults(suiteName: domain)!
      store = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
      server = BootstrapServer(input.source.account.profile)
    }
    func bootstrap() -> StudyLegacyBootstrap {
      .init(
        store: store, sourceID: "ios-main", credentials: credentials,
        preferences: .init(defaults: defaults), client: { _ in self.server },
        readLegacy: { try self.input.read() })
    }
  }

  @Test func verifiedSourceCredentialProfileAndProtectedWorkActivateTogether() async throws {
    let env = try await Environment()
    let result = try await env.bootstrap().activate()
    #expect(result.activated && result.accountID == "migration-account")
    #expect(result.credentialID == StudyCredentialID.forToken(env.input.source.token))
    #expect(env.credentials.token == env.input.source.token)
    #expect(await env.server.reads == 1)
    let snapshot = try #require(await env.store.snapshot(credentialID: result.credentialID))
    #expect(snapshot.currentLevel == 13 && snapshot.onVacation && snapshot.pendingReviews == 1)
    #expect(
      try await env.store.accountState(accountID: result.accountID)?.profile.maxLevelGranted == 3)
    let answer = try #require(await env.store.pendingReviews(accountID: result.accountID).first)
    #expect(
      answer.attempted && answer.submission == env.input.source.account.pendingReviews[0].submission
    )
    let note = try #require(await env.store.materials(accountID: result.accountID).first)
    #expect(note.pending && note.issue?.reason == .uncertain)
    #expect(note.material == env.input.source.account.materials[0].value)
  }

  @Test(arguments: BootstrapCredentials.Fault.allCases)
  fileprivate func credentialFailuresRemainPreparedAndResumeOfflineAfterRecreatingOwner(
    _ fault: BootstrapCredentials.Fault
  ) async throws {
    let env = try await Environment()
    env.credentials.fault = fault
    await #expect(throws: (any Error).self) { try await env.bootstrap().activate() }
    let prepared = try #require(await env.store.legacyHandoff(sourceID: "ios-main"))
    #expect(!prepared.activated)
    #expect(try await env.store.pendingReviews(accountID: prepared.accountID).count == 1)
    env.credentials.fault = nil
    await env.server.configure(offline: true)
    let resumed = try await env.bootstrap().activate()
    #expect(resumed.activated && resumed.credentialID == prepared.credentialID)
    #expect(await env.server.reads == 1)
  }

  @Test func wrongLegacyIdentityNeverImportsOrWritesACredential() async throws {
    let env = try await Environment()
    let wrong = WaniKaniAccount(id: "other", username: "other", level: 1, onVacation: false)
    await env.server.replaceIdentity(wrong)
    await #expect(throws: StudySignInError.self) { try await env.bootstrap().activate() }
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main") == nil)
    #expect(try await env.store.catalog(accountID: "other").isEmpty)
    #expect(env.credentials.token == nil && env.credentials.saves == 0)
  }

  @Test func signupMismatchOrIncompleteVerificationCannotAuthorizeTheHandoff() async throws {
    for startedAt: Int64? in [99, nil, 100] {
      let env = try await Environment()
      await env.server.replaceIdentity(
        .init(
          id: "migration-account", username: "migration-fixture",
          level: 12, onVacation: false, startedAt: startedAt))
      await #expect(throws: (any Error).self) { try await env.bootstrap().activate() }
      #expect(try await env.store.accountState(accountID: "migration-account") == nil)
      #expect(env.credentials.saves == 0)
    }
  }

  @Test(arguments: [false, true]) func sourceChangesWhileVerifyingCannotBeImported(
    changeToken: Bool
  ) async throws {
    let env = try await Environment()
    let gate = StudyTaskGate()
    await env.server.configure(gate: gate)
    let bootstrap = env.bootstrap()
    let activation = Task { try await bootstrap.activate() }
    await gate.waitForEntry()
    var changed = env.input.source.account
    changed.profile.level += 1
    env.input.source = .init(
      token: changeToken ? "different-token" : env.input.source.token,
      account: changeToken ? env.input.source.account : changed,
      preferences: env.input.source.preferences)
    await gate.resume()
    await #expect(throws: StudyBootstrapError.self) { try await activation.value }
    #expect(try await env.store.accountState(accountID: "migration-account") == nil)
    #expect(env.credentials.saves == 0)
  }

  @Test func anotherSavedCredentialIsNeverOverwritten() async throws {
    let env = try await Environment()
    env.credentials.token = "another-account-token"
    await #expect(throws: StudyBootstrapError.self) { try await env.bootstrap().activate() }
    #expect(env.credentials.token == "another-account-token" && env.credentials.saves == 0)
    #expect(await env.server.reads == 0)
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main") == nil)
  }

  @Test func credentialReplacementDuringVerificationStopsBeforeActivation() async throws {
    let env = try await Environment()
    let gate = StudyTaskGate()
    await env.server.configure(gate: gate)
    let bootstrap = env.bootstrap()
    let activation = Task { try await bootstrap.activate() }
    await gate.waitForEntry()
    env.credentials.token = "newer-account-token"
    await gate.resume()
    await #expect(throws: StudyBootstrapError.self) { try await activation.value }
    #expect(env.credentials.token == "newer-account-token" && env.credentials.saves == 0)
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main")?.activated == false)
  }

  @Test func changedPreparedSourceCannotResumeOrReplaceItsExactPendingPayload() async throws {
    let env = try await Environment()
    env.credentials.fault = .beforeSave
    await #expect(throws: CocoaError.self) { try await env.bootstrap().activate() }
    var changed = env.input.source.account
    changed.profile.level += 1
    env.input.source = .init(
      token: env.input.source.token, account: changed, preferences: env.input.source.preferences)
    env.credentials.fault = nil
    await env.server.configure(offline: true)
    await #expect(throws: LegacyImportError.self) { try await env.bootstrap().activate() }
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main")?.activated == false)
    #expect(
      try await env.store.materials(accountID: "migration-account").first?.material.meaningNote
        == "offline\u{0000}note\n猫")
    #expect(env.credentials.saves == 1 && env.credentials.token == nil)
  }

  @Test func activatedWriterChoiceSurvivesLogoutWithoutReadingRetiredDataOrCredentials()
    async throws
  {
    let env = try await Environment()
    let first = try await env.bootstrap().activate()
    let answer = try #require(await env.store.pendingReviews(accountID: first.accountID).first)
    try await env.store.acknowledgeReview(answer)
    let note = try #require(await env.store.materials(accountID: first.accountID).first)
    try await env.store.saveMaterial(
      .init(subjectID: 42, meaningNote: "new native work"),
      accountID: first.accountID, expectedRevision: note.revision)
    try await env.store.removeSnapshot(credentialID: first.credentialID)
    env.credentials.remove()
    env.credentials.failLoads = true
    env.input.fail = true
    let reads = env.input.reads
    await env.server.configure(offline: true)
    #expect(try await env.bootstrap().activate() == first)
    #expect(env.input.reads == reads && env.credentials.token == nil)
    #expect(await env.server.reads == 1)
    #expect(try await env.store.pendingReviews(accountID: first.accountID).isEmpty)
    #expect(try await env.store.snapshot(credentialID: first.credentialID) == nil)
    #expect(
      try await env.store.materials(accountID: first.accountID).first?.material.meaningNote
        == "new native work")
  }

  @Test func concurrentScenesShareOneCredentialHandoff() async throws {
    let env = try await Environment()
    let gate = StudyTaskGate()
    await env.server.configure(gate: gate)
    let bootstrap = env.bootstrap()
    async let first = bootstrap.activate()
    async let second = bootstrap.activate()
    await gate.waitForEntry()
    await gate.resume()
    let values = try await (first, second)
    #expect(values.0 == values.1 && values.0.activated)
    #expect(await env.server.reads == 1)
    #expect(env.credentials.saves == 1)
  }

  @Test func invalidImportRollsBackBeforeCredentialWriteOrWriterChoice() async throws {
    let env = try await Environment()
    var invalid = env.input.source.account
    invalid.pendingReviews = [
      .init(
        assignment: invalid.assignments[0],
        submission: .init(
          itemID: 0,
          subjectID: 42, assignmentID: 999, isLesson: false, meaningWrong: false,
          readingWrong: false,
          meaningWrongCount: 0, readingWrongCount: 0, createdAt: nil))
    ]
    env.input.source = .init(
      token: env.input.source.token, account: invalid, preferences: env.input.source.preferences)
    await #expect(throws: LegacyImportError.self) { try await env.bootstrap().activate() }
    #expect(try await env.store.catalog(accountID: "migration-account").isEmpty)
    #expect(try await env.store.accountState(accountID: "migration-account") == nil)
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main") == nil)
    #expect(env.credentials.saves == 0)
  }

  @Test func importCommittedBeforeItsBindingIsReverifiedWithoutResurrectingWork() async throws {
    let env = try await Environment()
    let source = env.input.source.account
    try await env.store.importLegacyAccount(
      source, sourceID: "ios-main", verifiedAccountID: "migration-account",
      verifiedUsername: source.profile.username,
      credentialID: StudyCredentialID.forToken(env.input.source.token))
    let answer = try #require(await env.store.pendingReviews(accountID: "migration-account").first)
    try await env.store.acknowledgeReview(answer)
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main") == nil)
    #expect(try await env.bootstrap().activate().activated)
    #expect(await env.server.reads == 1)
    #expect(try await env.store.pendingReviews(accountID: "migration-account").isEmpty)
  }

  @Test func missingPreparedSnapshotDoesNotResurrectItOrAuthorizeAWriter() async throws {
    let env = try await Environment()
    env.credentials.fault = .beforeSave
    await #expect(throws: CocoaError.self) { try await env.bootstrap().activate() }
    let prepared = try #require(await env.store.legacyHandoff(sourceID: "ios-main"))
    try await env.store.removeSnapshot(credentialID: prepared.credentialID)
    env.credentials.fault = nil
    await #expect(throws: StudyBootstrapError.self) { try await env.bootstrap().activate() }
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main")?.activated == false)
    #expect(try await env.store.snapshot(credentialID: prepared.credentialID) == nil)
    #expect(env.credentials.token == nil)
  }
  @Test func cancelledSceneCannotInterruptTheSharedHandoff() async throws {
    let env = try await Environment()
    let gate = StudyTaskGate()
    await env.server.configure(gate: gate)
    let bootstrap = env.bootstrap()
    let first = Task { try await bootstrap.activate() }
    await gate.waitForEntry()
    first.cancel()
    let second = Task { try await bootstrap.activate() }
    await gate.resume()
    await #expect(throws: CancellationError.self) { try await first.value }
    let result = try await second.value
    #expect(result.activated && env.credentials.token == env.input.source.token)
    #expect(await env.server.reads == 1)
    #expect(env.credentials.saves == 1)
  }
  @Test func changedPreferencesCannotPassVerificationOrResumeAPreparedImport() async throws {
    let env = try await Environment()
    let gate = StudyTaskGate()
    await env.server.configure(gate: gate)
    let bootstrap = env.bootstrap()
    let activation = Task { try await bootstrap.activate() }
    await gate.waitForEntry()
    var changed = env.input.source.preferences
    changed.review.exactMatch.toggle()
    env.input.source = .init(
      token: env.input.source.token, account: env.input.source.account, preferences: changed)
    await gate.resume()
    await #expect(throws: StudyBootstrapError.self) { try await activation.value }
    #expect(
      try await env.store.legacyHandoff(sourceID: "ios-main") == nil && env.credentials.saves == 0)
    env.credentials.fault = .beforeSave
    await #expect(throws: CocoaError.self) { try await env.bootstrap().activate() }
    #expect(env.defaults.object(forKey: "native.reviewPreferences") == nil)
    var newer = changed
    newer.audio.cellular.toggle()
    env.input.source = .init(
      token: env.input.source.token, account: env.input.source.account, preferences: newer)
    env.credentials.fault = nil
    await env.server.configure(offline: true)
    await #expect(throws: StudyBootstrapError.self) { try await env.bootstrap().activate() }
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main")?.activated == false)
    #expect(try await env.store.pendingReviews(accountID: "migration-account").count == 1)
  }
  @Test func activatedReceiptRestoresMissingPreferencesWithoutReadingTheRetiredSource() async throws
  {
    let env = try await Environment()
    let first = try await env.bootstrap().activate()
    #expect(
      first.preferences == env.input.source.preferences && first.mediaLayout == .legacyDocuments)
    env.defaults.removePersistentDomain(forName: env.domain)
    env.input.fail = true
    env.credentials.failLoads = true
    await env.server.configure(offline: true)
    let reads = env.input.reads
    #expect(try await env.bootstrap().activate() == first)
    let data = try #require(env.defaults.data(forKey: "native.reviewPreferences"))
    #expect(
      try JSONDecoder().decode(ReviewPreferences.self, from: data) == first.preferences?.review)
    var edited = try JSONDecoder().decode(ReviewPreferences.self, from: data)
    edited.exactMatch.toggle()
    let bytes = try JSONEncoder().encode(edited)
    env.defaults.set(bytes, forKey: "native.reviewPreferences")
    #expect(try await env.bootstrap().activate() == first)
    #expect(
      env.defaults.data(forKey: "native.reviewPreferences") == bytes && env.input.reads == reads)
    #expect(await env.server.reads == 1)
  }
  @Test func preferenceRecoveryNeverReopensAnActivatedLegacyWriter() async throws {
    let env = try await Environment()
    let corrupt = Data("invalid-native-preference".utf8)
    env.defaults.set(corrupt, forKey: "native.reviewPreferences")
    await #expect(throws: StudyPreferenceImportError.self) { try await env.bootstrap().activate() }
    let saved = try #require(await env.store.legacyHandoff(sourceID: "ios-main"))
    #expect(saved.activated && env.defaults.data(forKey: "native.reviewPreferences") == corrupt)
    env.defaults.removeObject(forKey: "native.reviewPreferences")
    env.input.fail = true
    env.credentials.failLoads = true
    await env.server.configure(offline: true)
    #expect(try await env.bootstrap().activate() == saved)
    #expect(try await env.store.pendingReviews(accountID: saved.accountID).count == 1)
  }
  @Test func earlierReceiptBytesKeepTheirOneWayChoiceWithoutPreferenceMetadata() async throws {
    let env = try await Environment()
    let first = try await env.bootstrap().activate()
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
    object.removeValue(forKey: "preferences")
    let decoded = try JSONDecoder().decode(
      StudyLegacyHandoff.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.activated && decoded.preferences == nil && decoded.mediaLayout == .native)
    #expect(decoded.accountID == first.accountID && decoded.credentialID == first.credentialID)
  }
  @Test func configuredEndpointSelectsTheAccountVerifierAndIsPreservedInNativeSettings()
    async throws
  {
    let env = try await Environment()
    let endpoint = URL(string: "http://localhost:8080/v2")!
    var preferences = env.input.source.preferences
    preferences.apiBaseURL = endpoint
    env.input.source = .init(
      token: env.input.source.token, account: env.input.source.account, preferences: preferences)
    let server = env.server
    let bootstrap = StudyLegacyBootstrap(
      store: env.store, sourceID: "ios-main", credentials: env.credentials,
      preferences: .init(defaults: env.defaults),
      client: { url in
        #expect(url == endpoint)
        return server
      }, readLegacy: { try env.input.read() })
    let result = try await bootstrap.activate()
    #expect(result.preferences?.apiBaseURL == endpoint)
    #expect(env.defaults.string(forKey: "native.apiBaseUrl") == endpoint.absoluteString)
  }

  @Test func freshNativeSelectionNeverReadsRetiredDataOrCredentialsAgain() async throws {
    let env = try await Environment()
    #expect(try await env.bootstrap().prepareApplication(legacyToken: { "" }) == .native)
    #expect(try await env.store.nativeApplicationActivated(sourceID: "ios-main"))
    env.input.fail = true
    env.credentials.failLoads = true
    await env.server.configure(offline: true)
    #expect(
      try await env.bootstrap().prepareApplication(legacyToken: {
        throw CocoaError(.fileReadNoPermission)
      }) == .native)
    #expect(env.input.reads == 0 && env.credentials.saves == 0)
    #expect(await env.server.reads == 0)
  }
  @Test func existingLegacyAccountSelectsItsVerifiedHandoffAndRetainsProtectedWork() async throws {
    let env = try await Environment()
    #expect(
      try await env.bootstrap().prepareApplication(legacyToken: { env.input.source.token })
        == .legacyDocuments)
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main")?.activated == true)
    #expect(try await env.store.pendingReviews(accountID: "migration-account").count == 1)
    #expect(env.credentials.saves == 1)
  }
  @Test func failedLegacyVerificationCannotSelectAFreshNativeApplication() async throws {
    let env = try await Environment()
    await env.server.configure(offline: true)
    await #expect(throws: URLError.self) {
      try await env.bootstrap().prepareApplication(legacyToken: { env.input.source.token })
    }
    #expect(try await !env.store.nativeApplicationActivated(sourceID: "ios-main"))
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main") == nil)
    #expect(env.credentials.token == nil && env.credentials.saves == 0)
  }
  @Test func activatedSelectionAfterLogoutDoesNotInspectTheOldTokenOrSource() async throws {
    let env = try await Environment()
    _ = try await env.bootstrap().activate()
    let reads = env.input.reads
    env.credentials.remove()
    env.credentials.failLoads = true
    env.input.fail = true
    await env.server.configure(offline: true)
    #expect(
      try await env.bootstrap().prepareApplication(legacyToken: {
        throw CocoaError(.fileReadNoPermission)
      }) == .legacyDocuments)
    #expect(env.input.reads == reads && env.credentials.token == nil)
    #expect(await env.server.reads == 1)
  }
  @Test func preparedSourceWithALostOldTokenDoesNotBecomeAFreshInstallation() async throws {
    let env = try await Environment()
    env.credentials.fault = .beforeSave
    await #expect(throws: CocoaError.self) { try await env.bootstrap().activate() }
    env.credentials.fault = nil
    let original = env.input.source
    env.input.source = .init(
      token: "", account: original.account, preferences: original.preferences)
    await #expect(throws: StudyBootstrapError.self) {
      try await env.bootstrap().prepareApplication(legacyToken: { "" })
    }
    #expect(try await !env.store.nativeApplicationActivated(sourceID: "ios-main"))
    #expect(try await env.store.legacyHandoff(sourceID: "ios-main")?.activated == false)
  }

}
