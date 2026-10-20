// swift-tools-version:6.2
import PackageDescription

// Read-only legacy protobuf decoding. Native networking belongs to StudyCore.
let package = Package(
  name: "WaniKaniAPI",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [.library(name: "WaniKaniAPI", targets: ["WaniKaniAPI"])],
  dependencies: [
    .package(url: "https://github.com/apple/swift-protobuf", exact: "1.39.0")
  ],
  targets: [
    .target(
      name: "WaniKaniAPI",
      dependencies: [
        .product(name: "SwiftProtobuf", package: "swift-protobuf")
      ],
      plugins: [.plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf")]),
    .testTarget(name: "WaniKaniAPITests", dependencies: ["WaniKaniAPI"]),
  ])
