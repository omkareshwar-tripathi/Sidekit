import Foundation
import SidekitCore
import SidekitIntelligence

// Permanent headless verifier for the on-device LLM (spec 2026-06-12 §7).
// Drives the REAL shipping adapters (MLXTextEngine + ModelDownloader) + IntelligencePrompt.
// Single-model variant: Qwen2.5-1.5B-Instruct-4bit serves BOTH polish and draft roles
// (Gemma-2 sidelined by an upstream mlx-swift-lm 3.31.3 forward-pass defect, see spec §7).
// Downloads on first run into the app's own Intelligence folder, then:
// load once → polish generation → draft generation (no unload between, mirrors shipping
// behaviour on a role switch) → unload once, printing timings.
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

    guard let modelDir = downloader.snapshotDirectory(for: ModelDownloader.modelRepoID) else {
        fail("model snapshot directory not found at \(root.path)")
    }

    // --- Single shared engine (Qwen2.5-1.5B, no system fold — it has a real system role) ---
    let engine = MLXTextEngine(modelDirectory: { modelDir })

    print("\nLoading engine (Qwen2.5-1.5B-Instruct-4bit)…")
    let loadStart = clock.now
    try await engine.load()
    let loadDuration = loadStart.duration(to: clock.now)
    print("load: \(loadDuration)")

    // --- Polish case (lab case sc-8, deterministic at greedy temp 0.0) ---
    let (polishSystem, polishTemp) = IntelligencePrompt.build(chip: .polish, tone: .keepTone)
    let polishInput = "lets meet on tuesday no wait wednesday at three"

    let polishGenStart = clock.now
    let polishRaw = try await engine.generate(
        system: polishSystem,
        user: IntelligencePrompt.userPayload(chip: .polish, tone: .keepTone, input: polishInput),
        temperature: polishTemp)
    let polishGenDuration = polishGenStart.duration(to: clock.now)
    print("polish gen: \(polishGenDuration)")

    let polished = IntelligencePrompt.sanitize(polishRaw)
    print("polish output:\n\(polished)\n")

    if polished.isEmpty { fail("polish returned empty") }
    if !polished.localizedCaseInsensitiveContains("wednesday") { fail("polish lost the correction") }
    if polished.localizedCaseInsensitiveContains("tuesday") { fail("polish kept the false start 'tuesday'") }

    // --- Draft case (same engine, no unload — mirrors a role-switch relabel in the app) ---
    let (draftSystem, draftTemp) = IntelligencePrompt.build(chip: .draftEmail, tone: .professional)
    let draftInput = "tell priya the invoice for 4500 dollars went out, ask her to cc me going forward"

    let draftGenStart = clock.now
    let draftRaw = try await engine.generate(
        system: draftSystem,
        user: IntelligencePrompt.userPayload(chip: .draftEmail, tone: .professional, input: draftInput),
        temperature: draftTemp)
    let draftGenDuration = draftGenStart.duration(to: clock.now)
    print("draft gen: \(draftGenDuration)")

    let drafted = IntelligencePrompt.sanitize(draftRaw)
    print("draft output:\n\(drafted)\n")

    if drafted.isEmpty { fail("draft returned empty") }
    if drafted.contains("<think>") { fail("thinking mode leaked into draft output") }
    let draftSanitizedForAmount = drafted.replacingOccurrences(of: ",", with: "")
    if !draftSanitizedForAmount.contains("4500") { fail("draft dropped the exact amount") }

    await engine.unload()
    print("engine unloaded.")

    // --- Totals ---
    let diskGB = Double(diskBytes(at: root)) / 1_073_741_824
    print(String(format: "disk: %.2f GB total", diskGB))
    print("PASS")
} catch {
    fail("\(error)")
}
