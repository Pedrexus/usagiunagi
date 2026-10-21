// swift-tools-version: 6.4
import PackageDescription

// Keep domain values and persistence actor-neutral. UI declarations default to MainActor.
// Async helpers inherit the caller unless an explicit @concurrent boundary moves the work.
let warnings: [SwiftSetting] = [.treatAllWarnings(as: .error)]
let concurrency: [SwiftSetting] =
  warnings + [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ExistentialAny"),
  ]

let package = Package(
  name: "StudyKit",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [
    .library(name: "StudyCore", targets: ["StudyCore"]),
    .library(name: "StudyPersistence", targets: ["StudyPersistence"]),
    .library(name: "StudySpeech", targets: ["StudySpeech"]),
    .library(name: "StudyUI", targets: ["StudyUI"]),
  ],
  targets: [
    .target(name: "StudyCore", resources: [.process("Resources")], swiftSettings: concurrency),
    .target(name: "StudyPersistence", dependencies: ["StudyCore"], swiftSettings: concurrency),
    .target(name: "StudySpeech", dependencies: ["StudyCore"], swiftSettings: concurrency),
    .target(
      name: "StudyUI", dependencies: ["StudyCore", "StudySpeech", "StudyPersistence"],
      resources: [.process("Resources")],
      swiftSettings: concurrency + [.defaultIsolation(MainActor.self)]),
    .target(
      name: "StudyTestSupport", dependencies: ["StudyCore"], path: "Tests/StudyTestSupport",
      swiftSettings: warnings),
    .testTarget(
      name: "StudyPersistenceTests",
      dependencies: ["StudyPersistence", "StudyCore", "StudyTestSupport"], swiftSettings: warnings),
    .testTarget(
      name: "StudyCoreTests", dependencies: ["StudyCore", "StudyTestSupport"],
      swiftSettings: warnings),
    .testTarget(
      name: "StudySpeechTests", dependencies: ["StudyCore", "StudySpeech"], swiftSettings: warnings),
    .testTarget(
      name: "StudyUITests",
      dependencies: ["StudyUI", "StudyPersistence", "StudyCore", "StudyTestSupport"],
      swiftSettings: warnings),
  ],
  swiftLanguageModes: [.v6]
)
