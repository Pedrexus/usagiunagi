// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "NativePersistenceProbe", platforms: [.macOS("27.0")],
  dependencies: [.package(path: "../../../Shared")],
  targets: [
    .executableTarget(
      name: "NativePersistenceProbe",
      dependencies: [
        .product(name: "StudyPersistence", package: "Shared"),
        .product(name: "StudyCore", package: "Shared"),
      ])
  ], swiftLanguageModes: [.v6])
