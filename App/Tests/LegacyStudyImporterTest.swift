// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import SQLite3
import StudyCore
import StudyPersistence
import SwiftProtobuf
import Testing
import WaniKaniAPI

@MainActor @Suite final class LegacyStudyImporterTests {
  private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  deinit { try? FileManager.default.removeItem(at: directory) }
  private func fixture(
    version: Int = 15,
    edit: (LegacyFixtureDatabase) throws -> Void = { _ in
    }
  ) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: UUID().uuidString + ".sqlite")
    let db = try LegacyFixtureDatabase(url)
    let materialRevision = version >= 14 ? ", local_revision INTEGER DEFAULT 0" : ""
    let mistakeColumn = version >= 11 ? ", last_mistake_time TEXT" : ""
    let progressRevision = version >= 15 ? ", local_revision INTEGER DEFAULT 0" : ""
    let statisticsCursor = version >= 12 ? ", review_stats_updated_after TEXT" : ""
    let statisticsValue = version >= 12 ? ",'statistics'" : ""
    let schema = """
      PRAGMA user_version = \(version);
      CREATE TABLE user (id INTEGER PRIMARY KEY, pb BLOB);
      CREATE TABLE subjects (id INTEGER PRIMARY KEY, japanese TEXT, level INTEGER, type INTEGER, pb BLOB);
      CREATE TABLE assignments (id INTEGER PRIMARY KEY, subject_id INTEGER, pb BLOB);
      CREATE TABLE pending_progress (id INTEGER PRIMARY KEY, pb BLOB);
      CREATE TABLE study_materials (id INTEGER PRIMARY KEY, pb BLOB\(materialRevision));
      CREATE TABLE pending_study_materials (id INTEGER PRIMARY KEY);
      CREATE TABLE subject_progress (id INTEGER PRIMARY KEY, level INTEGER, srs_stage INTEGER, subject_type INTEGER\(mistakeColumn)\(progressRevision));
      CREATE TABLE level_progressions (id INTEGER PRIMARY KEY, level INTEGER, pb BLOB);
      CREATE TABLE voice_actors (id INTEGER PRIMARY KEY, pb BLOB);
      CREATE TABLE audio_urls (subject_id INTEGER, voice_actor_id INTEGER, level INTEGER, url TEXT);
      CREATE TABLE sync (assignments_updated_after TEXT, study_materials_updated_after TEXT, subjects_updated_after TEXT, voice_actors_updated_after TEXT\(statisticsCursor));
      INSERT INTO sync VALUES ('assignments','materials','subjects','voices'\(statisticsValue));
      CREATE TABLE error_log (request_headers TEXT);
      INSERT INTO error_log VALUES ('diagnostic-fixture-must-stay-in-source');
      """
    #expect(db.executeStatements(schema))
    if version >= 12 {
      #expect(
        db
          .executeStatements(
            "CREATE TABLE review_stats (id INTEGER PRIMARY KEY, subject_id INTEGER, pb BLOB);"))
    }
    var user = TKMUser()
    user.username = "fixture"
    user.level = 12
    user.maxLevelGrantedBySubscription = 60
    user.startedAt = 10
    user.subscribed = true
    user.subscriptionEndsAt = 100
    user.vacationStartedAt = 50
    user.profileURL = "https://example.invalid/fixture"
    try db.executeUpdate("INSERT INTO user VALUES (0, ?)", values: [.blob(user.serializedData())])
    var meaning = TKMMeaning()
    meaning.meaning = "cat"
    meaning.type = .primary
    var reading = TKMReading()
    reading.reading = "ねこ"
    reading.isPrimary = true
    reading.type = .kunyomi
    var subject = TKMSubject()
    subject.id = 42
    subject.japanese = "猫"
    subject.level = 12
    subject.slug = "猫"
    subject.documentURL = "https://example.invalid/cat"
    subject.meanings = [meaning]
    subject.readings = [reading]
    subject.componentSubjectIds = [21]
    subject.amalgamationSubjectIds = [43]
    subject.vocabulary.meaningExplanation = "Meaning <kanji>猫</kanji>"
    subject.vocabulary.readingExplanation = "Reading mnemonic"
    var sentence = TKMVocabulary.Sentence()
    sentence.japanese = "猫です。"
    sentence.english = "It is a cat."
    subject.vocabulary.sentences = [sentence]
    subject.vocabulary.partsOfSpeech = [.noun, .UNRECOGNIZED(99)]
    var audio = TKMVocabulary.PronunciationAudio()
    audio.url = "https://example.invalid/cat.mp3"
    audio.voiceActorID = 7
    subject.vocabulary.audio = [audio]
    try db.executeUpdate(
      "INSERT INTO subjects VALUES (42, '猫', 12, 3, ?)",
      values: [.blob(subject.serializedData())])
    var assignment = TKMAssignment()
    assignment.id = 142
    assignment.subjectID = 42
    assignment.subjectType = .vocabulary
    assignment.level = 12
    assignment.srsStageNumber = 3
    assignment.availableAt = 100
    assignment.startedAt = 10
    assignment.passedAt = 20
    assignment.burnedAt = 30
    try db.executeUpdate(
      "INSERT INTO assignments VALUES (142, 42, ?)",
      values: [.blob(assignment.serializedData())])
    var progress = TKMProgress()
    progress.assignment = assignment
    progress.createdAt = 120
    progress.meaningWrong = true
    progress.meaningWrongCount = 2
    progress.readingWrongCount = 0
    try db.executeUpdate(
      "INSERT INTO pending_progress VALUES (42, ?)",
      values: [.blob(progress.serializedData())])
    var material = TKMStudyMaterials()
    material.id = 242
    material.subjectID = 42
    material.meaningNote = "offline\u{0000}note\n猫"
    material.readingNote = "ねこ"
    material.meaningSynonyms = ["kitty", "house cat"]
    try db.executeUpdate(
      "INSERT INTO study_materials (id, pb) VALUES (42, ?)",
      values: [.blob(material.serializedData())])
    #expect(
      db
        .executeStatements(
          "INSERT INTO pending_study_materials VALUES (42); INSERT INTO subject_progress (id, level, srs_stage, subject_type) VALUES (42,12,2,3);"
        ))
    if version >= 11 {
      try db.executeUpdate(
        "UPDATE subject_progress SET last_mistake_time = ?",
        values: [.text("2026-10-17 12:34:56")])
    }
    if version >= 14 {
      #expect(db.executeStatements("UPDATE study_materials SET local_revision = 9"))
    }
    if version >= 15 {
      #expect(db.executeStatements("UPDATE subject_progress SET local_revision = 8"))
    }
    var level = TKMLevel()
    level.id = 5
    level.level = 12
    level.createdAt = 1
    level.unlockedAt = 2
    level.startedAt = 3
    level.passedAt = 4
    level.completedAt = 5
    level.abandonedAt = 6
    try db.executeUpdate(
      "INSERT INTO level_progressions VALUES (5, 12, ?)",
      values: [.blob(level.serializedData())])
    var voice = TKMVoiceActor()
    voice.id = 7
    voice.gender = .female
    voice.name = "Voice"
    voice.description_p = "Fixture voice"
    try db.executeUpdate(
      "INSERT INTO voice_actors VALUES (7, ?)", values: [.blob(voice.serializedData())])
    try db.executeUpdate("INSERT INTO audio_urls VALUES (42, 7, 12, ?)", values: [.text(audio.url)])
    if version >= 12 {
      var statistic = TKMReviewStatistic()
      statistic.id = 342
      statistic.subjectID = 42
      statistic.type = .vocabulary
      statistic.createdAt = 10
      statistic.meaningCorrect = 9
      statistic.meaningIncorrect = 2
      statistic.meaningMaxStreak = 5
      statistic.meaningCurrentStreak = 3
      statistic.readingCorrect = 8
      statistic.readingIncorrect = 1
      statistic.readingMaxStreak = 6
      statistic.readingCurrentStreak = 4
      statistic.percentageCorrect = 85
      statistic.hidden = true
      try db.executeUpdate(
        "INSERT INTO review_stats VALUES (342, 42, ?)",
        values: [.blob(statistic.serializedData())])
    }
    try edit(db)
    return url
  }

  @Test func fullDatabaseImportsWithoutChangingSourceAndReopensNatively() async throws {
    let url = try fixture()
    let original = try Data(contentsOf: url)
    let source = try LegacyStudyImporter.read(from: url)
    #expect(try Data(contentsOf: url) == original)
    #expect(source.profile.maxLevelGranted == 60)
    #expect(source.profile.vacationStartedAt == 50)
    #expect(source.subjects.first?.meaningMnemonic == "Meaning <kanji>猫</kanji>")
    #expect(source.subjects.first?.sentences.first?.japanese == "猫です。")
    #expect(source.subjects.first?.partsOfSpeech == [1, 99])
    #expect(source.subjects.first?.gradingSubject.primaryReadings == ["ねこ"])
    #expect(source.pendingReviews.first?.submission.meaningWrongCount == 2)
    #expect(source.materials.first?.legacyRevision == 9)
    #expect(source.progress.first?.legacyRevision == 8)
    #expect(source.progress.first?.lastMistakeLocalTime == "2026-10-17 12:34:56")
    #expect(source.levels.first?.completedAt == 5)
    #expect(source.statistics.first?.readingMaxStreak == 6)
    #expect(source.voices.first?.description == "Fixture voice")
    #expect(source.audio.first?.voiceActorID == 7)
    #expect(source.cursors["review_stats_updated_after"] == "statistics")
    let native = url.deletingPathExtension().appendingPathExtension("store")
    do {
      let store = try await StudyStore.open(at: native)
      try await store.importLegacyAccount(
        source, sourceID: url.path,
        verifiedAccountID: "account-fixture",
        verifiedUsername: "fixture",
        credentialID: "credential-fixture")
    }
    let store = try await StudyStore.open(at: native)
    let materials = try await store.materials(accountID: "account-fixture")
    let reviews = try await store.pendingReviews(accountID: "account-fixture")
    let available = try await store.assignments(accountID: "account-fixture")
    #expect(materials.first?.material.meaningNote == "offline\u{0000}note\n猫")
    #expect(materials.first?.material.meaningSynonyms == ["kitty", "house cat"])
    #expect(materials.first?.pending == true)
    #expect(reviews.first?.submission == source.pendingReviews.first?.submission)
    #expect(reviews.first?.attempted == true)
    #expect(available.isEmpty)
    #expect(try Data(contentsOf: url) == original)
  }

  @Test func everySupportedSchemaAndDuplicateAssignmentMigration() throws {
    for version in 9...15 {
      let url = try fixture(version: version) { db in
        var old = TKMAssignment()
        old.id = 141
        old.subjectID = 42
        old.subjectType = .vocabulary
        try db.executeUpdate(
          "INSERT INTO assignments VALUES (141, 42, ?)",
          values: [.blob(old.serializedData())])
      }
      let source = try LegacyStudyImporter.read(from: url)
      #expect(source.assignments.map(\.id) == [142])
      #expect(source.supersededAssignments.map(\.id) == [141])
      #expect(
        source.progress.first?.lastMistakeLocalTime == (version >= 11 ? "2026-10-17 12:34:56" : nil)
      )
      #expect(source.statistics.count == (version >= 12 ? 1 : 0))
      #expect(source.materials.first?.legacyRevision == (version >= 14 ? 9 : 0))
      #expect(source.progress.first?.legacyRevision == (version >= 15 ? 8 : 0))
    }
  }

  @Test func versionNineInfersKanaVocabularyForAssignmentsAndPendingLessons() throws {
    let url = try fixture(version: 9) { db in
      var subject = TKMSubject()
      subject.id = 42
      subject.level = 12
      subject.japanese = "猫"
      subject.vocabulary = TKMVocabulary()
      try db.executeUpdate(
        "UPDATE subjects SET pb = ? WHERE id = 42",
        values: [.blob(subject.serializedData())])
      var progress = TKMProgress()
      progress.assignment.id = 142
      progress.assignment.subjectID = 42
      progress.assignment.subjectType = .vocabulary
      progress.isLesson = true
      try db.executeUpdate(
        "UPDATE pending_progress SET pb = ? WHERE id = 42",
        values: [.blob(progress.serializedData())])
    }
    let source = try LegacyStudyImporter.read(from: url)
    #expect(source.assignments.first?.isKanaOnlyVocabulary == true)
    #expect(source.pendingReviews.first?.assignment.isKanaOnlyVocabulary == true)
    #expect(source.pendingReviews.first?.submission.isLesson == true)
    #expect(source.pendingReviews.first?.submission.createdAt == nil)
  }

  @Test func malformedMismatchedOrOrphanedDataFailsWithoutModifyingSource() throws {
    for mutation in [
      "UPDATE pending_progress SET pb = X'FF'",
      "UPDATE subjects SET id = 999",
      "INSERT INTO pending_study_materials VALUES (999)",
      "DELETE FROM user",
      "INSERT INTO sync SELECT * FROM sync",
      "UPDATE subject_progress SET subject_type = 999",
      "PRAGMA user_version = 16",
      "PRAGMA user_version = 8",
    ] {
      let url = try fixture { #expect($0.executeStatements(mutation)) }
      let original = try Data(contentsOf: url)
      #expect(throws: LegacyImportError.self, Comment(rawValue: mutation)) {
        _ = try LegacyStudyImporter.read(from: url)
      }
      #expect(try Data(contentsOf: url) == original)
    }
  }

  @Test func unknownNestedFieldsAreRejectedInsteadOfLost() throws {
    let url = try fixture { db in
      var subject = TKMSubject()
      subject.id = 42
      subject.level = 12
      subject.japanese = "猫"
      // Field 99, varint 1: valid protobuf wire data unknown to the installed schema.
      subject.vocabulary = try TKMVocabulary(serializedData: Data([0x98, 0x06, 0x01]))
      try db.executeUpdate(
        "UPDATE subjects SET pb = ? WHERE id = 42",
        values: [.blob(subject.serializedData())])
    }
    #expect(throws: LegacyImportError.self) { _ = try LegacyStudyImporter.read(from: url) }
  }

  @Test func missingDatabaseIsNotCreated() {
    let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
    #expect(
      LegacyStudyImporter.databaseURL == URL(fileURLWithPath: "\(documents[0])/local-cache.db"))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".sqlite")
    #expect(throws: LegacyImportError.self) { _ = try LegacyStudyImporter.read(from: url) }
    #expect(!(FileManager.default.fileExists(atPath: url.path)))
  }

  @Test func radicalKanjiDetailsAndGradingInputsMatchLegacy() throws {
    var radical = TKMSubject()
    radical.id = 1
    radical.level = 1
    radical.radical.mnemonic = "Image mnemonic"
    radical.radical.deprecatedMnemonic = "Previous mnemonic"
    radical.radical.characterImage = "https://example.invalid/image.svg"
    radical.radical.hasCharacterImageFile_p = true
    var kanji = TKMSubject()
    kanji.id = 2
    kanji.level = 1
    kanji.japanese = "猫"
    kanji.kanji.meaningMnemonic = "Meaning"
    kanji.kanji.meaningHint = "Meaning hint"
    kanji.kanji.readingMnemonic = "Reading"
    kanji.kanji.readingHint = "Reading hint"
    kanji.kanji.visuallySimilarKanji = "苗"
    kanji.kanji.visuallySimilarKanjiIds = [3]
    kanji.componentSubjectIds = [1]
    kanji.amalgamationSubjectIds = [42]
    kanji.meanings = [
      TKMMeaning.TypeEnum.primary,
      .secondary,
      .auxiliaryWhitelist,
      .blacklist,
      .unknown,
    ].map { role in
      var value = TKMMeaning()
      value.type = role
      value.meaning = "meaning-\(role.rawValue)"
      return value
    }
    kanji.readings = [true, false].map { primary in
      var value = TKMReading()
      value.isPrimary = primary
      value.reading = primary ? "びょう" : "ねこ"
      value.type = primary ? .onyomi : .kunyomi
      return value
    }
    let url = try fixture { db in
      for value in [radical, kanji] {
        try db.executeUpdate(
          "INSERT INTO subjects VALUES (?, ?, ?, ?, ?)",
          values: [
            .integer(value.id), .text(value.japanese),
            .integer(Int64(value.level)), .integer(value.hasRadical ? 1 : 2),
            .blob(value.serializedData()),
          ])
      }
    }
    let source = try LegacyStudyImporter.read(from: url)
    let importedRadical = try #require(source.subjects.first { $0.id == 1 })
    let importedKanji = try #require(source.subjects.first { $0.id == 2 })
    #expect(importedRadical.hasCharacterImageFile)
    #expect(importedRadical.characterImageURL == radical.radical.characterImage)
    #expect(importedRadical.deprecatedMnemonic == radical.radical.deprecatedMnemonic)
    #expect(importedKanji.meaningHint == kanji.kanji.meaningHint)
    #expect(importedKanji.readingHint == kanji.kanji.readingHint)
    #expect(importedKanji.visuallySimilarKanjiIDs == [3])
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    #expect(
      try encoder.encode(importedKanji.gradingSubject) == encoder.encode(kanji.gradingSubject))
    #expect(
      try encoder.encode(importedRadical.gradingSubject)
        == encoder.encode(
          radical.gradingSubject))
  }

  @Test func wALImportSeesCommittedDataAndLeavesPendingWriterAlone() throws {
    let url = try fixture()
    let db = try LegacyFixtureDatabase(url)
    #expect(
      db
        .executeStatements(
          "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; UPDATE sync SET subjects_updated_after='committed';"
        ))
    #expect(db.executeStatements("BEGIN EXCLUSIVE TRANSACTION"))
    defer { #expect(db.executeStatements("ROLLBACK TRANSACTION")) }
    #expect(db.executeStatements("UPDATE sync SET subjects_updated_after='not committed'"))
    let wal = URL(fileURLWithPath: url.path + "-wal")
    let before = try Data(contentsOf: url)
    let beforeWAL = try Data(contentsOf: wal)
    let source = try LegacyStudyImporter.read(from: url)
    #expect(source.cursors["subjects_updated_after"] == "committed")
    #expect(try Data(contentsOf: url) == before)
    #expect(try Data(contentsOf: wal) == beforeWAL)
    #expect(db.isInTransaction)
  }
  @Test(arguments: Array(9...15))
  func bootstrapVerifiesEveryActualSchemaWithoutChangingItsSource(version: Int) async throws {
    let url = try fixture(version: version)
    let domain = "usagi-importer-prefs-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set(
      try NSKeyedArchiver.archivedData(
        withRootObject: "synthetic-import-token", requiringSecureCoding: true),
      forKey: "userApiToken")
    let oldDefaults = defaults.persistentDomain(forName: domain) as NSDictionary?

    let original = try Data(contentsOf: url)
    let source = try LegacyStudyImporter.read(from: url)
    let credentials = ImporterBootstrapCredentials()
    let native = url.appendingPathExtension("store")
    let verifier = ImporterBootstrapVerifier(profile: source.profile)
    let handoff: StudyLegacyHandoff
    do {
      let store = try await StudyStore.open(at: native)
      let bootstrap = StudyLegacyBootstrap(
        store: store, sourceID: "ios-main", credentials: credentials,
        preferences: .init(defaults: defaults), client: { _ in verifier },
        readLegacy: { try LegacyStudyImporter.source(database: url, defaults: defaults) })
      handoff = try await bootstrap.activate()
      #expect(
        handoff.activated && handoff.preferences != nil && handoff.mediaLayout == .legacyDocuments)
      #expect(
        (defaults.persistentDomain(forName: domain)?["userApiToken"] as? Data) == oldDefaults?[
          "userApiToken"] as? Data)
      let answers = try await store.pendingReviews(accountID: handoff.accountID)
      let notes = try await store.materials(accountID: handoff.accountID)
      #expect(
        answers.first?.attempted == true
          && answers.first?.submission == source.pendingReviews.first?.submission)
      #expect(notes.first?.pending == true && notes.first?.issue?.reason == .uncertain)
      #expect(notes.first?.material == source.materials.first?.value)
      #expect(try await store.snapshot(credentialID: handoff.credentialID)?.currentLevel == 13)
    }
    #expect(try Data(contentsOf: url) == original)
    let reopened = try await StudyStore.open(at: native)
    let resumed = StudyLegacyBootstrap(
      store: reopened, sourceID: "ios-main", credentials: credentials,
      preferences: .init(defaults: defaults), client: { _ in verifier },
      readLegacy: { throw CocoaError(.fileReadNoSuchFile) })
    #expect(try await resumed.activate() == handoff)
    #expect(
      try await reopened.pendingReviews(accountID: handoff.accountID).first?.submission
        == source.pendingReviews.first?.submission)
    #expect(try Data(contentsOf: url) == original)
  }

}

private struct ImporterBootstrapVerifier: WaniKaniAccountReader {
  let profile: StudyAccountProfile
  func account(token: String) -> WaniKaniAccount {
    var fresh = profile
    fresh.level = 13
    fresh.vacationStartedAt = nil
    return .init(
      id: "import-fixture", username: fresh.username, level: fresh.level,
      onVacation: false, startedAt: fresh.startedAt, profile: fresh)
  }
}
@MainActor private final class ImporterBootstrapCredentials: StudyCredentialStore {
  var token: String?
  func load() -> String? { token }
  func save(_ token: String) { self.token = token }
  func remove() { token = nil }
}

/// A disposable fixture writer only; production legacy imports remain read-only.
private final class LegacyFixtureDatabase {
  enum Value {
    case integer(Int64)
    case text(String)
    case blob(Data)
  }
  private let database: OpaquePointer
  init(_ url: URL) throws {
    var handle: OpaquePointer?
    let status = sqlite3_open_v2(
      url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
    guard status == SQLITE_OK, let handle else {
      if let handle { sqlite3_close(handle) }
      throw CocoaError(.fileWriteUnknown)
    }
    database = handle
  }
  deinit { sqlite3_close(database) }
  var isInTransaction: Bool { sqlite3_get_autocommit(database) == 0 }
  func executeStatements(_ sql: String) -> Bool {
    sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
  }
  func executeUpdate(_ sql: String, values: [Value]) throws {
    var statement: OpaquePointer?
    defer { if let statement { sqlite3_finalize(statement) } }
    try check(sqlite3_prepare_v2(database, sql, -1, &statement, nil))
    guard let statement, Int(sqlite3_bind_parameter_count(statement)) == values.count else {
      throw CocoaError(.fileWriteUnknown)
    }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      let status: Int32
      switch value {
      case .integer(let integer): status = sqlite3_bind_int64(statement, index, integer)
      case .text(let text):
        status = text.withCString {
          sqlite3_bind_text(statement, index, $0, Int32(text.utf8.count), transient)
        }
      case .blob(let data):
        status =
          data.isEmpty
          ? sqlite3_bind_zeroblob(statement, index, 0)
          : data.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient)
          }
      }
      try check(status)
    }
    try check(sqlite3_step(statement), expected: SQLITE_DONE)
  }
  private func check(_ status: Int32, expected: Int32 = SQLITE_OK) throws {
    guard status == expected else {
      throw NSError(
        domain: "LegacyFixtureSQLite", code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
  }
}
