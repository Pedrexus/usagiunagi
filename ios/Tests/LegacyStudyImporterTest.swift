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

import FMDB
import Foundation
import StudyCore
import StudyPersistence
import SwiftProtobuf
import WaniKaniAPI
import XCTest

final class LegacyStudyImporterTest: XCTestCase {
  private func fixture(version: Int = 15, edit: (FMDatabase) throws -> Void = { _ in
  }) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".sqlite")
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    let db = FMDatabase(url: url)
    XCTAssertTrue(db.open())
    defer { db.close() }
    XCTAssertTrue(db.executeStatements("""
    PRAGMA user_version = \(version);
    CREATE TABLE user (id INTEGER PRIMARY KEY, pb BLOB);
    CREATE TABLE subjects (id INTEGER PRIMARY KEY, japanese TEXT, level INTEGER, type INTEGER, pb BLOB);
    CREATE TABLE assignments (id INTEGER PRIMARY KEY, subject_id INTEGER, pb BLOB);
    CREATE TABLE pending_progress (id INTEGER PRIMARY KEY, pb BLOB);
    CREATE TABLE study_materials (id INTEGER PRIMARY KEY, pb BLOB\(version >= 14 ?
      ", local_revision INTEGER DEFAULT 0" : ""));
    CREATE TABLE pending_study_materials (id INTEGER PRIMARY KEY);
    CREATE TABLE subject_progress (id INTEGER PRIMARY KEY, level INTEGER, srs_stage INTEGER, subject_type INTEGER\(version >=
      11 ? ", last_mistake_time TEXT" : "")\(version >= 15 ? ", local_revision INTEGER DEFAULT 0" :
      ""));
    CREATE TABLE level_progressions (id INTEGER PRIMARY KEY, level INTEGER, pb BLOB);
    CREATE TABLE voice_actors (id INTEGER PRIMARY KEY, pb BLOB);
    CREATE TABLE audio_urls (subject_id INTEGER, voice_actor_id INTEGER, level INTEGER, url TEXT);
    CREATE TABLE sync (assignments_updated_after TEXT, study_materials_updated_after TEXT, subjects_updated_after TEXT, voice_actors_updated_after TEXT\(version >=
      12 ? ", review_stats_updated_after TEXT" : ""));
    INSERT INTO sync VALUES ('assignments','materials','subjects','voices'\(version >= 12 ?
      ",'statistics'" : ""));
    CREATE TABLE error_log (request_headers TEXT);
    INSERT INTO error_log VALUES ('diagnostic-fixture-must-stay-in-source');
    """))
    if version >=
      12 {
      XCTAssertTrue(db
        .executeStatements("CREATE TABLE review_stats (id INTEGER PRIMARY KEY, subject_id INTEGER, pb BLOB);"))
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
    try db.executeUpdate("INSERT INTO user VALUES (0, ?)", values: [user.serializedData()])
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
    try db.executeUpdate("INSERT INTO subjects VALUES (42, '猫', 12, 3, ?)",
                         values: [subject.serializedData()])
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
    try db.executeUpdate("INSERT INTO assignments VALUES (142, 42, ?)",
                         values: [assignment.serializedData()])
    var progress = TKMProgress()
    progress.assignment = assignment
    progress.createdAt = 120
    progress.meaningWrong = true
    progress.meaningWrongCount = 2
    progress.readingWrongCount = 0
    try db.executeUpdate("INSERT INTO pending_progress VALUES (42, ?)",
                         values: [progress.serializedData()])
    var material = TKMStudyMaterials()
    material.id = 242
    material.subjectID = 42
    material.meaningNote = "offline\u{0000}note\n猫"
    material.readingNote = "ねこ"
    material.meaningSynonyms = ["kitty", "house cat"]
    try db.executeUpdate("INSERT INTO study_materials (id, pb) VALUES (42, ?)",
                         values: [material.serializedData()])
    XCTAssertTrue(db
      .executeStatements("INSERT INTO pending_study_materials VALUES (42); INSERT INTO subject_progress (id, level, srs_stage, subject_type) VALUES (42,12,2,3);"))
    if version >= 11 { try db.executeUpdate("UPDATE subject_progress SET last_mistake_time = ?",
                                            values: ["2026-10-17 12:34:56"]) }
    if version >=
      14 { XCTAssertTrue(db.executeStatements("UPDATE study_materials SET local_revision = 9")) }
    if version >=
      15 { XCTAssertTrue(db.executeStatements("UPDATE subject_progress SET local_revision = 8")) }
    var level = TKMLevel()
    level.id = 5
    level.level = 12
    level.createdAt = 1
    level.unlockedAt = 2
    level.startedAt = 3
    level.passedAt = 4
    level.completedAt = 5
    level.abandonedAt = 6
    try db.executeUpdate("INSERT INTO level_progressions VALUES (5, 12, ?)",
                         values: [level.serializedData()])
    var voice = TKMVoiceActor()
    voice.id = 7
    voice.gender = .female
    voice.name = "Voice"
    voice.description_p = "Fixture voice"
    try db.executeUpdate("INSERT INTO voice_actors VALUES (7, ?)", values: [voice.serializedData()])
    try db.executeUpdate("INSERT INTO audio_urls VALUES (42, 7, 12, ?)", values: [audio.url])
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
      try db.executeUpdate("INSERT INTO review_stats VALUES (342, 42, ?)",
                           values: [statistic.serializedData()])
    }
    try edit(db)
    return url
  }

  func testFullDatabaseImportsWithoutChangingSourceAndReopensNatively() async throws {
    let url = try fixture(), original = try Data(contentsOf: url)
    let source = try LegacyStudyImporter.read(from: url)
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertEqual(source.profile.maxLevelGranted, 60)
    XCTAssertEqual(source.profile.vacationStartedAt, 50)
    XCTAssertEqual(source.subjects.first?.meaningMnemonic, "Meaning <kanji>猫</kanji>")
    XCTAssertEqual(source.subjects.first?.sentences.first?.japanese, "猫です。")
    XCTAssertEqual(source.subjects.first?.partsOfSpeech, [1, 99])
    XCTAssertEqual(source.subjects.first?.gradingSubject.primaryReadings, ["ねこ"])
    XCTAssertEqual(source.pendingReviews.first?.submission.meaningWrongCount, 2)
    XCTAssertEqual(source.materials.first?.legacyRevision, 9)
    XCTAssertEqual(source.progress.first?.legacyRevision, 8)
    XCTAssertEqual(source.progress.first?.lastMistakeLocalTime, "2026-10-17 12:34:56")
    XCTAssertEqual(source.levels.first?.completedAt, 5)
    XCTAssertEqual(source.statistics.first?.readingMaxStreak, 6)
    XCTAssertEqual(source.voices.first?.description, "Fixture voice")
    XCTAssertEqual(source.audio.first?.voiceActorID, 7)
    XCTAssertEqual(source.cursors["review_stats_updated_after"], "statistics")
    let native = url.deletingPathExtension().appendingPathExtension("store")
    addTeardownBlock {
      for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: native.path + suffix)
      }
    }
    do {
      let store = try await StudyStore.open(at: native)
      try await store.importLegacyAccount(source, sourceID: url.path,
                                          verifiedAccountID: "account-fixture",
                                          verifiedUsername: "fixture",
                                          credentialID: "credential-fixture")
    }
    let store = try await StudyStore.open(at: native)
    let materials = try await store.materials(accountID: "account-fixture")
    let reviews = try await store.pendingReviews(accountID: "account-fixture")
    let available = try await store.assignments(accountID: "account-fixture")
    XCTAssertEqual(materials.first?.material.meaningNote, "offline\u{0000}note\n猫")
    XCTAssertEqual(materials.first?.material.meaningSynonyms, ["kitty", "house cat"])
    XCTAssertTrue(materials.first?.pending == true)
    XCTAssertEqual(reviews.first?.submission, source.pendingReviews.first?.submission)
    XCTAssertTrue(reviews.first?.attempted == true)
    XCTAssertTrue(available.isEmpty)
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  func testEverySupportedSchemaAndDuplicateAssignmentMigration() throws {
    for version in 9 ... 15 {
      let url = try fixture(version: version) { db in
        var old = TKMAssignment()
        old.id = 141
        old.subjectID = 42
        old.subjectType = .vocabulary
        try db.executeUpdate("INSERT INTO assignments VALUES (141, 42, ?)",
                             values: [old.serializedData()])
      }
      let source = try LegacyStudyImporter.read(from: url)
      XCTAssertEqual(source.assignments.map(\.id), [142])
      XCTAssertEqual(source.supersededAssignments.map(\.id), [141])
      XCTAssertEqual(source.progress.first?.lastMistakeLocalTime,
                     version >= 11 ? "2026-10-17 12:34:56" : nil)
      XCTAssertEqual(source.statistics.count, version >= 12 ? 1 : 0)
      XCTAssertEqual(source.materials.first?.legacyRevision, version >= 14 ? 9 : 0)
      XCTAssertEqual(source.progress.first?.legacyRevision, version >= 15 ? 8 : 0)
    }
  }

  func testVersionNineInfersKanaVocabularyForAssignmentsAndPendingLessons() throws {
    let url = try fixture(version: 9) { db in
      var subject = TKMSubject()
      subject.id = 42
      subject.level = 12
      subject.japanese = "猫"
      subject.vocabulary = TKMVocabulary()
      try db.executeUpdate("UPDATE subjects SET pb = ? WHERE id = 42",
                           values: [subject.serializedData()])
      var progress = TKMProgress()
      progress.assignment.id = 142
      progress.assignment.subjectID = 42
      progress.assignment.subjectType = .vocabulary
      progress.isLesson = true
      try db.executeUpdate("UPDATE pending_progress SET pb = ? WHERE id = 42",
                           values: [progress.serializedData()])
    }
    let source = try LegacyStudyImporter.read(from: url)
    XCTAssertTrue(source.assignments.first?.isKanaOnlyVocabulary == true)
    XCTAssertTrue(source.pendingReviews.first?.assignment.isKanaOnlyVocabulary == true)
    XCTAssertTrue(source.pendingReviews.first?.submission.isLesson == true)
    XCTAssertNil(source.pendingReviews.first?.submission.createdAt)
  }

  func testMalformedMismatchedOrOrphanedDataFailsWithoutModifyingSource() throws {
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
      let url = try fixture { XCTAssertTrue($0.executeStatements(mutation)) }
      let original = try Data(contentsOf: url)
      XCTAssertThrowsError(try LegacyStudyImporter.read(from: url), mutation)
      XCTAssertEqual(try Data(contentsOf: url), original)
    }
  }

  func testUnknownNestedFieldsAreRejectedInsteadOfLost() throws {
    let url = try fixture { db in
      var subject = TKMSubject()
      subject.id = 42
      subject.level = 12
      subject.japanese = "猫"
      // Field 99, varint 1: valid protobuf wire data unknown to the installed schema.
      subject.vocabulary = try TKMVocabulary(serializedData: Data([0x98, 0x06, 0x01]))
      try db.executeUpdate("UPDATE subjects SET pb = ? WHERE id = 42",
                           values: [subject.serializedData()])
    }
    XCTAssertThrowsError(try LegacyStudyImporter.read(from: url))
  }

  func testMissingDatabaseIsNotCreated() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".sqlite")
    XCTAssertThrowsError(try LegacyStudyImporter.read(from: url))
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testRadicalKanjiDetailsAndGradingInputsMatchLegacy() throws {
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
        try db.executeUpdate("INSERT INTO subjects VALUES (?, ?, ?, ?, ?)",
                             values: [value.id, value.japanese,
                                      value.level, value.hasRadical ? 1 : 2,
                                      value.serializedData()])
      }
    }
    let source = try LegacyStudyImporter.read(from: url)
    let importedRadical = try XCTUnwrap(source.subjects.first { $0.id == 1 })
    let importedKanji = try XCTUnwrap(source.subjects.first { $0.id == 2 })
    XCTAssertTrue(importedRadical.hasCharacterImageFile)
    XCTAssertEqual(importedRadical.characterImageURL, radical.radical.characterImage)
    XCTAssertEqual(importedRadical.deprecatedMnemonic, radical.radical.deprecatedMnemonic)
    XCTAssertEqual(importedKanji.meaningHint, kanji.kanji.meaningHint)
    XCTAssertEqual(importedKanji.readingHint, kanji.kanji.readingHint)
    XCTAssertEqual(importedKanji.visuallySimilarKanjiIDs, [3])
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    XCTAssertEqual(try encoder.encode(importedKanji.gradingSubject),
                   try encoder.encode(kanji.gradingSubject))
    XCTAssertEqual(try encoder.encode(importedRadical.gradingSubject),
                   try encoder.encode(radical.gradingSubject))
  }

  func testWALImportSeesCommittedDataAndLeavesPendingWriterAlone() throws {
    let url = try fixture()
    let db = FMDatabase(url: url)
    XCTAssertTrue(db.open())
    defer { db.close() }
    XCTAssertTrue(db
      .executeStatements("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; UPDATE sync SET subjects_updated_after='committed';"))
    XCTAssertTrue(db.beginTransaction())
    defer { XCTAssertTrue(db.rollback()) }
    XCTAssertTrue(db.executeStatements("UPDATE sync SET subjects_updated_after='not committed'"))
    let wal = URL(fileURLWithPath: url.path + "-wal")
    let before = try Data(contentsOf: url), beforeWAL = try Data(contentsOf: wal)
    let source = try LegacyStudyImporter.read(from: url)
    XCTAssertEqual(source.cursors["subjects_updated_after"], "committed")
    XCTAssertEqual(try Data(contentsOf: url), before)
    XCTAssertEqual(try Data(contentsOf: wal), beforeWAL)
    XCTAssertTrue(db.isInTransaction)
  }
}
