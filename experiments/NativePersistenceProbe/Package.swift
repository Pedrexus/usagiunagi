// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "NativePersistenceProbe", platforms: [.macOS("27.0")],
  dependencies: [.package(path: "../../StudyKit")],
  targets: [.executableTarget(name: "NativePersistenceProbe", dependencies: [
    .product(name: "StudyPersistence", package: "StudyKit"),
    .product(name: "StudyCore", package: "StudyKit")
  ])], swiftLanguageModes: [.v6])
