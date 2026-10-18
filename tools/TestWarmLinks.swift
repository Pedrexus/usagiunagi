import Darwin
import Foundation

struct WarmLinkRequest: Decodable {
  let id: UUID
  let url: URL
}

struct CommandFailure: Error { let message: String }
func xcrun(_ arguments: [String]) throws -> String {
  let process = Process()
  let output = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  process.arguments = arguments
  process.standardOutput = output
  process.standardError = FileHandle.nullDevice
  try process.run()
  let data = output.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw CommandFailure(message: arguments.joined(separator: " "))
  }
  return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

guard CommandLine.arguments.count == 3 else {
  fatalError("Expected simulator ID and derived-data directory")
}
let device = CommandLine.arguments[1]
let derivedData = CommandLine.arguments[2]
let test = Process()
test.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
test.arguments = [
  "xcodebuild", "test", "-onlyUsePackageVersionsFromResolvedFile",
  "-workspace", "ios/Tsurukame.xcworkspace", "-scheme", "ReviewValidation",
  "-destination", "platform=iOS Simulator,id=\(device)", "-derivedDataPath", derivedData,
  "-only-testing:AppStoreScreenshots/ReviewFlowTests/testNativeTabsPreserveWarmStudyLinksAndReturnToStatistics",
  "CODE_SIGNING_ALLOWED=NO",
]
test.standardOutput = FileHandle.standardOutput
test.standardError = FileHandle.standardError
let started = Date()
var consumed = Set<UUID>()
var marker: URL?
var nextContainerCheck = Date.distantPast
let allowed = Set(["/reviews", "/lessons", "/subject/3864"])
try test.run()
do {
  while test.isRunning {
    if Date() >= nextContainerCheck {
      nextContainerCheck = Date().addingTimeInterval(1)
      if let container = try? xcrun([
        "simctl", "get_app_container", device,
        "com.davidsansome.wanikani.AppStoreScreenshots.xctrunner", "data",
      ]) {
        marker = URL(fileURLWithPath: container).appendingPathComponent("tmp/usagi-warm-link.json")
      }
    }
    if let marker,
      let attributes = try? FileManager.default.attributesOfItem(atPath: marker.path),
      let modified = attributes[.modificationDate] as? Date, modified >= started,
      let bytes = try? Data(contentsOf: marker),
      let request = try? JSONDecoder().decode(WarmLinkRequest.self, from: bytes),
      consumed.insert(request.id).inserted
    {
      guard request.url.scheme == "tsurukame", request.url.query == nil,
        request.url.fragment == nil, allowed.contains(request.url.path)
      else { throw CommandFailure(message: "Unexpected test route") }
      _ = try xcrun(["simctl", "openurl", device, request.url.absoluteString])
      FileHandle.standardError.write(
        Data("Delivered warm study route at \(Date()): \(request.url.path)\n".utf8))
    }
    Thread.sleep(forTimeInterval: 0.1)
  }
  test.waitUntilExit()
  guard test.terminationStatus == 0 else { exit(test.terminationStatus) }
  guard consumed.count == allowed.count else {
    throw CommandFailure(message: "Not all warm routes were delivered")
  }
} catch {
  if test.isRunning {
    test.terminate()
    test.waitUntilExit()
  }
  throw error
}
