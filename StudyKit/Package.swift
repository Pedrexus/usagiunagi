// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StudyKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "StudyCore", targets: ["StudyCore"]),
        .library(name: "StudyPersistence", targets: ["StudyPersistence"]),
        .library(name: "StudySpeech", targets: ["StudySpeech"]),
        .library(name: "StudyUI", targets: ["StudyUI"])
    ],
    targets: [
        .target(name: "StudyCore", resources: [.process("Resources")]),
        .target(name: "StudyPersistence", dependencies: ["StudyCore"]),
        .target(name: "StudySpeech", dependencies: ["StudyCore"]),
        .target(name: "StudyUI", dependencies: ["StudyCore", "StudySpeech"]),
        .testTarget(name: "StudyPersistenceTests", dependencies: ["StudyPersistence", "StudyCore"]),
        .testTarget(name: "StudyCoreTests", dependencies: ["StudyCore"]),
        .testTarget(name: "StudySpeechTests", dependencies: ["StudyCore", "StudySpeech"])
    ],
    swiftLanguageModes: [.v6]
)
