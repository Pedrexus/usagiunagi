#if DEBUG
  import CoreText
  import StudyCore
  @testable import StudyPersistence
  import SwiftUI

  /// Isolated UI acceptance data. Never used by a release build or a live account.
  @MainActor enum NativeStudyFixture {
    private static var materialEvent:
      (token: String, environment: Task<(StudyStore, StudyDownload), any Error>)?
    private static var accountTask: Task<Void, Never>?
    private static var refreshEvent: (token: String, server: FixtureServer)?

    /// Only an explicitly armed synthetic account can accept this one-shot acceptance event.
    /// The owner must publish the returned task's result after it completes, including failures.
    static func receive(_ url: URL) -> Task<String, Never>? {
      let arguments = ProcessInfo.processInfo.arguments
      guard arguments.contains("--review-fixture"),
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        components.scheme == "usagiunagi", components.host?.isEmpty != false,
        components.user == nil, components.password == nil, components.port == nil,
        components.fragment == nil, components.query == nil
      else { return nil }
      if arguments.contains("--held-refresh-fixture"), let event = refreshEvent,
        components.percentEncodedPath == "/fixture/release-refresh/\(event.token)"
      {
        refreshEvent = nil
        return Task {
          await event.server.releaseRefresh()
            ? "Isolated refresh released" : "No isolated refresh was waiting"
        }
      }
      guard arguments.contains("--material-conflict-fixture"), let event = materialEvent,
        components.percentEncodedPath == "/fixture/material-conflict/\(event.token)"
      else { return nil }
      materialEvent = nil
      let reject = arguments.contains("--material-conflict-failure-fixture")
      return Task {
        do {
          let store = try await event.environment.value.0
          let current = try await store.subjectDetails(subjectID: 1, accountID: "review-fixture")
          var changed = current.material ?? StudyMaterial(subjectID: 1)
          changed.meaningNote = "Concurrent saved note\n" + StudyMaterial.exclusionMarker
          changed.readingNote = "Concurrent hidden reading note"
          try await store.saveMaterial(
            changed, accountID: "review-fixture",
            expectedRevision: reject ? UUID() : current.savedMaterial?.revision)
          return "Concurrent material change committed"
        } catch {
          return "Fixture event failed: \(error.localizedDescription)"
        }
      }
    }
    static func make() -> StudyAppAssembly {
      let arguments = ProcessInfo.processInfo.arguments
      precondition(
        arguments.contains("--review-fixture"), "Native fixtures require explicit opt-in")
      let environment = Task { try await reviewFixtureStore() }
      let deferredAccount = arguments.contains("--deferred-account-fixture")
      let expiredAccount = arguments.contains("--expired-account-fixture") || deferredAccount
      let hibernatingAccount = arguments.contains("--hibernating-account-fixture")
      let server = FixtureServer(
        environment: environment, expiredAccount: expiredAccount,
        hibernatingAccount: hibernatingAccount,
        heldRefresh: arguments.contains("--held-refresh-fixture"))
      let model = StudyAppModel(
        credentials: FixtureCredentials(
          arguments.contains("--disconnected-fixture") ? nil : "fixture"),
        client: server, openStore: { try await environment.value.0 })
      accountTask?.cancel()
      accountTask = nil
      if expiredAccount || hibernatingAccount {
        accountTask = Task {
          await model.restore()
          guard model.restorationComplete else { return }
          do {
            if deferredAccount {
              let cache = try await environment.value.0
              for await _ in await cache.changes() {
                try Task.checkCancellation()
                if let saved = try await cache.session(accountID: "review-fixture"),
                  !saved.session.isPractice,
                  saved.session.items.values.first?.isLesson == false
                {
                  break
                }
              }
            }
            try Task.checkCancellation()
            await model.refresh()
          } catch is CancellationError {
            return
          } catch {
            model.error =
              "Could not prepare the isolated account fixture: \(error.localizedDescription)"
          }
        }
      }
      materialEvent = nil
      refreshEvent = nil
      if let index = arguments.firstIndex(of: "--fixture-event-token"),
        arguments.indices.contains(index + 1), UUID(uuidString: arguments[index + 1]) != nil
      {
        if arguments.contains("--material-conflict-fixture") {
          materialEvent = (arguments[index + 1], environment)
        }
        if arguments.contains("--held-refresh-fixture") {
          refreshEvent = (arguments[index + 1], server)
        }
      }
      let suite = "dev.usagiunagi.mac-review-fixture"
      let defaults = UserDefaults(suiteName: suite)!
      defaults.removePersistentDomain(forName: suite)
      var preferences = ReviewPreferences()
      if arguments.contains("--settings-fixture") { preferences.appearance = .light }
      if arguments.contains("--lesson-fixture") || arguments.contains("--manual-review-fixture") {
        preferences.revealAnswers = false
        preferences.sessionOptions.groupMeaningReading = true
        preferences.sessionOptions.incorrectAnswerDelay = 0
      }
      if arguments.contains("--anki-fixture") {
        preferences.sessionOptions.ankiMode =
          arguments.contains("--reading-anki-fixture") ? .reading : .both
        preferences.sessionOptions.combinedAnki = arguments.contains("--combined-anki-fixture")
        preferences.sessionOptions.groupMeaningReading = true
        preferences.sessionOptions.incorrectAnswerDelay = 0
      }
      if arguments.contains("--sample-review-fixture") {
        preferences.sessionOptions.skipKanjiReadings = true
      }
      if arguments.contains("--voice-hint-fixture") { preferences.exactMatch = true }
      defaults.set(try? JSONEncoder().encode(preferences), forKey: "native.reviewPreferences")
      if arguments.contains("--catalog-fixture") {
        let lessons = DefaultsStudyLessonPreferences(defaults: defaults)
        var lessonPreferences = lessons.value
        lessonPreferences.allowVocabularyExclusion = true
        lessons.value = lessonPreferences
        let subjects = DefaultsStudySubjectPreferences(defaults: defaults)
        var subjectPreferences = subjects.value
        subjectPreferences.showPreviousLevelGraph = true
        subjects.value = subjectPreferences
      }
      if arguments.contains("--home-fixture") {
        let subjects = DefaultsStudySubjectPreferences(defaults: defaults)
        var value = subjects.value
        value.showPreviousLevelGraph = false
        subjects.value = value
        if arguments.contains("--home-limit-fixture") {
          let lessons = DefaultsStudyLessonPreferences(defaults: defaults)
          var value = lessons.value
          value.apprenticeLimit = 12
          lessons.value = value
        }
      }
      let (catalog, fontConfiguration) = StudyFontFixture.make()
      let audioConfiguration = URLSessionConfiguration.ephemeral
      audioConfiguration.protocolClasses = [AudioFixtureProtocol.self]
      let audio = StudyAudioLibrary(
        downloads: StudyAudioDownloads(
          directory: URL.temporaryDirectory.appending(path: "mac-audio-fixture-\(UUID())"),
          configuration: audioConfiguration),
        preferences: DefaultsStudyAudioPreferences(defaults: defaults),
        playback: SampleAudioPlayback())
      let voice = FixtureVoiceCapture(
        audio: audio, continuous: arguments.contains("--continuous-voice-fixture"),
        mistake: arguments.contains("--voice-mistake-fixture"),
        repeatReading: arguments.contains("--voice-repeat-fixture"),
        hint: arguments.contains("--voice-hint-fixture"),
        slowCleanup: arguments.contains("--voice-cleanup-fixture"))
      return StudyAppAssembly(
        model: model,
        fonts: StudyFontLibrary(
          catalog: catalog,
          preferences: DefaultsStudyFontPreferences(defaults: defaults),
          configuration: fontConfiguration),
        audio: audio,
        defaults: defaults,
        notifications: StudyNotifications(
          preferences: DefaultsStudyNotificationPreferences(defaults: defaults),
          client: NotificationFixture.client),
        avatars: StudyAvatarCache(
          cache: URLCache(memoryCapacity: 1_048_576, diskCapacity: 0),
          transport: { request in
            guard let url = request.url,
              let bytes = Data(
                base64Encoded:
                  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
              ),
              let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "image/png"])
            else { throw URLError(.badURL) }
            return (bytes, response)
          }),
        radicalImages: RadicalImageCache(
          directory: URL.temporaryDirectory.appending(path: "native-radical-fixture-\(UUID())"),
          transport: { request in
            guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "image/svg+xml"])
            else { throw URLError(.badURL) }
            let bytes = Data(
              "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><circle cx=\"12\" cy=\"12\" r=\"10\"/><circle cx=\"16\" cy=\"8\" r=\"3\" fill=\"white\"/></svg>"
                .utf8)
            return (bytes, response)
          }),
        voiceCapture: { voice },
        appearance: arguments.contains("--light-fixture")
          ? .light : arguments.contains("--dark-fixture") ? .dark : nil,
        paths: AsyncStream {
          $0.yield(true)
          $0.finish()
        })
    }
    /// Deterministic transcription; acceptance fixtures never start microphones or Speech APIs.
    private actor FixtureVoiceCapture: VoiceCapture {
      private let audio: StudyAudioLibrary
      private let continuous: Bool
      private let mistake: Bool
      private let repeatReading: Bool
      private let hint: Bool
      private let slowCleanup: Bool
      private var meanings = 0
      private var readings = 0
      private var callback: VoiceCaptureReport?
      private var recordingID: UUID?
      private var transcript = ""
      init(
        audio: StudyAudioLibrary, continuous: Bool, mistake: Bool, repeatReading: Bool, hint: Bool,
        slowCleanup: Bool
      ) {
        self.audio = audio
        self.continuous = continuous
        self.mistake = mistake
        self.repeatReading = repeatReading
        self.hint = hint
        self.slowCleanup = slowCleanup
      }
      func start(
        id: UUID, locale: Locale, downloadModel _: Bool,
        report: @escaping VoiceCaptureReport
      ) async {
        guard await audio.voiceInputActive else {
          await report(.failed("Voice input does not own pronunciation."))
          return
        }
        recordingID = id
        callback = report
        if locale.identifier.hasPrefix("ja") {
          readings += 1
          transcript = "一"
        } else {
          meanings += 1
          transcript =
            meanings == 1 && slowCleanup
            ? ""
            : meanings == 1 && hint ? "singl" : mistake && meanings == 1 ? "two" : "one"
        }
        await report(.listening)
        if continuous {
          await report(.segment(text: transcript, start: 0, end: 1, isFinal: false))
          if transcript.isEmpty { await report(.finished) }
        }
      }
      func finish(id: UUID) async {
        guard recordingID == id else { return }
        await callback?(
          .segment(
            text: transcript, start: 0, end: 1, isFinal: true,
            alternatives: continuous && transcript == "一" && (!repeatReading || readings > 1)
              ? ["いち"] : []))
        guard recordingID == id else { return }
        await callback?(.finished)
      }
      func cancel(id: UUID) async {
        guard recordingID == id else { return }
        if slowCleanup && meanings == 1 {
          try? await Task.sleep(for: .seconds(4))
        }
        guard recordingID == id else { return }
        callback = nil
        recordingID = nil
      }
    }
    private final class FixtureCredentials: StudyCredentialStore {
      private var token: String?
      init(_ token: String?) { self.token = token }
      func load() -> String? { token }
      func save(_ token: String) { self.token = token }
      func remove() { token = nil }
    }
    /// Typed in-memory server; production HTTP validation remains covered by StudyCore tests.
    private actor FixtureServer: WaniKaniService {
      let environment: Task<(StudyStore, StudyDownload), any Error>
      private let expiredAccount: Bool
      private let hibernatingAccount: Bool
      private let heldRefresh: Bool
      private var refreshReleased = false
      private var refreshWaiter: (id: UUID, continuation: CheckedContinuation<Void, any Error>)?
      private var state: StudyDownload?
      nonisolated func reconfigured(baseURL: URL) throws -> any WaniKaniService { self }
      init(
        environment: Task<(StudyStore, StudyDownload), any Error>,
        expiredAccount: Bool, hibernatingAccount: Bool, heldRefresh: Bool
      ) {
        self.environment = environment
        self.expiredAccount = expiredAccount
        self.hibernatingAccount = hibernatingAccount
        self.heldRefresh = heldRefresh
      }
      private func value(_ token: String) async throws -> StudyDownload {
        if token == "rejected" { throw WaniKaniClient.APIError.unauthorized }
        if token == "hibernating" { throw StudySignInError.hibernating }
        if token == "fixture", expiredAccount { throw WaniKaniClient.APIError.unauthorized }
        if token == "fixture", hibernatingAccount { throw StudySignInError.hibernating }
        if let state { return state }
        let value = try await environment.value.1
        state = value
        return value
      }
      func account(token: String) async throws -> WaniKaniAccount {
        let data = try await value(token)
        if token == "other-account-token" {
          return .init(
            id: "other-review-fixture", username: "Another synthetic account", level: 1,
            onVacation: false)
        }
        return .init(
          id: data.accountID, username: data.profile.username, level: data.profile.level,
          onVacation: data.profile.vacationStartedAt != nil, startedAt: data.profile.startedAt,
          profile: data.profile)
      }
      func download(token: String, subjects: [CatalogSubject], cursors: [String: String])
        async throws
        -> StudyDownload
      {
        var data = try await value(token)
        if heldRefresh, !refreshReleased {
          let id = UUID()
          try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
              (continuation: CheckedContinuation<Void, any Error>) in
              if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
              } else if refreshWaiter != nil {
                continuation.resume(throwing: StudyUploadError.alreadyRunning)
              } else {
                refreshWaiter = (id, continuation)
              }
            }
          } onCancel: {
            Task { await self.cancelRefresh(id) }
          }
        }
        try Task.checkCancellation()
        if heldRefresh, let index = data.assignments.firstIndex(where: { $0.subjectID == 50_001 }) {
          data.assignments[index].srsStage = 5
          data.assignments[index].passedAt = 42
          state = data
        }
        return StudyDownload(
          accountID: data.accountID, profile: data.profile,
          subjects: data.subjects, assignments: data.assignments, materials: data.materials,
          levels: data.levels, statistics: data.statistics, voices: data.voices,
          systems: data.systems)
      }
      func releaseRefresh() -> Bool {
        guard let waiter = refreshWaiter else { return false }
        refreshWaiter = nil
        refreshReleased = true
        waiter.continuation.resume()
        return true
      }
      private func cancelRefresh(_ id: UUID) {
        guard let waiter = refreshWaiter, waiter.id == id else { return }
        refreshWaiter = nil
        waiter.continuation.resume(throwing: CancellationError())
      }
      func assignment(subjectID: Int64, token: String) async throws -> CatalogAssignment? {
        try await value(token).assignments.first { $0.subjectID == subjectID }
      }
      func material(subjectID: Int64, token: String) async throws -> WaniKaniMaterial? {
        try await value(token).materials.first { $0.value.subjectID == subjectID }
      }
      func submit(_ answer: StudyReviewSubmission, token: String, now: Date) async throws
        -> CatalogAssignment
      {
        var data = try await value(token)
        guard
          let index = data.assignments.firstIndex(where: {
            $0.subjectID == answer.subjectID && $0.id == answer.assignmentID
          })
        else { throw WaniKaniClient.APIError.invalidPayload }
        var assignment = data.assignments[index]
        assignment.srsStage = answer.isLesson ? 1 : min(9, assignment.srsStage + 1)
        assignment.startedAt = assignment.startedAt ?? Int64(now.timeIntervalSince1970)
        assignment.availableAt =
          assignment.srsStage == 9 ? nil : Int64(now.timeIntervalSince1970) + 3600
        data.assignments[index] = assignment
        state = data
        return assignment
      }
      func writeMaterial(_ material: StudyMaterial, serverID: Int64?, token: String) async throws
        -> WaniKaniMaterial
      {
        var data = try await value(token)
        let value = WaniKaniMaterial(id: serverID ?? 200 + material.subjectID, value: material)
        data.materials.removeAll { $0.value.subjectID == material.subjectID }
        data.materials.append(value)
        state = data
        return value
      }
    }
    /// Full original catalog examples, converted to native values; no legacy writer is constructed.
    private static func catalogFixtureSubjects() -> [CatalogSubject] {
      func reading(
        _ text: String, primary: Bool = false, type: CatalogSubject.Reading.Kind = .unknown
      ) -> CatalogSubject.Reading {
        .init(text, isPrimary: primary, kind: type)
      }
      func meaning(
        _ text: String, type: CatalogSubject.Meaning.Role = .unknown
      ) -> CatalogSubject.Meaning {
        .init(text, role: type)
      }
      func subject(
        id: Int64, kind: SubjectKind, japanese: String = "", slug: String = "",
        documentURL: String = "", readings: [CatalogSubject.Reading] = [],
        meanings: [CatalogSubject.Meaning] = [], componentSubjectIDs: [Int64] = [],
        details: (inout CatalogSubject) -> Void = { _ in }
      ) -> CatalogSubject {
        var value = CatalogSubject(id: id, kind: kind)
        value.level = [294, 923].contains(id) ? 2 : 1
        value.japanese = japanese
        value.slug = slug
        value.documentURL = documentURL
        value.readings = readings
        value.meanings = meanings
        value.componentSubjectIDs = componentSubjectIDs
        details(&value)
        return value
      }
      return [
        subject(
          id: 743, kind: .kanji, japanese: "酒",
          readings: [
            reading("しゅ", primary: true, type: .onyomi),
            reading("さけ", primary: false, type: .kunyomi),
            reading("さか", primary: false, type: .kunyomi),
          ], meanings: [meaning("Alcohol", type: .primary)]),
        subject(
          id: 3163, kind: .vocabulary, japanese: "お酒", readings: [reading("おさけ", primary: true)],
          meanings: [meaning("Sake", type: .primary), meaning("Alcohol", type: .secondary)]),
        subject(
          id: 3164, kind: .vocabulary, japanese: "日本酒",
          readings: [reading("にほんしゅ", primary: true), reading("にっぽんしゅ", primary: false)],
          meanings: [
            meaning("Japanese Style Alcohol", type: .primary),
            meaning("Japanese Alcohol", type: .secondary), meaning("Sake", type: .secondary),
          ]),
        subject(
          id: 355, kind: .radical, japanese: "為",
          meanings: [meaning("Sake", type: .primary), meaning("fake", type: .blacklist)]),
        subject(
          id: 1600, kind: .kanji, japanese: "為",
          readings: [
            reading("い", primary: true, type: .onyomi),
            reading("ため", primary: false, type: .kunyomi),
            reading("な", primary: false, type: .kunyomi),
            reading("す", primary: false, type: .kunyomi),
          ], meanings: [meaning("Sake", type: .primary), meaning("Fake", type: .blacklist)]),
        subject(
          id: 8911, kind: .kanji, japanese: "鮭",
          readings: [
            reading("さけ", primary: true, type: .kunyomi),
            reading("しゃけ", primary: true, type: .kunyomi),
          ], meanings: [meaning("Salmon", type: .primary)]),
        subject(
          id: 8918, kind: .vocabulary, japanese: "鮭",
          readings: [reading("さけ", primary: true), reading("しゃけ", primary: false)],
          meanings: [meaning("Salmon", type: .primary)]),
        subject(
          id: 1787, kind: .kanji, japanese: "酎",
          readings: [
            reading("ちゅう", primary: true, type: .onyomi),
            reading("ちゅ", primary: true, type: .onyomi),
            reading("かも", primary: false, type: .kunyomi),
          ], meanings: [meaning("Sake", type: .primary)]),
        subject(
          id: 1803, kind: .kanji, japanese: "偽",
          readings: [
            reading("ぎ", primary: true, type: .onyomi),
            reading("にせ", primary: false, type: .kunyomi),
            reading("いつわ", primary: false, type: .kunyomi),
          ], meanings: [meaning("Fake", type: .primary), meaning("Sake", type: .blacklist)]),
        subject(
          id: 6556, kind: .vocabulary, japanese: "偽", readings: [reading("にせ", primary: true)],
          meanings: [
            meaning("Fake", type: .primary), meaning("Imitation", type: .secondary),
            meaning("Sake", type: .blacklist),
          ]),
        subject(
          id: 1892, kind: .kanji, japanese: "叫",
          readings: [
            reading("きょう", primary: true, type: .onyomi),
            reading("さけ", primary: false, type: .kunyomi),
          ], meanings: [meaning("Shout", type: .primary)]),
        subject(
          id: 3516, kind: .vocabulary, japanese: "酒飲み", readings: [reading("さけのみ", primary: true)],
          meanings: [
            meaning("Alcoholic", type: .primary), meaning("Boozer", type: .secondary),
            meaning("Drunkard", type: .secondary),
            meaning("Big Drinker", type: .auxiliaryWhitelist),
            meaning("Drinker", type: .auxiliaryWhitelist), meaning("Drink", type: .blacklist),
            meaning("alcohol", type: .blacklist),
          ]),
        subject(
          id: 3515, kind: .vocabulary, japanese: "酒好き", readings: [reading("さけずき", primary: true)],
          meanings: [meaning("Drinker", type: .primary), meaning("Alcoholic", type: .secondary)]),
        subject(
          id: 5907, kind: .vocabulary, japanese: "為に", readings: [reading("ために", primary: true)],
          meanings: [
            meaning("For", type: .primary), meaning("For The Sake Of", type: .secondary),
            meaning("To", type: .secondary), meaning("Sake Of", type: .secondary),
          ]),
        subject(
          id: 6163, kind: .vocabulary, japanese: "避ける",
          readings: [reading("さける", primary: true), reading("よける", primary: false)],
          meanings: [meaning("To Avoid", type: .primary), meaning("To Dodge", type: .secondary)]),
        subject(
          id: 6812, kind: .vocabulary, japanese: "叫ぶ", readings: [reading("さけぶ", primary: true)],
          meanings: [meaning("To Shout", type: .primary), meaning("To Scream", type: .secondary)]),
        subject(
          id: 6960, kind: .vocabulary, japanese: "叫び", readings: [reading("さけび", primary: true)],
          meanings: [
            meaning("Shout", type: .primary), meaning("Scream", type: .secondary),
            meaning("A Shout", type: .secondary), meaning("A Scream", type: .secondary),
          ]),
        subject(
          id: 6961, kind: .vocabulary, japanese: "叫び声", readings: [reading("さけびごえ", primary: true)],
          meanings: [
            meaning("Shout", type: .primary), meaning("Yell", type: .secondary),
            meaning("Scream", type: .secondary),
          ]),
        subject(
          id: 3864, kind: .vocabulary, japanese: "私自身", slug: "私自身",
          documentURL: "https://www.wanikani.com/vocabulary/%E7%A7%81%E8%87%AA%E8%BA%AB",
          readings: [reading("わたしじしん", primary: true), reading("わたくしじしん", primary: false)],
          meanings: [
            meaning("Personally", type: .primary), meaning("As For Me", type: .secondary),
            meaning("Myself", type: .secondary),
          ], componentSubjectIDs: [923, 578, 689],
          details: {
            $0.meaningMnemonic =
              "\"When it comes to <kanji>somebody</kanji> like my<kanji>self</kanji>... aka <kanji>I</kanji>...\" When you say this you're really saying \"<vocabulary>personally</vocabulary>\" or \"<vocabulary>as for me</vocabulary>.\""
            $0.readingMnemonic =
              "The readings are a bit weird here. The <ja>私</ja> is <ja>わたし</ja> and the rest is on'yomi kanji readings. So, it's a mix of both, I'm afraid. \"When it comes to me, I like mixing up on'yomi and kun'yomi because I hate myself.\""
            $0.sentences = [
              .init(
                japanese: "私自身は、その動物園の問題にはあまり関心がないんです。",
                english: "Personally, I'm indifferent to the zoo's issues."),
              .init(
                japanese: "私自身は、そんなにきょくたんなことじゃなければ、どんな食生活でも良いと思っています。",
                english:
                  "As for me, as long as it isn't too extreme, I think any kind of diet is okay."),
              .init(
                japanese: "あなたがもし私自身よりも私のことを知っていると思ったら、 それはとんだ大間違いよ。",
                english: "You’re way off base if you think you know me better than I know myself."),
            ]
            $0.partsOfSpeech = [19]
            $0.partOfSpeechNames = ["Pronoun"]
          }),
        subject(
          id: 923, kind: .kanji, japanese: "私", meanings: [meaning("I", type: .primary)]),
        subject(
          id: 578, kind: .kanji, japanese: "自", meanings: [meaning("Self", type: .primary)]),
        subject(
          id: 689, kind: .kanji, japanese: "身", meanings: [meaning("Somebody", type: .primary)]),
        subject(
          id: 293, kind: .radical, japanese: "旦",
          meanings: [
            meaning("Dawn", type: .primary), meaning("Sunrise", type: .auxiliaryWhitelist),
          ]),
        subject(
          id: 294, kind: .radical, japanese: "韋",
          meanings: [
            meaning("Korea", type: .primary), meaning("Cow God", type: .auxiliaryWhitelist),
          ]),
        subject(
          id: 295, kind: .radical, japanese: "客", meanings: [meaning("Guest", type: .primary)]),
        subject(
          id: 296, kind: .radical, japanese: "制", meanings: [meaning("Control", type: .primary)]),
        subject(
          id: 297, kind: .radical, japanese: "然", meanings: [meaning("Nature", type: .primary)]),
        subject(
          id: 298, kind: .radical, japanese: "受", meanings: [meaning("Accept", type: .primary)]),
        subject(
          id: 1217, kind: .kanji, japanese: "担",
          readings: [reading("たん", primary: true, type: .onyomi)],
          meanings: [meaning("Carry", type: .primary), meaning("Bear", type: .secondary)]),
        subject(
          id: 1218, kind: .kanji, japanese: "額",
          readings: [reading("がく", primary: true, type: .onyomi)],
          meanings: [
            meaning("Amount", type: .primary), meaning("Framed Picture", type: .secondary),
            meaning("Forehead", type: .secondary),
          ]),
        subject(
          id: 1219, kind: .kanji, japanese: "製",
          readings: [reading("せい", primary: true, type: .onyomi)],
          meanings: [meaning("Manufacture", type: .primary)]),
        subject(
          id: 1220, kind: .kanji, japanese: "違",
          readings: [reading("ちが", primary: true, type: .kunyomi)],
          meanings: [meaning("Different", type: .primary)]),
        subject(
          id: 1221, kind: .kanji, japanese: "輸",
          readings: [reading("ゆ", primary: true, type: .onyomi)],
          meanings: [meaning("Transport", type: .primary)]),
        subject(
          id: 1222, kind: .kanji, japanese: "燃",
          readings: [reading("ねん", primary: true, type: .onyomi)],
          meanings: [meaning("Burn", type: .primary)]),
        subject(
          id: 1223, kind: .kanji, japanese: "祝",
          readings: [
            reading("しゅく", primary: true, type: .onyomi),
            reading("しゅう", primary: true, type: .onyomi),
          ], meanings: [meaning("Celebrate", type: .primary)]),
        subject(
          id: 1224, kind: .kanji, japanese: "届",
          readings: [reading("とど", primary: true, type: .kunyomi)],
          meanings: [meaning("Deliver", type: .primary)]),
        subject(
          id: 1225, kind: .kanji, japanese: "狭",
          readings: [
            reading("せま", primary: true, type: .kunyomi),
            reading("せば", primary: true, type: .kunyomi),
          ], meanings: [meaning("Narrow", type: .primary)]),
        subject(
          id: 1226, kind: .kanji, japanese: "肩",
          readings: [reading("かた", primary: true, type: .kunyomi)],
          meanings: [meaning("Shoulder", type: .primary)]),
        subject(
          id: 1227, kind: .kanji, japanese: "腕",
          readings: [reading("うで", primary: true, type: .kunyomi)],
          meanings: [meaning("Arm", type: .primary)]),
        subject(
          id: 1228, kind: .kanji, japanese: "腰",
          readings: [reading("こし", primary: true, type: .kunyomi)],
          meanings: [meaning("Waist", type: .primary)]),
        subject(
          id: 1229, kind: .kanji, japanese: "触",
          readings: [reading("しょく", primary: true, type: .onyomi)],
          meanings: [meaning("Touch", type: .primary)]),
        subject(
          id: 1230, kind: .kanji, japanese: "載",
          readings: [reading("さい", primary: true, type: .onyomi)],
          meanings: [meaning("Publish", type: .primary)]),
        subject(
          id: 1231, kind: .kanji, japanese: "層",
          readings: [reading("そう", primary: true, type: .onyomi)],
          meanings: [meaning("Layer", type: .primary)]),
        subject(
          id: 1232, kind: .kanji, japanese: "型",
          readings: [reading("けい", primary: true, type: .onyomi)],
          meanings: [meaning("Model", type: .primary), meaning("Type", type: .secondary)]),
        subject(
          id: 1233, kind: .kanji, japanese: "庁",
          readings: [reading("ちょう", primary: true, type: .onyomi)],
          meanings: [
            meaning("Agency", type: .primary), meaning("Government Office", type: .secondary),
          ]),
        subject(
          id: 1234, kind: .kanji, japanese: "視",
          readings: [reading("し", primary: true, type: .onyomi)],
          meanings: [meaning("Look At", type: .primary)]),
        subject(
          id: 1235, kind: .kanji, japanese: "差",
          readings: [reading("さ", primary: true, type: .onyomi)],
          meanings: [meaning("Distinction", type: .primary)]),
        subject(
          id: 1236, kind: .kanji, japanese: "管",
          readings: [reading("かん", primary: true, type: .onyomi)],
          meanings: [meaning("Pipe", type: .primary)]),
        subject(
          id: 1237, kind: .kanji, japanese: "象",
          readings: [
            reading("ぞう", primary: true, type: .onyomi),
            reading("しょう", primary: true, type: .onyomi),
          ],
          meanings: [meaning("Elephant", type: .primary), meaning("Phenomenon", type: .secondary)]),
        subject(
          id: 1238, kind: .kanji, japanese: "量",
          readings: [reading("りょう", primary: true, type: .onyomi)],
          meanings: [
            meaning("Quantity", type: .primary), meaning("Amount", type: .secondary),
            meaning("quality", type: .blacklist),
          ]),
        subject(
          id: 1239, kind: .kanji, japanese: "境",
          readings: [reading("きょう", primary: true, type: .onyomi)],
          meanings: [meaning("Boundary", type: .primary)]),
        subject(
          id: 1240, kind: .kanji, japanese: "環",
          readings: [reading("かん", primary: true, type: .onyomi)],
          meanings: [meaning("Loop", type: .primary)]),
        subject(
          id: 1241, kind: .kanji, japanese: "武",
          readings: [reading("ぶ", primary: true, type: .onyomi)],
          meanings: [meaning("Military", type: .primary)]),
        subject(
          id: 1242, kind: .kanji, japanese: "質",
          readings: [
            reading("しつ", primary: true, type: .onyomi),
            reading("しち", primary: true, type: .onyomi),
          ], meanings: [meaning("Quality", type: .primary)]),
        subject(
          id: 1243, kind: .kanji, japanese: "述",
          readings: [reading("じゅつ", primary: true, type: .onyomi)],
          meanings: [meaning("Mention", type: .primary)]),
        subject(
          id: 1244, kind: .kanji, japanese: "供",
          readings: [reading("きょう", primary: true, type: .onyomi)],
          meanings: [meaning("Servant", type: .primary), meaning("Companion", type: .secondary)]),
        subject(
          id: 1245, kind: .kanji, japanese: "展",
          readings: [reading("てん", primary: true, type: .onyomi)],
          meanings: [meaning("Expand", type: .primary)]),
        subject(
          id: 1246, kind: .kanji, japanese: "販",
          readings: [reading("はん", primary: true, type: .onyomi)],
          meanings: [meaning("Sell", type: .primary)]),
        subject(
          id: 1247, kind: .kanji, japanese: "株",
          readings: [reading("かぶ", primary: true, type: .kunyomi)],
          meanings: [meaning("Stocks", type: .primary), meaning("Shares", type: .secondary)]),
        subject(
          id: 8790, kind: .radical, meanings: [meaning("Death Star", type: .primary)],
          details: {
            $0.characterImageURL =
              "https://cdn.wanikani.com/images/363-subject-8790-with-css-original.svg?1520987154"
            $0.hasCharacterImageFile = true
          }),
      ]
    }
    private static func reviewFixtureStore() async throws -> (StudyStore, StudyDownload) {
      let cache = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
      let arguments = ProcessInfo.processInfo.arguments
      var profile = StudyAccountProfile(username: "Synthetic review fixture")
      if ProcessInfo.processInfo.arguments.contains("--expired-account-fixture")
        || ProcessInfo.processInfo.arguments.contains("--hibernating-account-fixture")
        || ProcessInfo.processInfo.arguments.contains("--deferred-account-fixture")
      {
        profile.username = "dummy"
      }
      let statistics = ProcessInfo.processInfo.arguments.contains("--statistics-fixture")
      profile.level = statistics ? 24 : 1
      profile.maxLevelGranted = 60
      var subject = CatalogSubject(id: 1, kind: .kanji)
      subject.level = 1
      subject.japanese = "一"
      subject.meanings = [.init("One", role: .primary)]
      subject.readings = [.init("いち", isPrimary: true, kind: .onyomi)]
      if ProcessInfo.processInfo.arguments.contains("--audio-fixture") {
        subject = CatalogSubject(id: 1, kind: .vocabulary)
        subject.level = 1
        subject.japanese = "一つ"
        subject.meanings = [.init("One thing", role: .primary)]
        subject.readings = [.init("ひとつ", isPrimary: true, kind: .unknown)]
        subject.meaningMnemonic = "One <vocabulary>thing</vocabulary>."
        subject.readingMnemonic = "Read this as <reading>ひとつ</reading>."
        subject.sentences = [.init(japanese: "一つください。", english: "One, please.")]
        subject.audio = [Int64(1), 2].map {
          .init(url: "https://audio.example.test/\($0).mp3", voiceActorID: $0)
        }
      }
      if ProcessInfo.processInfo.arguments.contains("--radical-fixture") {
        subject = CatalogSubject(id: 8790, kind: .radical)
        subject.level = 1
        subject.meanings = [.init("Death Star", role: .primary)]
        subject.characterImageURL =
          "https://cdn.wanikani.com/images/363-subject-8790-with-css-original.svg?1520987154"
      }
      var assignment = CatalogAssignment(id: 101, subjectID: subject.id, kind: subject.kind)
      assignment.level = 1
      assignment.srsStage = 3
      assignment.startedAt = 1
      assignment.availableAt =
        ProcessInfo.processInfo.arguments.contains("--statistics-clock-fixture")
        ? Int64(Date.now.timeIntervalSince1970) + 30 : 1
      if ProcessInfo.processInfo.arguments.contains("--lesson-recovery-fixture")
        || ProcessInfo.processInfo.arguments.contains("--lesson-fixture")
      {
        assignment.srsStage = 0
        assignment.startedAt = nil
        assignment.availableAt = nil
        assignment.unlockedAt = 1
      }
      var pendingReview: StudyReviewSubmission?
      var fixture = StudyDownload(accountID: "review-fixture", profile: profile)
      if ProcessInfo.processInfo.arguments.contains("--audio-fixture") {
        fixture.voices = [Int64(1), 2].map { id in
          var voice = StudyVoiceActor(id: id)
          voice.name = "Voice \(id) fixture"
          voice.description = "Tokyo accent"
          return voice
        }

      }
      if subject.kind == .kanji {
        if ProcessInfo.processInfo.arguments.contains("--subject-display-fixture") {
          subject.readings.append(.init("ひと", isPrimary: false, kind: .kunyomi))
        }
        subject.meaningMnemonic = "A <kanji>single line</kanji> represents <b>one</b>."
        subject.meaningHint = "Count the line: <b>one</b>."
        subject.readingMnemonic = "Read this as <reading>いち</reading>."
        subject.componentSubjectIDs = [2]
        subject.amalgamationSubjectIDs = [3]
        var component = CatalogSubject(id: 2, kind: .radical)
        component.level = 1
        component.japanese = "一"
        component.meanings = [.init("Ground", role: .primary)]
        var vocabulary = CatalogSubject(id: 3, kind: .vocabulary)
        vocabulary.level = 1
        vocabulary.japanese = "一つ"
        vocabulary.meanings = [.init("One thing", role: .primary)]
        vocabulary.readings = [.init("ひとつ", isPrimary: true, kind: .unknown)]
        vocabulary.meaningMnemonic = "A synthetic <vocabulary>vocabulary</vocabulary> example."
        vocabulary.sentences = [.init(japanese: "一つください。", english: "One, please.")]
        vocabulary.componentSubjectIDs = [1]
        fixture.subjects = [subject, component, vocabulary]
        fixture.materials = [
          .init(
            id: 201,
            value: .init(
              subjectID: subject.id,
              meaningNote: ProcessInfo.processInfo.arguments.contains("--lesson-fixture")
                ? "" : "A saved synthetic note.",
              meaningSynonyms: ["Single"]))
        ]
      } else {
        fixture.subjects = [subject]
      }
      if ProcessInfo.processInfo.arguments.contains("--material-recovery-fixture") {
        fixture.materials = [
          .init(
            id: 201,
            value: .init(
              subjectID: 1, meaningNote: "Local saved note. 🐰\nSecond line.",
              readingNote: "いち", meaningSynonyms: ["Local synonym"]))
        ]
      }
      fixture.assignments = [assignment]
      if ProcessInfo.processInfo.arguments.contains("--review-feedback-fixture") {
        fixture.assignments[0].srsStage = 4
        var second = CatalogSubject(id: 4, kind: .vocabulary)
        second.level = 1
        second.japanese = "二つ"
        second.meanings = [.init("Two things", role: .primary)]
        second.readings = [.init("ふたつ", isPrimary: true, kind: .unknown)]
        var due = CatalogAssignment(id: 104, subjectID: second.id, kind: second.kind)
        due.level = 1
        due.srsStage = 4
        due.startedAt = 1
        due.availableAt = 1
        fixture.subjects.append(second)
        fixture.assignments.append(due)
      }
      if ProcessInfo.processInfo.arguments.contains("--lesson-settings-fixture") {
        let examples: [(SubjectKind, String, String, String)] = [
          (.radical, "人", "Person", ""), (.radical, "口", "Mouth", ""),
          (.kanji, "二", "Two", "に"), (.vocabulary, "一つ", "One thing", "ひとつ"),
          (.vocabulary, "こんにちは", "Hello", ""),
        ]
        for (index, example) in examples.enumerated() {
          var subject = CatalogSubject(id: Int64(10 + index), kind: example.0)
          subject.level = 1
          subject.japanese = example.1
          subject.meanings = [.init(example.2, role: .primary)]
          if !example.3.isEmpty {
            subject.readings = [.init(example.3, isPrimary: true, kind: .unknown)]
          }
          subject.isKanaOnlyVocabulary = index == 4
          var item = CatalogAssignment(
            id: Int64(200 + index), subjectID: subject.id, kind: subject.kind)
          item.level = 1
          item.unlockedAt = 1
          item.isKanaOnlyVocabulary = index == 4
          fixture.subjects.append(subject)
          fixture.assignments.append(item)
        }
        if ProcessInfo.processInfo.arguments.contains("--lesson-limit-fixture") {
          for index in 0..<25 {
            var subject = CatalogSubject(id: Int64(100 + index), kind: .kanji)
            subject.level = 1
            subject.japanese = "二"
            subject.meanings = [.init("Two", role: .primary)]
            subject.readings = [.init("に", isPrimary: true, kind: .onyomi)]
            var item = CatalogAssignment(
              id: Int64(1000 + index), subjectID: subject.id, kind: .kanji)
            item.level = 1
            item.srsStage = 2
            item.startedAt = 1
            item.availableAt = Int64(Date.now.timeIntervalSince1970) + 86400
            fixture.subjects.append(subject)
            fixture.assignments.append(item)
          }
        }
      }

      if ProcessInfo.processInfo.arguments.contains("--review-recovery-fixture") {
        let lesson = ProcessInfo.processInfo.arguments.contains("--lesson-recovery-fixture")
        pendingReview = .init(
          itemID: 0, subjectID: subject.id, assignmentID: assignment.id, isLesson: lesson,
          meaningWrong: !lesson, readingWrong: false, meaningWrongCount: lesson ? 0 : 1,
          readingWrongCount: 0, createdAt: 100)
      }
      if statistics {
        var start = Date.now.addingTimeInterval(-95 * 86400)
        for (index, days) in [10, 12, 11, 14, 9, 13, 12, 13].enumerated() {
          let end = start.addingTimeInterval(Double(days) * 86400)
          var level = CatalogLevelProgression(id: Int64(index + 1))
          level.level = index + 16
          level.unlockedAt = Int64(start.timeIntervalSince1970)
          level.passedAt = Int64(end.timeIntervalSince1970)
          fixture.levels.append(level)
          start = end
        }
        var current = CatalogLevelProgression(id: 9)
        current.level = 24
        current.unlockedAt = Int64(start.timeIntervalSince1970)
        fixture.levels.append(current)
      }
      if ProcessInfo.processInfo.arguments.contains("--catalog-fixture") {
        profile.username = "Fred"
        profile.level = 1
        fixture.profile = profile
        fixture.subjects = catalogFixtureSubjects()
        let byID = Dictionary(uniqueKeysWithValues: fixture.subjects.map { ($0.id, $0) })
        let stages: [(Int64, Int)] = [(293, 5), (743, 2), (923, 5), (578, 0), (3864, 3), (689, 9)]
        fixture.assignments = try stages.map { id, stage in
          guard let subject = byID[id] else { throw WaniKaniClient.APIError.invalidPayload }
          var assignment = CatalogAssignment(id: 100_000 + id, subjectID: id, kind: subject.kind)
          assignment.level = subject.level
          assignment.srsStage = stage
          assignment.unlockedAt = 42
          if stage > 0 {
            assignment.startedAt = 42
            assignment.availableAt = id == 923 ? Int64(Int32.max) : 42
          }
          return assignment
        }
        fixture.materials = [
          .init(
            id: 201, value: .init(subjectID: 3864, meaningNote: StudyMaterial.exclusionMarker))
        ]
      }
      if arguments.contains("--sample-review-fixture") {
        profile.level = 8
        fixture = StudyDownload(accountID: "review-fixture", profile: profile)
        let readings: [Int64: String] = [923: "し", 578: "じ", 689: "しん"]
        fixture.subjects = catalogFixtureSubjects().filter {
          [3864, 923, 578, 689].contains($0.id)
        }
        .map { source in
          var value = source
          if let reading = readings[value.id] {
            value.readings = [.init(reading, isPrimary: true, kind: .onyomi)]
          }
          return value
        }
        fixture.assignments = fixture.subjects.map { subject in
          var value = CatalogAssignment(
            id: 100_000 + subject.id, subjectID: subject.id, kind: subject.kind)
          value.level = subject.level
          value.srsStage = 2
          value.startedAt = 42
          value.availableAt = 42
          return value
        }
      }
      if arguments.contains("--home-fixture") {
        profile.username = "Fred"
        profile.level = 24
        if arguments.contains("--home-vacation-fixture") { profile.vacationStartedAt = 42 }
        fixture = StudyDownload(accountID: "review-fixture", profile: profile)
        func appendSubject(id: Int64, kind: SubjectKind, level: Int, stage: Int?) {
          var value = CatalogSubject(id: id, kind: kind)
          value.level = level
          value.japanese = kind == .kanji ? "一" : "一つ"
          value.meanings = [.init("Saved item \(id)", role: .primary)]
          value.readings = [
            .init(kind == .kanji ? "いち" : "ひとつ", isPrimary: true, kind: .unknown)
          ]
          fixture.subjects.append(value)
          guard let stage else { return }
          var assignment = CatalogAssignment(id: 100_000 + id, subjectID: id, kind: kind)
          assignment.level = level
          assignment.srsStage = stage
          assignment.unlockedAt = 42
          if stage > 0 {
            assignment.startedAt = 42
            assignment.availableAt = stage == 9 ? nil : stage >= 5 ? 4_070_908_800 : 42
          }
          if stage >= 5 { assignment.passedAt = 42 }
          if stage == 9 { assignment.burnedAt = 42 }
          fixture.assignments.append(assignment)
        }
        let empty = arguments.contains("--home-empty-fixture")
        for index in 0..<25 {
          let stage: Int? = empty || index >= 17 ? nil : index == 0 ? 5 : index < 13 ? 2 : 0
          appendSubject(id: 50_000 + Int64(index), kind: .kanji, level: 24, stage: stage)
        }
        if arguments.contains("--home-progress-fixture")
          || arguments.contains("--held-refresh-fixture")
        {
          // 863 burned kanji plus the current Guru kanji preserve the original header count of 864.
          for index in 0..<2056 {
            appendSubject(
              id: 60_000 + Int64(index), kind: index < 863 ? .kanji : .vocabulary,
              level: 23, stage: 9)
          }
        }
      }
      try await cache.installPreview(
        fixture, pendingReview: pendingReview,
        pendingMaterial: arguments.contains("--material-recovery-fixture"))
      var remote = fixture
      if ProcessInfo.processInfo.arguments.contains("--material-recovery-fixture") {
        remote.materials = [
          .init(
            id: 201,
            value: .init(
              subjectID: 1,
              meaningNote: "Server version of the note.", readingNote: "いち",
              meaningSynonyms: ["Server synonym"]))
        ]
      }
      if ProcessInfo.processInfo.arguments.contains("--review-recovery-fixture") {
        remote.assignments[0].srsStage = 4
        remote.assignments[0].startedAt = 1
        remote.assignments[0].availableAt = 4_070_908_800
      }
      return (cache, remote)
    }
  }
  extension StudyStore {
    /// Synthetic acceptance data enters through the same native download transaction as refresh.
    fileprivate func installPreview(
      _ download: StudyDownload, pendingReview: StudyReviewSubmission?, pendingMaterial: Bool
    ) throws {
      let accountID = download.accountID
      _ = try applyDownload(
        download, credentialID: StudyAppModel.credentialID("fixture"),
        baseline: refreshBaseline(accountID: accountID))
      try transaction {
        if let pendingReview,
          let assignment = download.assignments.first(where: {
            $0.subjectID == pendingReview.subjectID
          })
        {
          let row = ReviewRecord(
            accountID: accountID, submission: pendingReview,
            originalItem: assignment.sessionItem(
              id: pendingReview.itemID, isLesson: pendingReview.isLesson))
          row.originalAssignment = assignment
          row.attempted = true
          row.issue = .init(
            reason: .uncertain, httpStatus: nil, serverAssignment: nil, detectedAt: .now)
          modelContext.insert(row)
        }
        if pendingMaterial {
          for row in try MaterialRecord.fetch(in: modelContext, accountID: accountID) {
            row.pending = true
            row.issue = .init(
              reason: .uncertain, httpStatus: nil, serverAssignment: nil, detectedAt: .now)
          }
        }
      }
    }
  }

#endif
