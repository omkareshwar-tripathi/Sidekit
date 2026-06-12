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
        // v1.0.0+ removed the swift-transformers dependency, unblocking mlx-swift-examples co-existence.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0"),
        // On-device LLM (Sidekit Intelligence, spec 2026-06-12). Pinned by the committed
        // Package.resolved; MLXLLM/MLXLMCommon run the two role models.
        // Note: upstream split MLXLLM/MLXLMCommon out of mlx-swift-examples into the
        // standalone mlx-swift-lm package (upstream PR #441).
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        // HuggingFace hub downloader + transformers tokenizer (needed by MLXHuggingFace macros).
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(name: "SidekitCore"),
        // The one network adapter (Supabase inserts), split out so SubmissionSelftest can
        // verify it headlessly (same pattern as ModelSelftest for the Whisper model).
        .target(name: "SidekitNet", dependencies: ["SidekitCore"]),
        // The on-device LLM engine + model files, split out (like SidekitNet) so
        // IntelligenceSelftest can verify the exact shipping adapters headlessly.
        .target(
            name: "SidekitIntelligence",
            dependencies: [
                "SidekitCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .executableTarget(
            name: "SidekitApp",
            dependencies: [
                "SidekitCore",
                "SidekitNet",
                "SidekitIntelligence",
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
        // Dev tool + Brick-0 gate: headlessly verify the on-device LLMs download, load, and
        // generate (spec 2026-06-12 §7). Usage: swift run -c release IntelligenceSelftest
        .executableTarget(
            name: "IntelligenceSelftest",
            dependencies: ["SidekitCore", "SidekitIntelligence"]
        ),
    ]
)
