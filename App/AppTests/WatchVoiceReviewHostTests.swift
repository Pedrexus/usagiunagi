#if os(iOS)
  import Foundation
  import StudyCore
  import StudyPersistence
  import StudySpeech
  import Testing

  @testable import Tsurukame

  private actor WatchFinishedCapture: VoiceCapture {
    private let cleanupGate: AssemblyGate?
    private let reading: String
    private(set) var locales: [String] = []
    private var gated = false

    init(cleanupGate: AssemblyGate? = nil, reading: String = "いち") {
      self.cleanupGate = cleanupGate
      self.reading = reading
    }

    func start(
      id: UUID, locale: Locale, downloadModel: Bool, report: @escaping VoiceCaptureReport
    ) async throws {
      locales.append(locale.identifier)
      await report(
        .segment(
          text: locale.language.languageCode == .japanese ? reading : "One.",
          start: 0, end: 1, isFinal: true))
      await report(.finished)
    }

    func finish(id: UUID) {}
    func cancel(id: UUID) async {
      guard let cleanupGate, !gated else { return }
      gated = true
      await cleanupGate.pause()
    }
  }

  @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
  struct WatchVoiceReviewHostTests {
    private let account = "assembly-fixture"

    @Test(arguments: ["いち", "イチ", "イち"])
    func pairedAnswersPreserveKanaAndCreateOneOrdinarySavedReview(_ kana: String) async throws {
      let fixture = NativeAppAssemblyTests()
      let (services, store, server, _, domain, directory) = try await fixture.environment()
      defer { fixture.cleanup(domain, directory) }
      await services.model.restore()
      var preferences = ReviewPreferences()
      preferences.sessionOptions.groupMeaningReading = true
      preferences.sessionOptions.meaningFirst = true
      services.defaults.set(
        try JSONEncoder().encode(preferences), forKey: "native.reviewPreferences")
      let capture = WatchFinishedCapture(reading: kana)
      let host = WatchReviewHost(services: services, capture: { _ in capture })
      let id = UUID()
      let opened = await host.receive(.init(action: .start, runID: id))
      #expect(opened.outcome == .ready && opened.prompt?.reading == false)
      #expect(services.audio.voiceInputActive)
      let meaningRevision = try #require(opened.revision)
      let meaning = WatchReviewRequest(
        action: .answer, runID: id, revision: meaningRevision, audio: Data([1]))
      let reading = await host.receive(meaning)
      #expect(reading.outcome == .correct && reading.prompt?.reading == true)
      let readingRevision = try #require(reading.revision)
      let finished = await host.receive(
        .init(
          action: .answer, runID: id, revision: readingRevision, audio: Data([2])))
      #expect(finished.outcome == .finished && finished.completed == 1 && finished.correct == 1)
      #expect(finished.heard == kana)
      #expect(!services.audio.voiceInputActive)
      let pending = try await store.pendingReviews(accountID: account)
      #expect(pending.count == 1 && pending[0].submission.subjectID == 1)
      #expect(!pending[0].attempted && pending[0].submission.meaningWrongCount == 0)
      #expect(try await store.session(accountID: account) == nil)
      #expect(await capture.locales.map { String($0.prefix(2)) } == ["en", "ja"])
      #expect(await host.receive(meaning).outcome == .unavailable)
      #expect(
        try await store.pendingReviews(accountID: account).map(\.revision)
          == pending.map(\.revision))
      #expect(await server.writes == 0)
    }

    @Test func pauseDuringRecognizerCleanupDiscardsTheUnsubmittedAnswerAndLease() async throws {
      let fixture = NativeAppAssemblyTests()
      let (services, store, server, _, domain, directory) = try await fixture.environment()
      defer { fixture.cleanup(domain, directory) }
      await services.model.restore()
      let gate = AssemblyGate()
      let capture = WatchFinishedCapture(cleanupGate: gate)
      let host = WatchReviewHost(services: services, capture: { _ in capture })
      let id = UUID()
      let opened = await host.receive(.init(action: .start, runID: id))
      let revision = try #require(opened.revision)
      let answer = Task {
        await host.receive(
          .init(action: .answer, runID: id, revision: revision, audio: Data([1])))
      }
      await gate.waitForEntry()
      #expect(await host.receive(.init(action: .pause, runID: id)).outcome == .paused)
      #expect(!services.audio.voiceInputActive)
      gate.resume()
      #expect(await answer.value.outcome == .unavailable)
      #expect(try await store.session(accountID: account)?.revision == revision)
      #expect(try await store.pendingReviews(accountID: account).isEmpty)
      #expect(await server.writes == 0)
      #expect(
        await host.receive(.init(action: .refresh, runID: id, revision: revision)).outcome
          == .unavailable)
      #expect(!services.audio.voiceInputActive)
    }

    @Test func mixedFlashcardSessionIsRefusedEvenWhileItsCurrentQuestionIsTyped() async throws {
      let fixture = NativeAppAssemblyTests()
      let (services, store, _, _, domain, directory) = try await fixture.environment()
      defer { fixture.cleanup(domain, directory) }
      await services.model.restore()
      var options = StudySessionOptions()
      options.ankiMode = .reading
      options.groupMeaningReading = true
      options.meaningFirst = true
      let saved = try await store.openReviews(accountID: account, options: options)
      #expect(!saved.isAnki && saved.question?.kind == .meaning)
      let host = WatchReviewHost(services: services)
      let response = await host.receive(.init(action: .start, runID: UUID()))
      #expect(response.outcome == .unavailable)
      #expect(response.feedback?.contains("flashcard") == true)
      #expect(try await store.session(accountID: account)?.revision == saved.saved.revision)
      #expect(try await store.pendingReviews(accountID: account).isEmpty)
      #expect(!services.audio.voiceInputActive)
    }

    @Test func phoneVoiceLeaseCannotBeClaimedOrReleasedByWatch() async throws {
      let fixture = NativeAppAssemblyTests()
      let (services, store, _, _, domain, directory) = try await fixture.environment()
      defer { fixture.cleanup(domain, directory) }
      await services.model.restore()
      let lease = try #require(services.audio.beginVoiceInput())
      let host = WatchReviewHost(services: services)
      let blocked = await host.receive(.init(action: .start, runID: UUID()))
      #expect(blocked.outcome == .unavailable && services.audio.voiceInputActive)
      #expect(try await store.session(accountID: account) == nil)
      services.audio.endVoiceInput(lease)
      let id = UUID()
      #expect(await host.receive(.init(action: .start, runID: id)).outcome == .ready)
      #expect(await host.receive(.init(action: .pause, runID: id)).outcome == .paused)
      #expect(!services.audio.voiceInputActive)
    }

    @Test func previousProtocolIsRefusedBeforeOpeningASessionOrClaimingAudio() async throws {
      let fixture = NativeAppAssemblyTests()
      let (services, store, _, _, domain, directory) = try await fixture.environment()
      defer { fixture.cleanup(domain, directory) }
      await services.model.restore()
      let host = WatchReviewHost(services: services)
      var request = WatchReviewRequest(action: .start, runID: UUID())
      #expect(request.version == 2)
      request.version = 1
      #expect(await host.receive(request).outcome == .unavailable)
      #expect(try await store.session(accountID: account) == nil)
      #expect(!services.audio.voiceInputActive)
    }

    @Test func foreignPauseDoesNotStopTheOwnerButAStaleRevisionCannotChangeTheSession()
      async throws
    {
      let fixture = NativeAppAssemblyTests()
      let (services, store, _, _, domain, directory) = try await fixture.environment()
      defer { fixture.cleanup(domain, directory) }
      await services.model.restore()
      let host = WatchReviewHost(services: services)
      let id = UUID()
      let opened = await host.receive(.init(action: .start, runID: id))
      let revision = try #require(opened.revision)
      _ = await host.receive(.init(action: .pause, runID: UUID()))
      #expect(services.audio.voiceInputActive)
      #expect(
        await host.receive(.init(action: .refresh, runID: id, revision: revision)).outcome == .ready
      )
      #expect(
        await host.receive(.init(action: .advance, runID: id, revision: UUID())).outcome
          == .unavailable)
      #expect(try await store.session(accountID: account)?.revision == revision)
      #expect(try await store.pendingReviews(accountID: account).isEmpty)
      #expect(!services.audio.voiceInputActive)
    }
  }
#endif
