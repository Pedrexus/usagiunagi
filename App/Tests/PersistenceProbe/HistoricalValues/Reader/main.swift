import CryptoKit
import Darwin
import Foundation

/// Runs only after staging the archived source closure; it never imports current domain modules.
@main struct HistoricalNativeValues {
  static func main() async {
    do {
      try NativeStoreBaseline.require(
        CommandLine.arguments.count == 2, "Expected the canonical synthetic baseline path")
      let fixture = URL(filePath: CommandLine.arguments[1])
      let manifest = try PropertyListDecoder().decode(
        NativeStoreBaseline.Manifest.self,
        from: Data(contentsOf: fixture.appendingPathExtension("baseline.plist")))
      let sourceCount = try verifySources(manifest)
      try await NativeStoreBaseline.run("read-native-baseline", url: fixture)
      print(
        "PASS: independent frozen writer \(manifest.writerCommit), \(sourceCount) source files, \(manifest.expected.records.count) exact records / 10 models / 15 Codable attributes, PID \(ProcessInfo.processInfo.processIdentifier)"
      )
    } catch {
      FileHandle.standardError.write(Data("Historical decoder check refused: \(error)\n".utf8))
      exit(74)
    }
  }

  private static func verifySources(_ manifest: NativeStoreBaseline.Manifest) throws -> Int {
    let shared = URL(filePath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appending(path: "Shared").resolvingSymlinksInPath()
    let manager = FileManager.default
    var paths = ["Package.swift"]
    for directory in ["Sources/StudyCore", "Sources/StudyPersistence"] {
      guard
        let files = manager.enumerator(
          at: shared.appending(path: directory), includingPropertiesForKeys: [.isRegularFileKey])
      else { throw NativeStoreBaseline.Failure(description: "Historical sources are missing") }
      for case let file as URL in files where file.pathExtension == "swift" {
        let canonical = file.resolvingSymlinksInPath()
        try NativeStoreBaseline.require(
          canonical.path.hasPrefix(shared.path + "/")
            && canonical.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
          "Historical source escaped its archive")
        paths.append(String(canonical.path.dropFirst(shared.path.count + 1)))
      }
    }
    paths.sort()
    try NativeStoreBaseline.require(
      paths == manifest.sourcePaths, "Historical compiler source closure differs from the writer")
    var digest = SHA256()
    digest.update(data: Data("usagi-native-baseline-source-v1\u{0000}".utf8))
    for path in paths {
      digest.update(data: Data((path + "\u{0000}").utf8))
      digest.update(data: try Data(contentsOf: shared.appending(path: path)))
      digest.update(data: Data([0]))
    }
    let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
    try NativeStoreBaseline.require(
      hash == manifest.writerSourceHash, "Historical source bytes differ from the frozen writer")
    return paths.count
  }
}
