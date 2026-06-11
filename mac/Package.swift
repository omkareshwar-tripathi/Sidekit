// swift-tools-version: 6.0
import PackageDescription

// Sidekit (macOS) — native Swift app (feat/mac-app).
// Ports-and-adapters: SidekitCore is pure & unit-tested; SidekitApp holds the
// native adapters + SwiftUI shell. WhisperKit is added in brick MAC-6 (transcription),
// so MAC-1 stays dependency-free and builds fast.
let package = Package(
    name: "Sidekit",
    platforms: [.macOS(.v14)],
    dependencies: [
        // On-device Whisper on the Neural Engine (brick MAC-6).
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(name: "SidekitCore"),
        // The one network adapter (Supabase inserts), split out so SubmissionSelftest can
        // verify it headlessly (same pattern as ModelSelftest for the Whisper model).
        .target(name: "SidekitNet", dependencies: ["SidekitCore"]),
        .executableTarget(
            name: "SidekitApp",
            dependencies: [
                "SidekitCore",
                "SidekitNet",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(
            name: "SidekitCoreTests",
            dependencies: ["SidekitCore"]
        ),
        // Dev tool: headlessly verify the bundled model loads + transcribes offline.
        // Usage: swift run ModelSelftest <modelFolder> <audioPath>
        .executableTarget(
            name: "ModelSelftest",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")]
        ),
        // Dev tool: verify the Supabase sender headlessly against a real project or a
        // local stand-in. Usage:
        //   SIDEKIT_SUPABASE_URL=… SIDEKIT_SUPABASE_KEY=… swift run SubmissionSelftest
        .executableTarget(
            name: "SubmissionSelftest",
            dependencies: ["SidekitCore", "SidekitNet"]
        ),
    ]
)
