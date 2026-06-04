// swift-tools-version: 6.0
import PackageDescription

// SpeakType for Mac — native Swift dictation app (feat/mac-app).
// Ports-and-adapters: SpeakTypeCore is pure & unit-tested; SpeakTypeApp holds the
// native adapters + SwiftUI shell. WhisperKit is added in brick MAC-6 (transcription),
// so MAC-1 stays dependency-free and builds fast.
let package = Package(
    name: "SpeakTypeMac",
    platforms: [.macOS(.v14)],
    dependencies: [
        // On-device Whisper on the Neural Engine (brick MAC-6).
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(name: "SpeakTypeCore"),
        .executableTarget(
            name: "SpeakTypeApp",
            dependencies: [
                "SpeakTypeCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(
            name: "SpeakTypeCoreTests",
            dependencies: ["SpeakTypeCore"]
        ),
        // Dev tool: headlessly verify the bundled model loads + transcribes offline.
        // Usage: swift run ModelSelftest <modelFolder> <audioPath>
        .executableTarget(
            name: "ModelSelftest",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")]
        ),
    ]
)
