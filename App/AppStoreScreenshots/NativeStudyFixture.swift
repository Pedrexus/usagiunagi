#if DEBUG
  import CoreText
  import StudyCore
  import StudyPersistence
  import StudyUI
  import SwiftUI

  /// Isolated UI acceptance data. Never used by a release build or a live account.
  @MainActor enum NativeStudyFixture {
    static func make() -> StudyAppAssembly {
      let arguments = ProcessInfo.processInfo.arguments
      let suite = "dev.usagiunagi.mac-review-fixture"
      let defaults = UserDefaults(suiteName: suite)!
      defaults.removePersistentDomain(forName: suite)
      var preferences = ReviewPreferences()
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
          credentials: FixtureCredentials(), client: fixtureClient,
          openStore: { try await reviewFixtureStore() }),
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
        appearance: arguments.contains("--light-fixture")
          ? .light : arguments.contains("--dark-fixture") ? .dark : nil,
        notice: "Synthetic review fixture · memory only · uploads disabled")
    }
    private final class FixtureCredentials: StudyCredentialStore {
      private var token: String? = "fixture"
      func load() -> String? { token }
      func save(_ token: String) { self.token = token }
      func remove() { token = nil }
    }
    private static var fixtureClient: WaniKaniClient {
      WaniKaniClient { request in
        guard request.httpMethod == "GET" else { throw StudyStoreError.sampleData }
        if let token = request.value(forHTTPHeaderField: "Authorization"),
          token == "Bearer rejected" || token == "Bearer hibernating"
        {
          let hibernating = token == "Bearer hibernating"
          return (
            try JSONSerialization.data(withJSONObject: [
              "error": hibernating ? "Account is hibernating" : "Unauthorized"
            ]),
            HTTPURLResponse(
              url: request.url!, statusCode: hibernating ? 403 : 401, httpVersion: nil,
              headerFields: nil)!
          )
        }
        let json: String
        switch request.url?.lastPathComponent {
        case "user":
          json =
            #"{"object":"user","data":{"id":"review-fixture","username":"Synthetic review fixture","level":1,"current_vacation_started_at":null,"profile_url":"https://www.wanikani.com/users/fixture","started_at":"2020-01-01T00:00:00Z","subscription":{"active":true,"max_level_granted":60,"period_ends_at":null}}}"#
        case "study_materials":
          json =
            #"{"object":"collection","total_count":1,"pages":{"next_url":null},"data":[{"id":201,"object":"study_material","data":{"subject_id":1,"meaning_note":"Server version of the note.","reading_note":"いち","meaning_synonyms":["Server synonym"]}}]}"#
        case "assignments":
          json =
            #"{"object":"collection","total_count":1,"pages":{"next_url":null},"data":[{"id":101,"object":"assignment","data":{"subject_id":1,"subject_type":"kanji","srs_stage":4,"available_at":"2099-01-01T00:00:00Z","started_at":"2020-01-01T00:00:00Z","unlocked_at":"2020-01-01T00:00:00Z","hidden":false}}]}"#
        case "subjects":
          let subject: [String: Any] = [
            "id": 1, "object": "kanji",
            "data": [
              "characters": "一", "level": 1, "slug": "一",
              "document_url": "https://www.wanikani.com/kanji/一",
              "lesson_position": 0, "spaced_repetition_system_id": 1, "meaning_mnemonic": "One.",
              "meanings": [["meaning": "One", "primary": true, "accepted_answer": true]],
              "auxiliary_meanings": [],
              "readings": [
                ["reading": "いち", "primary": true, "accepted_answer": true, "type": "onyomi"]
              ],
            ],
          ]
          json = String(
            decoding: try JSONSerialization.data(withJSONObject: [
              "object": "collection", "total_count": 1,
              "pages": ["next_url": NSNull()], "data": [subject],
            ]), as: UTF8.self)
        case "review_statistics", "level_progressions", "voice_actors":
          json = #"{"object":"collection","total_count":0,"pages":{"next_url":null},"data":[]}"#
        default: throw StudyStoreError.sampleData
        }
        return (
          Data(json.utf8),
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      }
    }
    private static func reviewFixtureStore() async throws -> StudyStore {
      let cache = try await StudyStore.open(at: URL(filePath: "/unused"), inMemory: true)
      var profile = StudyAccountProfile(username: "Synthetic review fixture")
      profile.level = 1
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
              subjectID: subject.id, meaningNote: "A saved synthetic note.",
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
      _ = try await cache.importLegacyAccount(
        fixture, sourceID: "review-fixture", verifiedAccountID: "review-fixture",
        verifiedUsername: profile.username, credentialID: StudyAppModel.credentialID("fixture"))
      return cache
    }
  }
#endif
