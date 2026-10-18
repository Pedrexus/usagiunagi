import CoreTransferable
import Foundation
import SQLite3
import UniformTypeIdentifiers

public struct SQLiteDiagnosticArchive: Transferable, Sendable {
  public let source: URL
  public init(source: URL) { self.source = source }
  public static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .database) { archive in
      SentTransferredFile(try await copy(from: archive.source))
    }
  }

  /// Copy a live legacy database, including committed WAL pages and exact row identifiers.
  @concurrent public static func copy(from source: URL, directory: URL = .temporaryDirectory)
    async throws -> URL
  {
    guard source.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
    let input = try open(source, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
    defer { sqlite3_close(input) }
    let folder = directory.appendingPathComponent("usagiunagi-diagnostics-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    var complete = false
    defer { if !complete { try? FileManager.default.removeItem(at: folder) } }
    let file = folder.appendingPathComponent("usagiunagi-diagnostics.db")
    let output = try open(
      file, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX)
    defer { sqlite3_close(output) }
    sqlite3_busy_timeout(input, 100)
    sqlite3_busy_timeout(output, 100)
    guard let backup = sqlite3_backup_init(output, "main", input, "main") else {
      throw Failure(code: sqlite3_errcode(output))
    }
    var finished = false
    defer { if !finished { sqlite3_backup_finish(backup) } }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while true {
      try Task.checkCancellation()
      let status = sqlite3_backup_step(backup, 256)
      if status == SQLITE_DONE { break }
      guard [SQLITE_OK, SQLITE_BUSY, SQLITE_LOCKED].contains(status), ContinuousClock.now < deadline
      else {
        throw Failure(code: status == SQLITE_OK ? SQLITE_BUSY : status)
      }
      if status != SQLITE_OK { try await Task.sleep(for: .milliseconds(25)) }
    }
    let result = sqlite3_backup_finish(backup)
    finished = true
    guard result == SQLITE_OK else { throw Failure(code: result) }
    guard sqlite3_exec(output, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
      throw Failure(code: sqlite3_errcode(output))
    }
    complete = true
    return file
  }

  private static func open(_ url: URL, flags: Int32) throws -> OpaquePointer {
    var database: OpaquePointer?
    let status = sqlite3_open_v2(url.path, &database, flags, nil)
    guard status == SQLITE_OK, let database else {
      if let database { sqlite3_close(database) }
      throw Failure(code: status)
    }
    return database
  }
  private struct Failure: LocalizedError {
    let code: Int32
    var errorDescription: String? {
      "The local database could not be copied (SQLite \(code)). Try again after synchronization finishes."
    }
  }
}
