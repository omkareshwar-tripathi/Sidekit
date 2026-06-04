// swift-tools-version: 6.0
import PackageDescription

// SpeakType for Mac — native Swift dictation app (feat/mac-app).
// Ports-and-adapters: SpeakTypeCore is pure & unit-tested; SpeakTypeApp holds the
// native adapters + SwiftUI shell. WhisperKit is added in brick MAC-6 (transcription),
// so MAC-1 stays dependency-free and builds fast.
let package = Package(
    name: "SpeakTypeMac",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SpeakTypeCore"),
        .executableTarget(
            name: "SpeakTypeApp",
            dependencies: ["SpeakTypeCore"]
        ),
        .testTarget(
            name: "SpeakTypeCoreTests",
            dependencies: ["SpeakTypeCore"]
        ),
    ]
)
