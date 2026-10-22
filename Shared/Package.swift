// swift-tools-version: 6.4
import PackageDescription

// Keep stored domain values and persistence actor-neutral; app UI lives in the app target.
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
  ],
  targets: [
    .target(name: "StudyCore", resources: [.process("Resources")], swiftSettings: concurrency),
    .target(name: "StudyPersistence", dependencies: ["StudyCore"], swiftSettings: concurrency),
    .target(
      name: "StudyTestSupport", dependencies: ["StudyCore"], path: "Tests/StudyTestSupport",
      swiftSettings: warnings),
    .testTarget(
      name: "StudyPersistenceTests",
      dependencies: ["StudyPersistence", "StudyCore", "StudyTestSupport"], swiftSettings: warnings),
    .testTarget(
      name: "StudyCoreTests", dependencies: ["StudyCore", "StudyTestSupport"],
      swiftSettings: warnings),
  ],
  swiftLanguageModes: [.v6]
)
