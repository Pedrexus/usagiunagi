// Synthetic diagnostics only; UI tests never export the account database or clear user caches.
#if DEBUG
  import Foundation
  import SQLite3
  import WaniKaniAPI

  extension Screenshotter {
    @nonobjc @MainActor static func developerFixture() -> URL? { DeveloperFixture.database }
  }
  @MainActor private enum DeveloperFixture {
    static let database: URL? = {
      guard Screenshotter.isActive,
        ProcessInfo.processInfo.arguments.contains("DeveloperFlowFixture")
      else { return nil }
      var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
      arguments["apiBaseUrl"] = try? NSKeyedArchiver.archivedData(
        withRootObject: WaniKaniAPIClient.defaultBaseUrl, requiringSecureCoding: true)
      UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
      Settings.apiBaseUrl = WaniKaniAPIClient.defaultBaseUrl
      let directory = URL.temporaryDirectory.appendingPathComponent("developer-fixture-\(UUID())")
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("fixture.db")
      var database: OpaquePointer?
      if sqlite3_open(file.path, &database) == SQLITE_OK, let database {
        sqlite3_exec(
          database,
          "CREATE TABLE fixture(value TEXT); INSERT INTO fixture VALUES('Synthetic diagnostics');",
          nil, nil, nil)
      }
      if let database { sqlite3_close(database) }
      return file
    }()
  }
#endif
