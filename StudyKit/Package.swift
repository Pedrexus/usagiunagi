// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StudyKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "StudyCore", targets: ["StudyCore"]),
        .library(name: "StudyUI", targets: ["StudyUI"])
    ],
    targets: [
        .target(name: "StudyCore", resources: [.process("Resources")]),
        .target(name: "StudyUI", dependencies: ["StudyCore"]),
        .testTarget(name: "StudyCoreTests", dependencies: ["StudyCore"])
    ],
    swiftLanguageModes: [.v6]
)
