// swift-tools-version:5.5
import PackageDescription

// Read-only legacy protobuf decoding. Native networking belongs to StudyCore.
let package = Package(
  name: "WaniKaniAPI",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [.library(name: "WaniKaniAPI", targets: ["WaniKaniAPI"])],
  dependencies: [
    .package(url: "https://github.com/apple/swift-protobuf", from: "1.15.0"),
    .package(url: "https://github.com/JanGorman/Hippolyte", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "WaniKaniAPI",
      dependencies: [
        .product(name: "SwiftProtobuf", package: "swift-protobuf")
      ]),
    .testTarget(name: "WaniKaniAPITests", dependencies: ["Hippolyte", "WaniKaniAPI"]),
  ])
