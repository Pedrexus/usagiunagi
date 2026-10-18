import CoreText
import StudyCore
import StudyPersistence
import StudyUI
import SwiftUI

@MainActor enum StudyAppAssembly {
  static let reviewDefaults: UserDefaults = {
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      if arguments.contains("--review-fixture") {
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
        return defaults
      }
    #endif
    return .standard
  }()
  static var isReviewFixture: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("--review-fixture")
    #else
      false
    #endif
  }
  static func makeFonts() -> StudyFontLibrary {
    #if DEBUG
      if isReviewFixture {
        let font = CTFontCreateWithName("HiraMinProN-W3" as CFString, 24, nil)
        let name = CTFontCopyPostScriptName(font) as String
        let directory = FileManager.default.temporaryDirectory.appending(
          path: "mac-font-fixture-\(UUID().uuidString)")
        let catalog = StudyFontCatalog(
          definitions: [
            .init(name, "font-ready.ttf", "Installed font fixture", 1024),
            .init("DownloadFontFixture", "font-download.ttf", "Download font fixture", 1024),
            .init("MissingFontFixture", "font-failed.ttf", "Failed font fixture", 1024),
            .init("HeldFontFixture", "font-held.ttf", "Held font fixture", 1024),
          ], directory: directory, bundledFonts: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FontFixtureProtocol.self]
        return StudyFontLibrary(
          catalog: catalog, preferences: DefaultsStudyFontPreferences(defaults: reviewDefaults),
          configuration: configuration)
      }
    #endif
    return StudyFontLibrary(
      catalog: .init(
        directory: URL.applicationSupportDirectory.appending(path: "TsurukameNative/fonts"),
        bundledFonts: nil))
  }
  static func makeAudio() -> StudyAudioLibrary {
    #if DEBUG
      if isReviewFixture {
        let directory = URL.temporaryDirectory.appending(
          path: "mac-audio-fixture-\(UUID().uuidString)")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AudioFixtureProtocol.self]
        return StudyAudioLibrary(
          downloads: StudyAudioDownloads(directory: directory, configuration: configuration),
          preferences: DefaultsStudyAudioPreferences(defaults: reviewDefaults),
          playback: SampleAudioPlayback())
      }
    #endif
    return StudyAudioLibrary(
      downloads: StudyAudioDownloads(
        directory: URL.applicationSupportDirectory.appending(path: "TsurukameNative/audio")))
  }
  static func makeModel() -> StudyAppModel {
    #if DEBUG
      if isReviewFixture {
        return StudyAppModel(
          credentials: FixtureCredentials(), client: fixtureClient,
          openStore: { try await reviewFixtureStore() })
      }
    #endif
    let directory = URL.applicationSupportDirectory.appending(path: "TsurukameNative")
    return StudyAppModel(
      credentials: KeychainStudyCredentialStore(service: "TsurukameNative.WaniKani"),
      legacySnapshotURL: directory.appending(path: "snapshot-v1.json"),
      openStore: { try await StudyStore.open(at: directory.appending(path: "study.store")) })
  }
  #if DEBUG
    private struct FixtureCredentials: StudyCredentialStore {
      func load() -> String? { "fixture" }
      func save(_ token: String) throws { throw StudyStoreError.sampleData }
      func remove() throws { throw StudyStoreError.sampleData }
    }
    private static var fixtureClient: WaniKaniClient {
      WaniKaniClient { request in
        guard request.httpMethod == "GET" else { throw StudyStoreError.sampleData }
        let json: String
        switch request.url?.lastPathComponent {
        case "user":
          json =
            #"{"object":"user","data":{"id":"review-fixture","username":"Synthetic review fixture","level":1,"current_vacation_started_at":null}}"#
        case "study_materials":
          json =
            #"{"object":"collection","total_count":1,"pages":{"next_url":null},"data":[{"id":201,"object":"study_material","data":{"subject_id":1,"meaning_note":"Server version of the note.","reading_note":"いち","meaning_synonyms":["Server synonym"]}}]}"#
        case "assignments":
          json =
            #"{"object":"collection","total_count":1,"pages":{"next_url":null},"data":[{"id":101,"object":"assignment","data":{"subject_id":1,"subject_type":"kanji","srs_stage":4,"available_at":"2099-01-01T00:00:00Z","started_at":"2020-01-01T00:00:00Z","unlocked_at":"2020-01-01T00:00:00Z","hidden":false}}]}"#
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
  #endif
  static var appearance: ColorScheme? {
    guard isReviewFixture else { return nil }
    if ProcessInfo.processInfo.arguments.contains("--light-fixture") { return .light }
    if ProcessInfo.processInfo.arguments.contains("--dark-fixture") { return .dark }
    return nil
  }
  static var notice: String? {
    isReviewFixture ? "Synthetic review fixture · memory only · uploads disabled" : nil
  }

}
