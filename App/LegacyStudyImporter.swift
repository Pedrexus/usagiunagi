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
import WaniKaniAPI

/// One-time compatibility boundary. Opens a consistent read-only transaction and never changes
/// the legacy database. The caller must stop legacy writers and verify the account before cutover.
enum LegacyStudyImporter {
  @MainActor static func source(database: URL, defaults: UserDefaults) throws -> StudyLegacySource {
    let values = try LegacyPreferenceImporter.sourceValues(defaults: defaults)
    return try .init(
      token: values.token, account: read(from: database), preferences: values.preferences)
  }
  static func read(from url: URL) throws -> LegacyStudyExport {

    let db = try Reader(url)
    try db.execute("BEGIN")
    defer { try? db.execute("ROLLBACK") }
    var version = 0
    try db.rows("PRAGMA user_version") { version = try Int($0.integer(0)) }
    guard (9...15).contains(version) else { throw LegacyImportError.unsupportedSchema(version) }
    var users: [TKMUser] = []
    try db.rows("SELECT id, pb FROM user ORDER BY id") { row in
      try require(row.integer(0) == 0, "user identifier")
      try users.append(row.message(1))
    }
    guard users.count == 1, let user = users.first, !user.username.isEmpty else {
      throw LegacyImportError.invalidData("missing or ambiguous account")
    }
    var profile = StudyAccountProfile(username: user.username)
    profile.level = Int(user.level)
    profile.maxLevelGranted = Int(user.maxLevelGrantedBySubscription)
    profile.profileURL = user.profileURL
    profile.subscribed = user.subscribed
    profile.startedAt = user.hasStartedAt ? Int64(user.startedAt) : nil
    profile.subscriptionEndsAt = user.hasSubscriptionEndsAt ? Int64(user.subscriptionEndsAt) : nil
    profile.vacationStartedAt = user.hasVacationStartedAt ? Int64(user.vacationStartedAt) : nil
    var result = LegacyStudyExport(schemaVersion: version, profile: profile)
    try db.rows("SELECT id, japanese, level, type, pb FROM subjects ORDER BY id") { row in
      let value: TKMSubject = try row.message(4)
      let subject = try catalogSubject(value)
      try require(
        row.integer(0) == subject.id && row.text(1) == subject.japanese
          && row.integer(2) == Int64(subject.level) && kind(row.integer(3)) == subject.kind,
        "subject metadata")
      result.subjects.append(subject)
    }
    try require(
      Set(result.subjects.map(\.id)).count == result.subjects.count,
      "duplicate subject identifiers")
    let subjects = Dictionary(uniqueKeysWithValues: result.subjects.map { ($0.id, $0) })
    func assignment(_ value: TKMAssignment) throws -> CatalogAssignment {
      try known(value)
      try require(value.id > 0 && value.subjectID > 0, "assignment identifier")
      var item = try CatalogAssignment(
        id: value.id, subjectID: value.subjectID,
        kind: kind(Int64(value.subjectType.rawValue)))
      item.level = Int(value.level)
      item.srsStage = Int(value.srsStageNumber)
      item.availableAt = value.hasAvailableAt ? Int64(value.availableAt) : nil
      item.startedAt = value.hasStartedAt ? Int64(value.startedAt) : nil
      item.passedAt = value.hasPassedAt ? Int64(value.passedAt) : nil
      item.burnedAt = value.hasBurnedAt ? Int64(value.burnedAt) : nil
      item.isKanaOnlyVocabulary = value.isKanaOnlyVocab
      // Version 10 inferred this field from the catalog. Do the same without mutating old bytes.
      if version == 9, let subject = subjects[item.subjectID], subject.kind == .vocabulary,
        subject.readings.isEmpty
      {
        item.isKanaOnlyVocabulary = true
      }
      return item
    }
    var assignments: [Int64: CatalogAssignment] = [:]
    try db.rows("SELECT id, subject_id, pb FROM assignments ORDER BY id") { row in
      let item = try assignment(row.message(2))
      try require(
        row.integer(0) == item.id && row.integer(1) == item.subjectID,
        "assignment metadata")
      if let previous = assignments.updateValue(item, forKey: item.subjectID) {
        // Match the version-13 highest-ID migration, retaining the displaced record for recovery.
        result.supersededAssignments.append(previous)
      }
    }
    result.assignments = assignments.values.sorted { $0.subjectID < $1.subjectID }
    try db.rows("SELECT id, pb FROM pending_progress ORDER BY id") { row in
      let value: TKMProgress = try row.message(1)
      try require(
        value.hasAssignment && row.integer(0) == value.assignment.subjectID
          && value.meaningWrongCount >= 0 && value.readingWrongCount >= 0, "pending review payload")
      let item = try assignment(value.assignment)
      result.pendingReviews.append(
        .init(
          assignment: item,
          submission: .init(
            itemID: result.pendingReviews.count,
            subjectID: item.subjectID,
            assignmentID: item.id,
            isLesson: value.isLesson,
            meaningWrong: value.meaningWrong,
            readingWrong: value.readingWrong,
            meaningWrongCount: Int(
              value
                .meaningWrongCount),
            readingWrongCount: Int(
              value
                .readingWrongCount),
            createdAt: value
              .hasCreatedAt ? Int64(value.createdAt) : nil)))
    }
    var pendingMaterials = Set<Int64>()
    try db
      .rows("SELECT id FROM pending_study_materials ORDER BY id") {
        try pendingMaterials.insert($0.integer(0))
      }
    let materialRevision = version >= 14 ? "local_revision" : "0"
    try db.rows("SELECT id, pb, \(materialRevision) FROM study_materials ORDER BY id") { row in
      let value: TKMStudyMaterials = try row.message(1)
      try require(
        value.subjectID > 0 && row.integer(0) == value.subjectID,
        "study material identifier")
      try result.materials.append(
        .init(
          serverID: value.id,
          value: .init(
            subjectID: value.subjectID,
            meaningNote: value.meaningNote,
            readingNote: value.readingNote,
            meaningSynonyms: value.meaningSynonyms),
          pending: pendingMaterials.remove(value.subjectID) != nil,
          legacyRevision: row.integer(2)))
    }
    try require(pendingMaterials.isEmpty, "pending notes without their saved content")
    let mistake = version >= 11 ? "last_mistake_time" : "NULL"
    let progressRevision = version >= 15 ? "local_revision" : "0"
    try db
      .rows(
        "SELECT id, level, srs_stage, subject_type, \(mistake), \(progressRevision) FROM subject_progress ORDER BY id"
      ) { row in
        let id = try row.integer(0)
        try require(id > 0, "progress identifier")
        try result.progress.append(
          .init(
            subjectID: id, level: Int(row.integer(1)),
            srsStage: Int(row.integer(2)),
            kind: kind(row.integer(3)),
            lastMistakeLocalTime: row.optionalText(4),
            legacyRevision: row.integer(5)))
      }
    try db.rows("SELECT id, level, pb FROM level_progressions ORDER BY id") { row in
      let value: TKMLevel = try row.message(2)
      try require(
        value.id > 0 && row.integer(0) == value.id
          && row
            .integer(1) == Int64(value.level),
        "level progression identifier")
      var level = CatalogLevelProgression(id: value.id)
      level.level = Int(value.level)
      level.abandonedAt = value.hasAbandonedAt ? Int64(value.abandonedAt) : nil
      level.completedAt = value.hasCompletedAt ? Int64(value.completedAt) : nil
      level.createdAt = value.hasCreatedAt ? Int64(value.createdAt) : nil
      level.passedAt = value.hasPassedAt ? Int64(value.passedAt) : nil
      level.startedAt = value.hasStartedAt ? Int64(value.startedAt) : nil
      level.unlockedAt = value.hasUnlockedAt ? Int64(value.unlockedAt) : nil
      result.levels.append(level)
    }
    try db.rows("SELECT id, pb FROM voice_actors ORDER BY id") { row in
      let value: TKMVoiceActor = try row.message(1)
      try require(value.id > 0 && row.integer(0) == value.id, "voice actor identifier")
      var voice = StudyVoiceActor(id: value.id)
      voice.name = value.name
      voice.description = value.description_p
      voice.gender = value.gender.rawValue
      result.voices.append(voice)
    }
    try db
      .rows(
        "SELECT subject_id, voice_actor_id, level, url FROM audio_urls ORDER BY subject_id, voice_actor_id"
      ) { row in
        try result.audio.append(
          .init(
            subjectID: row.integer(0), voiceActorID: row.integer(1),
            level: Int(row.integer(2)), url: row.text(3)))
      }
    if version >= 12 {
      try db.rows("SELECT id, subject_id, pb FROM review_stats ORDER BY id") { row in
        let value: TKMReviewStatistic = try row.message(2)
        try require(
          value.id > 0 && value.subjectID > 0 && row.integer(0) == value.id
            && row.integer(1) == value.subjectID, "review statistic identifier")
        var statistic = try CatalogReviewStatistic(
          id: value.id,
          answers: .init(
            subjectID: value.subjectID,
            type: kind(
              Int64(
                value.type
                  .rawValue)),
            meaningCorrect: Int(
              value
                .meaningCorrect),
            meaningIncorrect: Int(
              value
                .meaningIncorrect),
            meaningCurrentStreak: Int(
              value
                .meaningCurrentStreak),
            readingCorrect: Int(
              value
                .readingCorrect),
            readingIncorrect: Int(
              value
                .readingIncorrect),
            readingCurrentStreak: Int(
              value
                .readingCurrentStreak),
            hidden: value.hidden))
        statistic.createdAt = value.hasCreatedAt ? Int64(value.createdAt) : nil
        statistic.meaningMaxStreak = Int(value.meaningMaxStreak)
        statistic.readingMaxStreak = Int(value.readingMaxStreak)
        statistic.percentageCorrect = Int(value.percentageCorrect)
        result.statistics.append(statistic)
      }
    }
    var columns = [
      "assignments_updated_after",
      "study_materials_updated_after",
      "subjects_updated_after",
      "voice_actors_updated_after",
    ]
    if version >= 12 { columns.append("review_stats_updated_after") }
    var syncRows = 0
    try db.rows("SELECT \(columns.joined(separator: ", ")) FROM sync") { row in
      syncRows += 1
      for (index, name)
        in columns
        .enumerated()
      { result.cursors[name] = try row.optionalText(Int32(index)) }
    }
    try require(syncRows == 1, "sync cursor row count")
    return result
  }

  static func catalogSubject(_ value: TKMSubject) throws -> CatalogSubject {
    try require(
      value.id > 0
        && [value.hasRadical, value.hasKanji, value.hasVocabulary]
          .filter { $0 }.count == 1,
      "subject kind")
    var subject = CatalogSubject(
      id: value.id,
      kind: value.hasRadical
        ? .radical
        : value
          .hasKanji ? .kanji : .vocabulary)
    subject.level = Int(value.level)
    subject.slug = value.slug
    subject.documentURL = value.documentURL
    subject.japanese = value.japanese
    subject.componentSubjectIDs = value.componentSubjectIds
    subject.amalgamationSubjectIDs = value.amalgamationSubjectIds
    subject.meanings = try value.meanings.map { meaning in
      try known(meaning)
      guard let role = CatalogSubject.Meaning.Role(rawValue: meaning.type.rawValue) else {
        throw LegacyImportError.invalidData("unknown meaning role")
      }
      return .init(meaning.meaning, role: role)
    }
    subject.readings = try value.readings.map { reading in
      try known(reading)
      guard let kind = CatalogSubject.Reading.Kind(rawValue: reading.type.rawValue) else {
        throw LegacyImportError.invalidData("unknown reading kind")
      }
      return .init(reading.reading, isPrimary: reading.isPrimary, kind: kind)
    }
    if value.hasRadical {
      let radical = value.radical
      try known(radical)
      subject.meaningMnemonic = radical.mnemonic
      subject.deprecatedMnemonic = radical.deprecatedMnemonic
      subject.characterImageURL = radical.characterImage
      subject.hasCharacterImageFile = radical.hasCharacterImageFile_p
    } else if value.hasKanji {
      let kanji = value.kanji
      try known(kanji)
      subject.meaningMnemonic = kanji.meaningMnemonic
      subject.meaningHint = kanji.meaningHint
      subject.readingMnemonic = kanji.readingMnemonic
      subject.readingHint = kanji.readingHint
      subject.visuallySimilarKanji = kanji.visuallySimilarKanji
      subject.visuallySimilarKanjiIDs = kanji.visuallySimilarKanjiIds
    } else {
      let vocabulary = value.vocabulary
      try known(vocabulary)
      subject.meaningMnemonic = vocabulary.meaningExplanation
      subject.readingMnemonic = vocabulary.readingExplanation
      subject.partsOfSpeech = vocabulary.partsOfSpeech.map(\.rawValue)
      subject.partOfSpeechNames = vocabulary.partsOfSpeech.map(\.description).filter { !$0.isEmpty }
      subject.sentences = try vocabulary.sentences.map {
        try known($0)
        return .init(japanese: $0.japanese, english: $0.english)
      }
      subject.audio = try vocabulary.audio.map {
        try known($0)
        return .init(url: $0.url, voiceActorID: $0.voiceActorID)
      }
    }
    return subject
  }

  private static func kind(_ raw: Int64) throws -> SubjectKind {
    switch raw {
    case 1: return .radical
    case 2: return .kanji
    case 3: return .vocabulary
    default: throw LegacyImportError.invalidData("unknown subject type")
    }
  }

  private static func require(
    _ condition: @autoclosure () throws -> Bool,
    _ detail: String
  ) throws {
    guard try condition() else { throw LegacyImportError.invalidData(detail) }
  }

  private static func known(_ message: some SwiftProtobuf.Message) throws {
    try require(message.unknownFields.data.isEmpty, "unrecognized protobuf fields")
  }

  private final class Reader {
    private let database: OpaquePointer
    init(_ url: URL) throws {
      var handle: OpaquePointer?
      let status = sqlite3_open_v2(
        url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
        nil)
      guard status == SQLITE_OK, let handle else {
        if let handle { sqlite3_close(handle) }
        throw LegacyImportError.invalidData("database could not be opened read-only")
      }
      database = handle
    }

    deinit { sqlite3_close(database) }
    func execute(_ sql: String) throws {
      guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw LegacyImportError.invalidData("database read transaction")
      }
    }

    func rows(_ sql: String, _ body: (Row) throws -> Void) throws {
      var statement: OpaquePointer?
      defer { if let statement { sqlite3_finalize(statement) } }
      guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
        let statement
      else {
        throw LegacyImportError.invalidData("missing or unreadable database structure")
      }
      var status = sqlite3_step(statement)
      while status == SQLITE_ROW {
        try body(Row(statement: statement))
        status = sqlite3_step(statement)
      }
      try require(status == SQLITE_DONE, "incomplete database read")
    }
  }

  private struct Row {
    let statement: OpaquePointer
    func integer(_ index: Int32) throws -> Int64 {
      try require(
        sqlite3_column_type(statement, index) == SQLITE_INTEGER,
        "non-integer database field")
      return sqlite3_column_int64(statement, index)
    }

    func optionalText(_ index: Int32) throws -> String? {
      sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : try text(index)
    }

    func text(_ index: Int32) throws -> String {
      try require(sqlite3_column_type(statement, index) == SQLITE_TEXT, "non-text database field")
      let count = Int(sqlite3_column_bytes(statement, index))
      guard let bytes = sqlite3_column_text(statement, index),
        let text = String(data: Data(bytes: bytes, count: count), encoding: .utf8)
      else {
        throw LegacyImportError.invalidData("invalid text encoding")
      }
      return text
    }

    func message<T: SwiftProtobuf.Message>(_ index: Int32) throws -> T {
      try require(sqlite3_column_type(statement, index) == SQLITE_BLOB, "missing protobuf content")
      let count = Int(sqlite3_column_bytes(statement, index))
      let data =
        sqlite3_column_blob(statement, index)
        .map { Data(bytes: $0, count: count) } ?? Data()
      let value: T
      do { value = try T(serializedData: data) } catch {
        throw LegacyImportError.invalidData("malformed protobuf content")
      }
      try known(value)
      return value
    }
  }
}
