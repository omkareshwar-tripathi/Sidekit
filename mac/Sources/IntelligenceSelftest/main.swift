import Foundation
import SidekitCore
import SidekitIntelligence

// Permanent headless verifier for the on-device LLMs (spec 2026-06-12 §7).
// Drives the REAL shipping adapters (MLXTextEngine + ModelDownloader) + IntelligencePrompt.
// Two-model variant: Gemma-2-2B polishes (NO system role — foldsSystemIntoUser = true),
// Qwen3-1.7B drafts (thinking off via additionalContext + sanitize strips any leak).
// Downloads on first run into the app's own Intelligence folder, then per model:
// load → real IntelligencePrompt generation → unload, printing timings.
// Exits non-zero on any failure.
// Budgets (spec §5): warm-disk load ≤ 5 s; each generation ≤ 8 s.
//
// RUNTIME PREREQ: mlx-swift ships no precompiled Metal library under SwiftPM — `mlx.metallib`
// must sit beside the binary (e.g. .build/release/mlx.metallib) or generation crashes at
// runtime. A clean `swift build -c release` clobbers it; re-place the metallib before running.
// The shipped .app needs the same file beside its executable (Task 7 / build-app.sh).
// See the GATE-B entry in BRICKS.md for how it was compiled.

let root = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Sidekit/Intelligence", isDirectory: true)

func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}

let clock = ContinuousClock()

func diskBytes(at url: URL) -> Int {
    var total = 0
    if let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
        for case let u as URL in files {
            total += (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
    }
    return total
}

do {
    // --- Model provisioning ---
    let downloader = ModelDownloader(root: root, log: { print("  \($0)") })
    if !downloader.isDownloaded {
        print("Models not found — downloading…")
        try await downloader.download { p in
            let pct = Int(p * 100)
            if pct % 10 == 0 { print("  download \(pct)%") }
        }
        print("Download complete.")
    } else {
        print("Models already on disk — skipping download.")
    }

    guard let polishDir = downloader.snapshotDirectory(for: ModelDownloader.polishRepoID) else {
        fail("polish snapshot directory not found at \(root.path)")
    }
    guard let draftDir = downloader.snapshotDirectory(for: ModelDownloader.draftRepoID) else {
        fail("draft snapshot directory not found at \(root.path)")
    }

    // --- Polish engine (Gemma-2-2B, foldsSystemIntoUser) ---
    let polishEngine = MLXTextEngine(
        modelDirectory: { polishDir },
        foldsSystemIntoUser: true)

    let (polishSystem, polishTemp) = IntelligencePrompt.build(chip: .polish, tone: .keepTone)
    let polishInput = "um so basically i think we should uh ship it on tuesday actually no wednesday"

    print("\nLoading polish engine (gemma-2-2b-it-4bit)…")
    let polishLoadStart = clock.now
    try await polishEngine.load()
    let polishLoadDuration = polishLoadStart.duration(to: clock.now)
    print("polish load: \(polishLoadDuration)")

    let polishGenStart = clock.now
    let polishRaw = try await polishEngine.generate(
        system: polishSystem, user: polishInput, temperature: polishTemp)
    let polishGenDuration = polishGenStart.duration(to: clock.now)
    print("polish gen: \(polishGenDuration)")

    let polished = IntelligencePrompt.sanitize(polishRaw)
    print("polish output:\n\(polished)\n")

    if polished.isEmpty { fail("polish returned empty") }
    if !polished.localizedCaseInsensitiveContains("wednesday") { fail("polish lost the correction") }

    await polishEngine.unload()
    print("polish engine unloaded.")

    // --- Draft engine (Qwen3-1.7B, no system fold, thinking off) ---
    let draftEngine = MLXTextEngine(
        modelDirectory: { draftDir },
        foldsSystemIntoUser: false)

    let (draftSystem, draftTemp) = IntelligencePrompt.build(chip: .draftEmail, tone: .professional)
    let draftInput = "tell priya the invoice for 4500 dollars went out, ask her to cc me going forward"

    print("Loading draft engine (Qwen3-1.7B-4bit)…")
    let draftLoadStart = clock.now
    try await draftEngine.load()
    let draftLoadDuration = draftLoadStart.duration(to: clock.now)
    print("draft load: \(draftLoadDuration)")

    let draftGenStart = clock.now
    let draftRaw = try await draftEngine.generate(
        system: draftSystem, user: draftInput, temperature: draftTemp)
    let draftGenDuration = draftGenStart.duration(to: clock.now)
    print("draft gen: \(draftGenDuration)")

    let drafted = IntelligencePrompt.sanitize(draftRaw)
    print("draft output:\n\(drafted)\n")

    if drafted.isEmpty { fail("draft returned empty") }
    if drafted.contains("<think>") { fail("thinking mode leaked into draft output") }
    if !drafted.contains("4500") { fail("draft dropped the exact amount") }

    await draftEngine.unload()
    print("draft engine unloaded.")

    // --- Totals ---
    let diskGB = Double(diskBytes(at: root)) / 1_073_741_824
    print(String(format: "disk: %.2f GB total", diskGB))
    print("PASS")
} catch {
    fail("\(error)")
}
