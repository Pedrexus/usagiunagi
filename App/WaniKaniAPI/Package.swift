// swift-tools-version:5.5
import PackageDescription

// Temporary legacy API boundary; its active host has the same deployment floor as StudyKit.
let package = Package(
  name: "WaniKaniAPI",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [.library(name: "WaniKaniAPI", targets: ["WaniKaniAPI"])],
  dependencies: [
    .package(path: "../../Shared"),
    .package(url: "https://github.com/apple/swift-protobuf", from: "1.15.0"),
    .package(url: "https://github.com/mxcl/PromiseKit", from: "6.13.3"),
    .package(
      name: "PMKFoundation", url: "https://github.com/PromiseKit/Foundation.git", from: "3.3.4"),
    .package(url: "https://github.com/JanGorman/Hippolyte", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "WaniKaniAPI",
      dependencies: [
        .product(name: "StudyCore", package: "Shared"),
        "PromiseKit", "PMKFoundation",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ]),
    .testTarget(name: "WaniKaniAPITests", dependencies: ["Hippolyte", "WaniKaniAPI"]),
    .testTarget(name: "WaniKaniAPIProber", dependencies: ["WaniKaniAPI"]),
  ])
