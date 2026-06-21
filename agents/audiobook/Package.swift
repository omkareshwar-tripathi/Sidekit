// swift-tools-version: 6.0
import PackageDescription

// Audiobook Agent (macOS) — the first voice-agent built end-to-end to prove the
// listen→decide→act→verify loop. AudiobookCore is pure & unit-tested; AudiobookApp
// holds the AVFoundation/timer adapters + SwiftUI shell. Sub-project A: no AI yet.
let package = Package(
    name: "AudiobookAgent",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AudiobookCore"),
        .executableTarget(
            name: "AudiobookApp",
            dependencies: ["AudiobookCore"],
            resources: [.copy("Resources")]   // Sources/AudiobookApp/Resources
        ),
        .testTarget(name: "AudiobookCoreTests", dependencies: ["AudiobookCore"]),
    ]
)
