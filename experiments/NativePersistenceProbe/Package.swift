// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "NativePersistenceProbe", platforms: [.macOS("27.0")],
  targets: [.executableTarget(name: "NativePersistenceProbe")], swiftLanguageModes: [.v6])
