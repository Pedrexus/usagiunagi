// swift-tools-version: 6.4
import PackageDescription

// Mainboard stages this package beside the archived writer's unmodified Shared directory.
let concurrency: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("ExistentialAny"),
]
let package = Package(
  name: "HistoricalNativeValues",
  platforms: [.macOS("27.0")],
  targets: [
    .target(
      name: "StudyCore", path: "Shared/Sources/StudyCore",
      resources: [.process("Resources")], swiftSettings: concurrency),
    .target(
      name: "StudyPersistence", dependencies: ["StudyCore"],
      path: "Shared/Sources/StudyPersistence", swiftSettings: concurrency),
    .executableTarget(
      name: "HistoricalNativeValues", dependencies: ["StudyCore", "StudyPersistence"],
      path: "Reader"),
  ],
  swiftLanguageModes: [.v6])
