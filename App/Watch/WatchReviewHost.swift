#if os(iOS)
  import Foundation
  import StudyCore
  import StudyPersistence

  /// The phone remains the sole review writer; Watch is another revision-checked input.
  @MainActor final class WatchReviewHost {
    private let services: StudyAppAssembly
    private let capture: @Sendable (URL) -> any VoiceCapture
    private var generation = UUID()
    private var runID: UUID?
    private var accountID: String?
    private var state: NativeReviewState?
    private var preferences = ReviewPreferences()
    private var busy = false
    private var expiry: Task<Void, Never>?
    private var activeVoice: VoiceReviewController?
    private var audioLease: UUID?

    init(
      services: StudyAppAssembly,
      capture: @escaping @Sendable (URL) -> any VoiceCapture = { AppleVoiceCapture(recording: $0) }
    ) {
      self.services = services
      self.capture = capture
    }

    func receive(_ request: WatchReviewRequest) async -> WatchReviewResponse {
      guard request.version == 2 else {
        return failure(request.runID, "Update usagiunagi on both your Watch and iPhone.")
      }
      if request.action == .pause {
        if runID == request.runID { stop() }
        return .init(runID: request.runID, outcome: .paused)
      }
      guard !busy else {
        return failure(request.runID, "The phone is busy. Resume when it is ready.")
      }
      busy = true
      defer { busy = false }
      var requestGeneration = generation
      do {
        let model = services.model
        guard model.restorationComplete, !model.isDisconnecting,
          model.snapshot?.isSample == false, let account = model.snapshot?.accountID,
          model.accountIssue == nil, let store = model.savedWorkStore
        else {
          throw StudySignInError.message(
            "Open usagiunagi on your iPhone and connect WaniKani first.")
        }
        if request.action == .start {
          stop()
          requestGeneration = generation
          guard let lease = services.audio.beginVoiceInput() else {
            throw StudySignInError.message("Voice input is already running on your iPhone.")
          }
          runID = request.runID
          accountID = account
          audioLease = lease
          preferences =
            services.defaults.data(forKey: "native.reviewPreferences")
            .flatMap { try? JSONDecoder().decode(ReviewPreferences.self, from: $0) } ?? .init()
          var options = preferences.sessionOptions
          options.ankiMode = .off
          let opened = try await store.openReviews(
            accountID: account, options: options, lessonPreferences: services.lessonSettings.value,
            policy: preferences.reviewPolicy(
              waniKani: model.effectiveWaniKaniPreferences,
              followWaniKani: services.defaults.bool(forKey: "native.waniKani.reviewOrder")))
          try requireRun(request.runID, account: account, generation: requestGeneration)
          guard opened.saved.session.options.ankiMode == .off else {
            throw StudySignInError.message(
              "Finish the current flashcard session on your iPhone before using Watch voice reviews."
            )
          }
          state = opened
        } else {
          guard runID == request.runID, accountID == account, let current = state,
            request.revision == current.saved.revision
          else { throw StudyStoreError.staleSession }
          switch request.action {
          case .advance:
            let updated = try await store.changeReview(
              .advance, accountID: account, expectedRevision: current.saved.revision)
            try requireRun(request.runID, account: account, generation: requestGeneration)
            state = updated
          case .answer:
            return try await answer(
              request, current: current, store: store, account: account,
              generation: requestGeneration)
          case .refresh: break
          case .start, .pause: throw StudyStoreError.invalidSession
          }
        }
        return try await response(
          request.runID, store: store, account: account, generation: requestGeneration)
      } catch {
        if runID == request.runID, generation == requestGeneration { stop() }
        return failure(request.runID, error.localizedDescription)
      }
    }

    private func answer(
      _ request: WatchReviewRequest, current: NativeReviewState, store: StudyStore, account: String,
      generation: UUID
    ) async throws -> WatchReviewResponse {
      guard let question = current.question,
        current.saved.session.currentDecision != .incorrect,
        let bytes = request.audio, !bytes.isEmpty,
        bytes.count <= WatchReviewRequest.maximumAudioBytes
      else { throw StudyStoreError.invalidSession }
      let url = URL.temporaryDirectory.appending(path: "watch-answer-\(UUID()).m4a")
      try bytes.write(
        to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      defer { try? FileManager.default.removeItem(at: url) }
      let voice = VoiceReviewController(
        question: question, capture: capture(url))
      activeVoice = voice
      defer { activeVoice = nil }
      let operation = voice.start()
      let timeout = Task {
        do { try await Task.sleep(for: .seconds(15)) } catch { return }
        await voice.cancel()?.value
      }
      await operation.value
      timeout.cancel()
      try requireRun(request.runID, account: account, generation: generation)
      let heard = voice.text
      let text = voice.answer(for: question, usingSingleKanaInterpretation: true)
      let phase = voice.phase
      let shouldRepeat = voice.shouldRepeat
      await voice.cancel()?.value
      try requireRun(request.runID, account: account, generation: generation)
      guard let text else {
        var value = try await response(
          request.runID, store: store, account: account, generation: generation)
        value.heard = heard
        switch phase {
        case .needsModel:
          throw StudySignInError.message(
            "Use voice input in an iPhone review once for English and Japanese to set up both languages, then resume here."
          )
        case .reviewing:
          value.outcome = .repeatAnswer
          value.feedback = "Reading unclear. Say it again in Japanese."
        case .failed where heard.isEmpty:
          if shouldRepeat {
            value.outcome = .repeatAnswer
          } else {
            throw StudySignInError.message(
              "Recognition stopped. Check voice input on your iPhone, then resume here.")
          }
          value.feedback = "I didn’t hear an answer. Try again."
        default:
          throw StudySignInError.message("Recognition stopped. Resume to try again.")
        }
        return value
      }
      let result = try await store.answerReview(
        text, question: question, accountID: account,
        expectedRevision: current.saved.revision, exactMatch: preferences.exactMatch)
      try requireRun(request.runID, account: account, generation: generation)
      state = result.state
      var value = try await response(
        request.runID, store: store, account: account, generation: generation)
      value.heard = text
      if result.grade == .incorrect { return value }
      if result.state.question != question {
        if value.outcome != .finished { value.outcome = .correct }
        value.feedback = "Correct"
      } else {
        let screen = ReviewScreenState()
        screen.showAnswerHint(result.grade, exactMatch: preferences.exactMatch)
        value.outcome = .repeatAnswer
        value.feedback = screen.feedback.isEmpty ? "Try that answer again." : screen.feedback
      }
      return value
    }

    private func response(_ id: UUID, store: StudyStore, account: String, generation: UUID)
      async throws
      -> WatchReviewResponse
    {
      guard let state else { throw StudyStoreError.staleSession }
      guard try await store.session(accountID: account)?.revision == state.saved.revision else {
        throw StudyStoreError.staleSession
      }
      try requireRun(id, account: account, generation: generation)
      let summary = state.summary(showOldMeanings: false)
      var value = WatchReviewResponse(
        runID: id, revision: state.saved.revision,
        completed: summary.entries.count, correct: summary.correctCount,
        remaining: state.saved.session.items.count - state.saved.session.completedIDs.count)
      if let subject = state.subject, let question = state.question {
        let imageData: Data?
        if subject.japanese.isEmpty {
          guard let url = URL(string: subject.characterImageURL) else {
            throw StudySignInError.message("This radical needs an image. Continue on your iPhone.")
          }
          imageData = try await RadicalImageView.bitmap(at: url, cache: services.radicalImages)
          try requireRun(id, account: account, generation: generation)
          guard try await store.session(accountID: account)?.revision == state.saved.revision else {
            throw StudyStoreError.staleSession
          }
          try requireRun(id, account: account, generation: generation)
        } else {
          imageData = nil
        }
        value.prompt = .init(
          characters: subject.japanese, imageData: imageData,
          kind: subject.kind.rawValue, reading: question.kind == .reading)
        if state.saved.session.currentDecision == .incorrect {
          value.outcome = .incorrect
          let expected =
            question.kind == .reading
            ? subject.readings.filter(\.isPrimary).map(\.text)
            : subject.meanings.filter { $0.role != .blacklist }.map(\.text)
          value.feedback = "Incorrect. Answer: " + expected.joined(separator: ", ")
        }
        try renewLease(id, account: account, generation: generation)
      } else {
        try await store.finishReviews(accountID: account, expectedRevision: state.saved.revision)
        try requireRun(id, account: account, generation: generation)
        value.outcome = .finished
        value.feedback = "Reviews saved on iPhone"
        stop()
      }
      return value
    }

    private func requireRun(_ id: UUID, account: String, generation: UUID) throws {
      try Task.checkCancellation()
      guard self.generation == generation, runID == id, accountID == account,
        services.model.snapshot?.accountID == account, !services.model.isDisconnecting,
        services.model.accountIssue == nil, audioLease != nil
      else { throw StudySignInError.accountChanged }
    }

    private func renewLease(_ id: UUID, account: String, generation: UUID) throws {
      try requireRun(id, account: account, generation: generation)
      expiry?.cancel()
      services.automaticSync.start()
      services.automaticSync.updateScene(id, active: true, studying: true)
      services.iCloudPreferences?.updateScene(id, studying: true)
      expiry = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(60)) } catch { return }
        guard let self, self.generation == generation else { return }
        self.stop()
      }
    }

    private func stop() {
      generation = UUID()
      activeVoice?.cancel()
      if let audioLease { services.audio.endVoiceInput(audioLease) }
      audioLease = nil
      expiry?.cancel()
      expiry = nil
      if let runID {
        services.automaticSync.removeScene(runID)
        services.iCloudPreferences?.updateScene(runID, studying: false)
      }
      runID = nil
      accountID = nil
      state = nil
    }

    private func failure(_ id: UUID, _ message: String) -> WatchReviewResponse {
      .init(runID: id, outcome: .unavailable, feedback: message)
    }
  }
#endif
