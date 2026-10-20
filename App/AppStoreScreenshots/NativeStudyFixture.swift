#if DEBUG
  import CoreText
  import StudyCore
  import StudyPersistence
  import StudyUI
  import SwiftUI

  /// Isolated UI acceptance data. Never used by a release build or a live account.
  @MainActor enum NativeStudyFixture {
    private static var materialEvent:
      (token: String, environment: Task<(StudyStore, StudyDownload), any Error>)?

    /// Only an explicitly armed synthetic account can accept this one-shot acceptance event.
    /// The owner must publish the returned task's result after it completes, including failures.
    static func receive(_ url: URL) -> Task<String, Never>? {
      let arguments = ProcessInfo.processInfo.arguments
      guard arguments.contains("--review-fixture"),
        arguments.contains("--material-conflict-fixture"),
        let event = materialEvent,
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        components.scheme == "usagiunagi", components.host?.isEmpty != false,
        components.percentEncodedPath == "/fixture/material-conflict/\(event.token)",
        components.user == nil, components.password == nil, components.port == nil,
        components.fragment == nil, components.query == nil
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
      let environment = Task { try await reviewFixtureStore() }
      materialEvent = nil
      if arguments.contains("--review-fixture"), arguments.contains("--material-conflict-fixture"),
        let index = arguments.firstIndex(of: "--fixture-event-token"),
        arguments.indices.contains(index + 1), UUID(uuidString: arguments[index + 1]) != nil
      {
        materialEvent = (arguments[index + 1], environment)
      }
      let suite = "dev.usagiunagi.mac-review-fixture"
      let defaults = UserDefaults(suiteName: suite)!
      defaults.removePersistentDomain(forName: suite)
      var preferences = ReviewPreferences()
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
      defaults.set(try? JSONEncoder().encode(preferences), forKey: "native.reviewPreferences")
      let (catalog, fontConfiguration) = StudyFontFixture.make()
      let audioConfiguration = URLSessionConfiguration.ephemeral
      audioConfiguration.protocolClasses = [AudioFixtureProtocol.self]
      return StudyAppAssembly(
        model: StudyAppModel(
          credentials: FixtureCredentials(), client: FixtureServer(environment: environment),
          openStore: { try await environment.value.0 }),
        fonts: StudyFontLibrary(
          catalog: catalog,
          preferences: DefaultsStudyFontPreferences(defaults: defaults),
          configuration: fontConfiguration),
        audio: StudyAudioLibrary(
          downloads: StudyAudioDownloads(
            directory: URL.temporaryDirectory.appending(path: "mac-audio-fixture-\(UUID())"),
            configuration: audioConfiguration),
          preferences: DefaultsStudyAudioPreferences(defaults: defaults),
          playback: SampleAudioPlayback()),
        defaults: defaults,
        notifications: StudyNotifications(
          preferences: DefaultsStudyNotificationPreferences(defaults: defaults),
          client: NotificationFixture.client),
        avatars: LegacyAvatarCache(
          directory: URL.temporaryDirectory.appending(path: "native-avatar-fixture-\(UUID())"),
          cache: URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)),
        appearance: arguments.contains("--light-fixture")
          ? .light : arguments.contains("--dark-fixture") ? .dark : nil,
        notice: "Synthetic review fixture · memory only · simulated sync",
        paths: AsyncStream {
          $0.yield(true)
          $0.finish()
        })
    }
    private final class FixtureCredentials: StudyCredentialStore {
      private var token: String? = "fixture"
      func load() -> String? { token }
      func save(_ token: String) { self.token = token }
      func remove() { token = nil }
    }
    /// Typed in-memory server; production HTTP validation remains covered by StudyCore tests.
    private actor FixtureServer: WaniKaniService {
      let environment: Task<(StudyStore, StudyDownload), any Error>
      private var state: StudyDownload?
      init(environment: Task<(StudyStore, StudyDownload), any Error>) {
        self.environment = environment
      }
      private func value(_ token: String) async throws -> StudyDownload {
        if token == "rejected" { throw WaniKaniClient.APIError.unauthorized }
        if token == "hibernating" { throw StudySignInError.hibernating }
        if let state { return state }
        let value = try await environment.value.1
        state = value
        return value
      }
      func account(token: String) async throws -> WaniKaniAccount {
        let data = try await value(token)
        return .init(
          id: data.accountID, username: data.profile.username, level: data.profile.level,
          onVacation: data.profile.vacationStartedAt != nil, startedAt: data.profile.startedAt,
          profile: data.profile)
      }
      func download(token: String) async throws -> StudyDownload {
        let data = try await value(token)
        return StudyDownload(
          accountID: data.accountID, profile: data.profile,
          subjects: data.subjects, assignments: data.assignments, materials: data.materials,
          levels: data.levels, statistics: data.statistics, voices: data.voices,
          systems: data.systems)
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
    private static func reviewFixtureStore() async throws -> (StudyStore, StudyDownload) {
      let cache = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
      var profile = StudyAccountProfile(username: "Synthetic review fixture")
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
      assignment.availableAt = 1
      if ProcessInfo.processInfo.arguments.contains("--lesson-recovery-fixture")
        || ProcessInfo.processInfo.arguments.contains("--lesson-fixture")
      {
        assignment.srsStage = 0
        assignment.startedAt = nil
        assignment.availableAt = nil
        assignment.unlockedAt = 1
      }
      var fixture = LegacyStudyExport(schemaVersion: 15, profile: profile)
      if ProcessInfo.processInfo.arguments.contains("--audio-fixture") {
        fixture.voices = [Int64(1), 2].map { id in
          var voice = StudyVoiceActor(id: id)
          voice.name = "Voice \(id) fixture"
          voice.description = "Tokyo accent"
          return voice
        }
        fixture.audio = subject.audio.map {
          .init(
            subjectID: subject.id, voiceActorID: $0.voiceActorID, level: subject.level, url: $0.url)
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
            serverID: 0,
            value: .init(
              subjectID: subject.id,
              meaningNote: ProcessInfo.processInfo.arguments.contains("--lesson-fixture")
                ? "" : "A saved synthetic note.",
              meaningSynonyms: ["Single"]), pending: false, legacyRevision: 0)
        ]
      } else {
        fixture.subjects = [subject]
      }
      if ProcessInfo.processInfo.arguments.contains("--material-recovery-fixture") {
        fixture.materials = [
          .init(
            serverID: 201,
            value: .init(
              subjectID: 1, meaningNote: "Local saved note. 🐰\nSecond line.",
              readingNote: "いち", meaningSynonyms: ["Local synonym"]), pending: true,
            legacyRevision: 0)
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
        fixture.pendingReviews = [
          .init(
            assignment: assignment,
            submission: .init(
              itemID: 0,
              subjectID: subject.id, assignmentID: assignment.id, isLesson: lesson,
              meaningWrong: !lesson, readingWrong: false, meaningWrongCount: lesson ? 0 : 1,
              readingWrongCount: 0, createdAt: 100))
        ]
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
      _ = try await cache.importLegacyAccount(
        fixture, sourceID: "review-fixture", verifiedAccountID: "review-fixture",
        verifiedUsername: profile.username, credentialID: StudyAppModel.credentialID("fixture"))
      var remote = StudyDownload(
        accountID: "review-fixture", profile: fixture.profile,
        subjects: fixture.subjects, assignments: fixture.assignments,
        materials: fixture.materials.map { .init(id: max(201, $0.serverID), value: $0.value) },
        levels: fixture.levels, statistics: fixture.statistics, voices: fixture.voices)
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
#endif
