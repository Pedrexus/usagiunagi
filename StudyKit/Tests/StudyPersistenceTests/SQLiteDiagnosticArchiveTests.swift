import Foundation
import SQLite3
import Testing

@testable import StudyPersistence

struct SQLiteDiagnosticArchiveTests {
  @Test func liveWALSnapshotPreservesRowsIdentifiersAndSchemaWithoutChangingSource() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("cache's 日本.db")
    let writer = try Database(source)
    try writer.execute(
      "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; PRAGMA user_version=15; CREATE TABLE pending(payload BLOB); INSERT INTO pending(rowid,payload) VALUES(47,X'0001FF');"
    )
    let original = try Data(contentsOf: source)
    let wal = try Data(contentsOf: URL(fileURLWithPath: source.path + "-wal"))
    let exported = try await SQLiteDiagnosticArchive.copy(from: source, directory: folder)
    let reader = try Database(exported)
    #expect(try reader.scalar("PRAGMA user_version") == 15)
    #expect(try reader.scalar("SELECT rowid FROM pending") == 47)
    #expect(try reader.scalar("SELECT length(payload) FROM pending") == 3)
    #expect(try reader.scalar("SELECT hex(payload)='0001FF' FROM pending") == 1)
    #expect(
      try reader.scalar("SELECT count(*) FROM pragma_integrity_check WHERE integrity_check != 'ok'")
        == 0)
    #expect(!FileManager.default.fileExists(atPath: exported.path + "-wal"))
    #expect(try Data(contentsOf: source) == original)
    #expect(try Data(contentsOf: URL(fileURLWithPath: source.path + "-wal")) == wal)
    try writer.execute("INSERT INTO pending(payload) VALUES(X'99')")
    #expect(try reader.scalar("SELECT count(*) FROM pending") == 1)
    #expect(try writer.scalar("SELECT count(*) FROM pending") == 2)
  }

  @Test func eachExportHasItsOwnImmutableFile() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("cache.db")
    let database = try Database(source)
    try database.execute("CREATE TABLE note(value INTEGER); INSERT INTO note VALUES(1);")
    let first = try await SQLiteDiagnosticArchive.copy(from: source, directory: folder)
    try database.execute("UPDATE note SET value=2")
    let second = try await SQLiteDiagnosticArchive.copy(from: source, directory: folder)
    #expect(first != second)
    #expect(try Database(first).scalar("SELECT value FROM note") == 1)
    #expect(try Database(second).scalar("SELECT value FROM note") == 2)
  }

  @Test(arguments: [false, true]) func failedExportsNeverCreateSourceOrKeepPartialCopies(
    _ corrupt: Bool
  ) async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("cache.db")
    if corrupt { try Data("not sqlite".utf8).write(to: source) }
    await #expect(throws: (any Error).self) {
      try await SQLiteDiagnosticArchive.copy(from: source, directory: folder)
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil)
    #expect(files.map(\.lastPathComponent) == (corrupt ? ["cache.db"] : []))
    if corrupt { #expect(try Data(contentsOf: source) == Data("not sqlite".utf8)) }
  }

  private func temporaryFolder() throws -> URL {
    let folder = URL.temporaryDirectory.appendingPathComponent("diagnostic-test-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}

private final class Database {
  private let handle: OpaquePointer
  init(_ url: URL) throws {
    var database: OpaquePointer?
    guard
      sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        == SQLITE_OK,
      let database
    else { throw CocoaError(.fileReadUnknown) }
    handle = database
  }
  deinit { sqlite3_close(handle) }
  func execute(_ sql: String) throws {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
      throw CocoaError(.fileReadCorruptFile)
    }
  }
  func scalar(_ sql: String) throws -> Int64 {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw CocoaError(.fileReadCorruptFile)
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw CocoaError(.fileReadCorruptFile) }
    return sqlite3_column_int64(statement, 0)
  }
}
