# Sidekit Intelligence v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The floating pill grows a hover menu (Polish · Scratchpad · Dictate) backed by two role-specific on-device LLMs (Gemma-2-2B polishes, Qwen3-1.7B drafts — only one ever warm) that load on demand and unload after idle — per `docs/superpowers/specs/2026-06-12-sidekit-intelligence-v1-design.md`.

**Architecture:** Ports-and-adapters. Pure core: `IntelligencePrompt` (chip×tone → exact prompt strings, sanitation, input cap) + `IntelligenceSession` (the RAM-guest state machine over `TextGenerating`/`ModelProvisioning`/`IntelligenceIdleTimer` ports). App adapters: two `MLXTextEngine` instances (MLX Swift — Gemma with the system prompt folded into the user turn, Qwen with thinking off), `ModelDownloader` (both HF hub snapshots, one combined download), `MemoryPressureSource`, plus the scratchpad panel (FeedbackBox pattern) and the pill hover menu. A headless `IntelligenceSelftest` executable is the Brick-0 gate and stays as the permanent live verifier.

**Tech Stack:** Swift 6 / SwiftPM, swift-testing (`@Test`/`#expect`), MLX Swift (`mlx-swift-examples`: MLXLLM + MLXLMCommon), Hugging Face hub via swift-transformers' `Hub`, lab gate via the existing Python MLX harness (`lab/whisper-compare`).

**Verification baseline:** `swift test` currently passes **152/152** (run from `mac/`). This plan adds **29** core tests (13 prompt + 16 session) → **181** expected at the end.

**Third-party drift rule (Tasks 2 & 5 only):** `mlx-swift-examples` API names move between releases. The code below targets the current `main` API (`LLMModelFactory.loadContainer` / `ModelContainer.perform` / `UserInput(chat:)` / `Generation.chunk`). If the pinned revision's signatures differ, adapt the *call sites* to the pinned equivalents — the printed contract (load seconds, generation seconds, outputs free of `<think>`) and the port signatures (`TextGenerating` etc.) are fixed and must not change. This rule covers ONLY the MLX/Hub API surface; everything else in this plan is exact.

---

## Task 1 — Gate A: Qwen3.5-2B through the cleanup eval (lab)

The shared model must polish as faithfully as the dedicated cleanup pick. `qwen3.5-2b` is already registered in `lab/whisper-compare/server.py` `LLM_MODELS` (with `think: False`); it has simply never been run on `p7_faithful`. Reference bar (run 20260608-235816): **gemma-2-2b = 148/190 PASS, bloat 2**.

**Skill:** none (lab harness; gentle-thermal house rules — small batches, cooldowns, one model in RAM).

**Files:**
- No source changes. New generated results land in `lab/whisper-compare/tune_runs/` (NOTE: `/lab/` is gitignored — results live on disk only; the spec records the numbers durably).
- Modify: `docs/superpowers/specs/2026-06-12-sidekit-intelligence-v1-design.md` (one line — see step 3).

- [ ] **Step 1: Free RAM, then run the eval (default gentle settings)**

```bash
cd /Users/omkareshwartripathi/SpeakType/lab/whisper-compare
lsof -nP -iTCP:5005 -sTCP:LISTEN -t | xargs kill 2>/dev/null   # stop any idle lab server
.venv/bin/python tune_prompts.py --models qwen3.5-2b --prompts p7_faithful
```

Expected: a new `tune_runs/<timestamp>.md` + `.json` with a scorecard row for `qwen3.5-2b` / `p7_faithful`. (If `.venv` is missing, run `./run.sh` once to create it, then Ctrl-C the server and re-run the eval.)

- [ ] **Step 2: Read the scorecard and apply the gate**

**PASS bar: `qwen3.5-2b` PASS ≥ 143/190 AND bloat ≤ 2** (within 5 PASS of gemma-2-2b's 148, no extra bloat — this calibrates the spec's "within 1 point", which was phrased on the 29-point assistant scale).

- **Gate passes** → proceed to Step 3.
- **Gate fails** → STOP this task and report BLOCKED with the scorecard. The controller switches the plan to the spec §7 two-model fallback (Gemma-2-2B for Polish, Qwen3.5 for drafting) — that changes Tasks 3/5/6 constants and must go back through the user.

- [ ] **Step 3: Record the calibrated bar in the spec**

In `docs/superpowers/specs/2026-06-12-sidekit-intelligence-v1-design.md` §7, replace:

`**Pass = within 1 point of Gemma-2-2B's score.**`

with:

`**Pass = PASS ≥ 143/190 and bloat ≤ 2 on the 190-case set (gemma-2-2b reference: 148/190, bloat 2). Result: <PASS>/190, bloat <N> — passed <date>.**` (fill the actual numbers).

- [ ] **Step 4: Commit**

```bash
cd /Users/omkareshwartripathi/SpeakType
git add lab/whisper-compare/tune_runs/ docs/superpowers/specs/2026-06-12-sidekit-intelligence-v1-design.md
git commit -m "lab: Gate A — qwen3.5-2b passes p7_faithful cleanup eval (Intelligence v1 §7)"
```

**OUTCOME (2026-06-12): GATE FAILED — two-model fallback adopted.** `qwen3.5-2b` scored **127/190, bloat 4** (run `tune_runs/20260612-152848`; worst categories: self-corrections 4/14, fillers 3/12, answers-the-transcript 3/10). A follow-up assistant run on `gemma-2-2b` (`assistant_runs/20260612-153130`) scored **19/29 with the arithmetic guardrail 0/2** — neither model covers both roles. **User decision: ship the two-model variant** — Gemma-2-2B polishes, Qwen3.5-2B drafts, one warm at a time. Steps 3–4 above were superseded: the controller recorded the failure + decision in the spec and committed it with both lab runs. **Every task below is already amended to the two-model variant.**

---

## Task 2 — Gate B: MLX Swift dependency + `IntelligenceSelftest`

Prove the Swift runtime can load the model and generate, before any product code. The selftest is the permanent headless verifier (ModelSelftest/SubmissionSelftest precedent).

**Skill:** none (verification-before-completion; third-party drift rule applies).

**Files:**
- Modify: `mac/Package.swift`
- Create: `mac/Sources/IntelligenceSelftest/main.swift`
- Commit (new): `mac/Package.resolved` (pins the resolved MLX revision — it is currently untracked and not gitignored)

- [ ] **Step 1: Add the dependency + executable target to `mac/Package.swift`**

In `dependencies:`, after the WhisperKit line:

```swift
        // On-device LLM (Sidekit Intelligence, spec 2026-06-12). Pinned by the committed
        // Package.resolved; MLXLLM/MLXLMCommon run the shared Qwen model.
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", branch: "main"),
```

In `targets:`, add to `SidekitApp`'s `dependencies` array (after the WhisperKit product):

```swift
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
```

And append a new executable target at the end of `targets:`:

```swift
        // Dev tool + Brick-0 gate: headlessly verify the on-device LLM downloads, loads, and
        // generates (spec 2026-06-12 §7). Usage: swift run -c release IntelligenceSelftest
        .executableTarget(
            name: "IntelligenceSelftest",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ]
        ),
```

- [ ] **Step 2: Resolve and build (this pins the revision)**

```bash
cd /Users/omkareshwartripathi/SpeakType/mac
swift package resolve && swift build
```

Expected: resolves mlx-swift-examples (+ transitive mlx-swift, swift-transformers) and builds clean. **If the build errors that `Hub` (used in Step 3) is not a declared product**, add `.package(url: "https://github.com/huggingface/swift-transformers", from: "<the version Package.resolved already picked>")` and `.product(name: "Transformers", package: "swift-transformers")` to the two targets that import it — match the resolved version exactly so nothing re-resolves.

- [ ] **Step 3: Write `mac/Sources/IntelligenceSelftest/main.swift`**

```swift
import Foundation
import Hub
import MLX
import MLXLMCommon
import MLXLLM

// Brick-0 gate + permanent headless verifier for the on-device LLMs (spec 2026-06-12 §7).
// Two-model variant (Gate A outcome): Gemma-2-2B polishes (its chat template has NO system
// role — fold the system prompt into the user turn), Qwen3-1.7B drafts (thinking off).
// Downloads on first run into the app's own Intelligence folder, then per model:
// load → canned generation → unload, printing timings. Exits non-zero on any failure.
// Budgets (spec §5): warm-disk load ≤ 5 s; each generation ≤ 8 s.
// Task 5 rewires this to drive the real MLXTextEngine adapter + IntelligencePrompt.

let polishRepo = "mlx-community/gemma-2-2b-it-4bit"
let draftRepo = "mlx-community/Qwen3-1.7B-4bit"
let root = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Sidekit/Intelligence", isDirectory: true)

// Short canned prompts for the gate only — Task 3's IntelligencePrompt replaces these in Task 5.
let polishSystem = """
You clean raw speech-to-text transcripts. Remove fillers (um, uh, like) and the abandoned \
half of self-corrections; fix casing and punctuation; keep every other word. \
Output only the cleaned transcript.
"""
let draftSystem = """
You write text from the user's rough notes. Keep every fact, name, number, and date exactly \
as given; invent nothing. Output only the requested text — no preamble, no quotes.
Write an email from these notes. Subject line first, then the body.
"""

func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}

let clock = ContinuousClock()

func snapshot(_ repoID: String, hub: HubApi) async throws -> URL {
    print("snapshot \(repoID)")
    var lastPercent = -1
    return try await hub.snapshot(
        from: Hub.Repo(id: repoID),
        matching: ["*.safetensors", "*.json", "*.txt", "*.model"]) { progress in
        let percent = Int(progress.fractionCompleted * 100)
        if percent / 10 != lastPercent / 10 { print("  download \(percent)%"); lastPercent = percent }
    }
}

/// Load → generate once → free — the RAM-guest rule holds even in the gate.
func runOnce(dir: URL, chat: [Chat.Message], temperature: Float, label: String) async throws -> String {
    let loadStart = clock.now
    let container = try await LLMModelFactory.shared.loadContainer(
        configuration: ModelConfiguration(directory: dir))
    print("\(label) load: \(loadStart.duration(to: clock.now))")
    let genStart = clock.now
    let out: String = try await container.perform { context in
        let input = try await context.processor.prepare(
            input: UserInput(chat: chat, additionalContext: ["enable_thinking": false]))
        var text = ""
        let stream = try MLXLMCommon.generate(
            input: input,
            parameters: GenerateParameters(maxTokens: 1024, temperature: temperature),
            context: context)
        for await item in stream {
            if case .chunk(let chunk) = item { text += chunk }
        }
        return text
    }
    print("\(label) gen (\(genStart.duration(to: clock.now))):\n\(out)\n")
    MLX.GPU.clearCache()
    return out
}

do {
    let hub = HubApi(downloadBase: root)
    let gemmaDir = try await snapshot(polishRepo, hub: hub)
    let qwenDir = try await snapshot(draftRepo, hub: hub)

    var diskBytes = 0
    if let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
        for case let url as URL in files {
            diskBytes += (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
    }
    print(String(format: "disk: %.2f GB total", Double(diskBytes) / 1_073_741_824))

    // Polish on Gemma — NO system role: the system prompt rides the user turn.
    let polished = try await runOnce(
        dir: gemmaDir,
        chat: [.user(polishSystem + "\n\n" +
                     "um so basically i think we should uh ship it on tuesday actually no wednesday")],
        temperature: 0.2, label: "polish/gemma")
    if polished.isEmpty { fail("polish returned empty") }
    if !polished.localizedCaseInsensitiveContains("wednesday") { fail("polish lost the correction") }

    // Draft on Qwen — native system role, thinking off.
    let drafted = try await runOnce(
        dir: qwenDir,
        chat: [.system(draftSystem),
               .user("tell priya the invoice for 4500 dollars went out, ask her to cc me going forward")],
        temperature: 0.7, label: "draft/qwen")
    if drafted.isEmpty { fail("draft returned empty") }
    if drafted.contains("<think>") { fail("thinking mode leaked into draft output") }
    if !drafted.contains("4500") { fail("draft dropped the exact amount") }

    print("gpu memory: \(GPU.snapshot())")
    print("PASS")
} catch {
    fail("\(error)")
}
```

- [ ] **Step 4: Run the gate**

```bash
cd /Users/omkareshwartripathi/SpeakType/mac
swift run -c release IntelligenceSelftest
```

Expected: first run downloads both models (~2.5–3 GB total, one time), then per model `load: …` + a generation, and `PASS`, exit 0. **Record from the output: total disk GB, each model's load seconds and generation seconds** — Task 6 bakes the disk size into the download-button string, and BRICKS.md gets the timings.

**Budget check (spec §5):** re-run once (warm disk). Per model: warm load ≤ 5 s, generation ≤ 8 s. Any budget missed by >2× → STOP, report BLOCKED with the numbers (spec says revisit with the user). **If Qwen3.5's architecture fails to load** (unsupported-architecture error) → STOP, report BLOCKED: spec §7 swaps the DRAFT repo to `mlx-community/Qwen2.5-1.5B-Instruct-4bit` — a decision the controller takes back to the user. Gemma-2 failing to load is unexpected (mature architecture) — if it does, STOP and report BLOCKED.

- [ ] **Step 5: Confirm the suite still passes, then commit**

```bash
swift test 2>&1 | tail -3   # expect 152/152
cd /Users/omkareshwartripathi/SpeakType
git add mac/Package.swift mac/Package.resolved mac/Sources/IntelligenceSelftest/
git commit -m "feat(mac): Gate B — MLX Swift deps + IntelligenceSelftest proves Qwen3.5-2B loads & generates"
```

**OUTCOME (2026-06-12): PASSED, with the draft model swapped under the §7 fallback rule.** Shipped as `e69d05e` + review nits `1848a11`. Qwen3.5-2B-OptiQ failed Swift load (VLM architecture); the implementer substituted **Qwen3-1.7B-4bit**, which the controller then lab-validated: **22/29 assistant, guardrail 2/2** (≥ the 20/29 bar) — adopted, recorded in spec §1/§7. Warm numbers: Gemma load 1.19 s / gen 0.48 s; Qwen3-1.7B load 0.75 s / gen 0.64 s. Library reality: MLXLLM lives in `mlx-swift-lm` 3.31.3 (pinned via committed Package.resolved); WhisperKit bumped to 1.0.0 (drops its swift-transformers, resolving the conflict — dictation needs a sanity check at Task 7 UAT). **`mlx.metallib` must sit beside any binary that loads a model** (no SwiftPM Metal pipeline) — Task 7 must make build-app.sh place it in the .app, and Task 5's selftest re-run needs it re-placed after a clean release build. Before Task 5's disk measurement, delete the stale `models--mlx-community--Qwen3.5-2B-OptiQ-4bit` snapshot from `~/Library/Application Support/Sidekit/Intelligence/` so the printed size reflects the two shipping models.

---

## Task 3 — Core: `IntelligencePrompt` (TDD)

Pure prompt construction: chips, tones, the two Polish paths, sanitation, input cap. Exact strings from spec §4.

**Skill:** none (superpowers:test-driven-development; run with `swift test`).

**Files:**
- Create: `mac/Sources/SidekitCore/IntelligencePrompt.swift`
- Test: `mac/Tests/SidekitCoreTests/IntelligencePromptTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import SidekitCore

struct IntelligencePromptTests {
    // MARK: chips & tones

    @Test func chipAndToneLabels() {
        #expect(IntelligenceChip.allCases.map(\.label) ==
                ["Draft email", "Draft message", "Polish", "Summarize"])
        #expect(IntelligenceTone.allCases.map(\.label) ==
                ["Keep tone", "Professional", "Friendly", "Concise"])
    }

    @Test func chipRolesSplitPolishFromDrafting() {
        #expect(IntelligenceChip.polish.role == .polish)
        for chip in [IntelligenceChip.draftEmail, .draftMessage, .summarize] {
            #expect(chip.role == .draft)
        }
    }

    // MARK: polish paths

    /// The faithful polish prompt is the lab-tuned p7 verbatim (spec §4) — guard it against
    /// hand-trimming. If the disposable lab/ folder is ever deleted, delete this one test
    /// (the constant stays; it IS the product copy).
    @Test func polishKeepToneIsLabP7Verbatim() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)              // …/mac/Tests/SidekitCoreTests/x.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent() // → repo root
        let labFile = repoRoot.appendingPathComponent("lab/whisper-compare/prompts/p7_faithful.txt")
        let lab = try String(contentsOf: labFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let built = IntelligencePrompt.build(chip: .polish, tone: .keepTone)
        #expect(built.system == lab)
    }

    @Test func polishWithToneUsesRewritePromptNotP7() {
        let built = IntelligencePrompt.build(chip: .polish, tone: .professional)
        #expect(built.system == "Rewrite the text in a professional, courteous tone. Keep every fact, name, number, date, and the meaning unchanged. Output only the rewritten text.")
        #expect(!built.system.contains("GOLDEN RULE"))
    }

    @Test func polishConciseRewrite() {
        let built = IntelligencePrompt.build(chip: .polish, tone: .concise)
        #expect(built.system == "Rewrite the text to be as brief as possible. Keep every fact, name, number, date, and the meaning unchanged. Output only the rewritten text.")
    }

    // MARK: drafting chips

    @Test func draftEmailProfessionalExactComposition() {
        let built = IntelligencePrompt.build(chip: .draftEmail, tone: .professional)
        #expect(built.system == """
        You write text from the user's rough notes. Keep every fact, name, number, and date \
        exactly as given; invent nothing. If a result needs computed math, show the formula \
        and tell the user to verify — never state a guessed number. Output only the requested \
        text — no preamble, no quotes.
        Write an email from these notes. Subject line first, then the body.
        Tone: professional and courteous.
        """)
    }

    @Test func keepToneAppendsNoToneLine() {
        for chip in [IntelligenceChip.draftEmail, .draftMessage, .summarize] {
            #expect(!IntelligencePrompt.build(chip: chip, tone: .keepTone).system.contains("Tone:"))
        }
    }

    @Test func allDraftChipsCarryTheArithmeticGuardrail() {
        for chip in [IntelligenceChip.draftEmail, .draftMessage, .summarize] {
            #expect(IntelligencePrompt.build(chip: chip, tone: .friendly).system
                .contains("never state a guessed number"))
        }
    }

    @Test func temperaturesPerSpec() {
        #expect(IntelligencePrompt.build(chip: .polish, tone: .keepTone).temperature == 0.2)
        #expect(IntelligencePrompt.build(chip: .polish, tone: .friendly).temperature == 0.2)
        #expect(IntelligencePrompt.build(chip: .draftEmail, tone: .keepTone).temperature == 0.7)
        #expect(IntelligencePrompt.build(chip: .summarize, tone: .concise).temperature == 0.7)
    }

    // MARK: input check

    @Test func inputCheckTrimsAndRejectsEmpty() {
        #expect(IntelligencePrompt.check("  hi  ") == .ok("hi"))
        #expect(IntelligencePrompt.check("   \n ") == .empty)
        #expect(IntelligencePrompt.check("") == .empty)
    }

    @Test func inputCheckEnforcesTheCapWithoutTruncating() {
        let atCap = String(repeating: "a", count: 6000)
        #expect(IntelligencePrompt.check(atCap) == .ok(atCap))
        #expect(IntelligencePrompt.check(atCap + "a") == .tooLong)
    }

    // MARK: sanitation

    @Test func sanitizeStripsThinkBlocksFencesQuotesAndWhitespace() {
        #expect(IntelligencePrompt.sanitize("<think>hmm</think>\nHello.") == "Hello.")
        #expect(IntelligencePrompt.sanitize("```\nHello.\n```") == "Hello.")
        #expect(IntelligencePrompt.sanitize("```text\nHello.\n```") == "Hello.")
        #expect(IntelligencePrompt.sanitize("\"Hello.\"") == "Hello.")
        #expect(IntelligencePrompt.sanitize("  Hello.  \n") == "Hello.")
    }

    @Test func sanitizeLeavesInteriorQuotesAndFencesAlone() {
        #expect(IntelligencePrompt.sanitize("She said \"hi\" twice.") == "She said \"hi\" twice.")
        #expect(IntelligencePrompt.sanitize("Run ```ls``` now.") == "Run ```ls``` now.")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd /Users/omkareshwartripathi/SpeakType/mac
swift test --filter IntelligencePromptTests 2>&1 | tail -5
```

Expected: FAIL — `IntelligenceChip` etc. don't exist (compile error counts as the failing state).

- [ ] **Step 3: Implement `mac/Sources/SidekitCore/IntelligencePrompt.swift`**

```swift
import Foundation

/// The scratchpad's preset actions (spec 2026-06-12 §3). Chips grow one at a time, each
/// lab-tested first — no free-form instructions in v1.
public enum IntelligenceChip: CaseIterable, Sendable {
    case draftEmail, draftMessage, polish, summarize

    public var label: String {
        switch self {
        case .draftEmail: return "Draft email"
        case .draftMessage: return "Draft message"
        case .polish: return "Polish"
        case .summarize: return "Summarize"
        }
    }

    /// Which model serves this chip (spec §1 two-model split): Polish runs on Gemma-2-2B,
    /// every drafting chip on Qwen3.5-2B.
    public var role: IntelligenceRole {
        self == .polish ? .polish : .draft
    }
}

/// The two engine roles of the two-model split (spec §1/§5). One is warm at a time.
public enum IntelligenceRole: Sendable, Equatable {
    case polish, draft
}

/// The global tone picker (spec §3). Applies to whatever chip runs; default Keep tone.
public enum IntelligenceTone: String, CaseIterable, Sendable {
    case keepTone, professional, friendly, concise

    public var label: String {
        switch self {
        case .keepTone: return "Keep tone"
        case .professional: return "Professional"
        case .friendly: return "Friendly"
        case .concise: return "Concise"
        }
    }
}

/// Prompt construction + I/O hygiene for the on-device model (spec §4). Pure functions of
/// (chip, tone) so every string ships exactly as reviewed. Token-lean by user rule; the one
/// exception is `polishFaithful` — the lab-tuned p7 prompt, copied verbatim, never hand-trimmed.
public enum IntelligencePrompt {
    public static let inputCap = 6000
    public static let tooLongMessage =
        "Text is too long for the on-device model — trim it below 6,000 characters."

    public enum InputVerdict: Equatable, Sendable {
        case ok(String)
        case empty
        case tooLong
    }

    /// Whitespace-trim, then gate: empty does nothing, over-cap is refused outright —
    /// never silently truncated (spec §4).
    public static func check(_ text: String) -> InputVerdict {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > inputCap { return .tooLong }
        return .ok(trimmed)
    }

    /// (system prompt, sampling temperature) per spec §4: 0.2 for Polish (both paths),
    /// 0.7 for the drafting chips.
    public static func build(chip: IntelligenceChip, tone: IntelligenceTone)
        -> (system: String, temperature: Float) {
        switch chip {
        case .polish:
            switch tone {
            case .keepTone:
                return (polishFaithful, 0.2)
            case .professional:
                return ("Rewrite the text in a professional, courteous tone. Keep every fact, name, number, date, and the meaning unchanged. Output only the rewritten text.", 0.2)
            case .friendly:
                return ("Rewrite the text in a warm, friendly tone. Keep every fact, name, number, date, and the meaning unchanged. Output only the rewritten text.", 0.2)
            case .concise:
                return ("Rewrite the text to be as brief as possible. Keep every fact, name, number, date, and the meaning unchanged. Output only the rewritten text.", 0.2)
            }
        case .draftEmail, .draftMessage, .summarize:
            var system = draftShared + "\n" + taskLine(chip)
            if let tone = toneLine(tone) { system += "\n" + tone }
            return (system, 0.7)
        }
    }

    /// Trim; strip a think-block, one wrapping fence pair, one wrapping quote pair — the
    /// ways a small model wraps output. Interior quotes/fences are content and stay.
    public static func sanitize(_ raw: String) -> String {
        var text = raw
        // Defensive: thinking is disabled at the template level, but strip any leak.
        while let open = text.range(of: "<think>"),
              let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6 {
            text = String(text.dropFirst(3).dropLast(3))
            if let newline = text.firstIndex(of: "\n"),
               !text[text.startIndex..<newline].contains(" ") {
                text = String(text[text.index(after: newline)...]) // drop a ```lang tag line
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count > 1,
           !text.dropFirst().dropLast().contains("\"") {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Strings (spec §4, exact)

    private static let draftShared = """
    You write text from the user's rough notes. Keep every fact, name, number, and date \
    exactly as given; invent nothing. If a result needs computed math, show the formula \
    and tell the user to verify — never state a guessed number. Output only the requested \
    text — no preamble, no quotes.
    """

    private static func taskLine(_ chip: IntelligenceChip) -> String {
        switch chip {
        case .draftEmail: return "Write an email from these notes. Subject line first, then the body."
        case .draftMessage: return "Write a short chat message (Slack/text) from these notes."
        case .summarize: return "Summarize these notes in 2–3 sentences, or up to 5 bullets if they list items."
        case .polish: return "" // polish never reaches here
        }
    }

    private static func toneLine(_ tone: IntelligenceTone) -> String? {
        switch tone {
        case .keepTone: return nil
        case .professional: return "Tone: professional and courteous."
        case .friendly: return "Tone: warm and friendly."
        case .concise: return "Tone: as brief as possible while keeping all facts."
        }
    }

    /// The lab-tuned faithful cleanup prompt — `lab/whisper-compare/prompts/p7_faithful.txt`
    /// VERBATIM (a unit test enforces byte equality with the lab file). Never hand-edit;
    /// re-tune in the lab, then re-copy.
    static let polishFaithful = #"""
    <PASTE THE FULL CONTENTS OF lab/whisper-compare/prompts/p7_faithful.txt HERE, VERBATIM,
    WITH NO TRAILING NEWLINE — generate the paste with:
      sed -e 's/\\/\\\\/g' lab/whisper-compare/prompts/p7_faithful.txt
    (it contains no backslashes or triple quotes today, so a direct copy is safe; the
    polishKeepToneIsLabP7Verbatim test is the authority — make it pass byte-for-byte)>
    """#
}
```

**Note on the one allowed fill-in:** the `polishFaithful` body is the only content this plan does not inline — it is ~60 lines that must match `lab/whisper-compare/prompts/p7_faithful.txt` *byte-for-byte*, and the test in Step 1 is the enforcing authority. Copy the file contents directly between the `#"""` delimiters.

- [ ] **Step 4: Run the tests until green**

```bash
swift test --filter IntelligencePromptTests 2>&1 | tail -5
```

Expected: 13/13 PASS. Then the whole suite: `swift test 2>&1 | tail -3` → 165/165.

- [ ] **Step 5: Commit**

```bash
cd /Users/omkareshwartripathi/SpeakType
git add mac/Sources/SidekitCore/IntelligencePrompt.swift mac/Tests/SidekitCoreTests/IntelligencePromptTests.swift
git commit -m "feat(mac): IntelligencePrompt — chips, tones, two polish paths, sanitation, input cap (TDD)"
```

---

## Task 4 — Core: ports + `IntelligenceSession` state machine (TDD)

The RAM-guest lifecycle (spec §5) as a pure, fake-tested state machine.

**Skill:** none (superpowers:test-driven-development).

**Files:**
- Create: `mac/Sources/SidekitCore/IntelligencePorts.swift`
- Create: `mac/Sources/SidekitCore/IntelligenceSession.swift`
- Test: `mac/Tests/SidekitCoreTests/IntelligenceSessionTests.swift`

- [ ] **Step 1: Write `mac/Sources/SidekitCore/IntelligencePorts.swift`** (ports first — the tests need the protocols to fake)

```swift
import Foundation

/// Generates text with the on-device model. `load()` is idempotent; `unload()` frees the
/// weights (the RAM-guest rule, spec §5). Generation honors task cancellation.
public protocol TextGenerating: Sendable {
    func load() async throws
    func unload() async
    func generate(system: String, user: String, temperature: Float) async throws -> String
}

/// Owns the model files on disk (download / presence / removal — spec §6). Detached from
/// loading so download consent, progress, and Settings-removal stay explicit.
public protocol ModelProvisioning: Sendable {
    var isDownloaded: Bool { get }
    func download(progress: @escaping @Sendable (Double) -> Void) async throws
    func remove() throws
}

/// One-shot idle timer for the unload window. `start` replaces any pending timer.
public protocol IntelligenceIdleTimer: AnyObject {
    func start(after seconds: Double, _ fire: @escaping @Sendable () -> Void)
    func cancel()
}
```

- [ ] **Step 2: Write the failing tests**

```swift
import Foundation
import Testing
@testable import SidekitCore

// MARK: - Fakes

private final class FakeEngine: TextGenerating, @unchecked Sendable {
    var loads = 0, unloads = 0
    var generated: [(system: String, user: String, temperature: Float)] = []
    var loadError: Error?
    var reply = "REPLY"
    var generateError: Error?

    func load() async throws { loads += 1; if let loadError { throw loadError } }
    func unload() async { unloads += 1 }
    func generate(system: String, user: String, temperature: Float) async throws -> String {
        generated.append((system, user, temperature))
        if let generateError { throw generateError }
        try Task.checkCancellation()
        return reply
    }
}

private final class FakeProvisioner: ModelProvisioning, @unchecked Sendable {
    var isDownloaded: Bool
    var downloadError: Error?
    var progressTicks: [Double] = [0.5]
    init(downloaded: Bool) { isDownloaded = downloaded }
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        for tick in progressTicks {
            progress(tick)
            await Task.yield() // let the session's main-actor progress hop land before we finish
        }
        if let downloadError { throw downloadError }
        isDownloaded = true
    }
    func remove() throws { isDownloaded = false }
}

private final class FakeIdleTimer: IntelligenceIdleTimer {
    var pending: (() -> Void)?
    var cancels = 0
    func start(after seconds: Double, _ fire: @escaping @Sendable () -> Void) { pending = fire }
    func cancel() { cancels += 1; pending = nil }
    func fire() { pending?(); pending = nil }
}

private struct TestError: Error {}

// MARK: - Tests

@MainActor
struct IntelligenceSessionTests {
    final class Recorder {
        var states: [IntelligenceSession.State] = []
        var results: [String] = []
        var errors: [String] = []
    }

    private struct Rig {
        let session: IntelligenceSession
        let polish: FakeEngine
        let draft: FakeEngine
        let provisioner: FakeProvisioner
        let idle: FakeIdleTimer
        let rec: Recorder
    }

    private func make(downloaded: Bool = true) -> Rig {
        let polish = FakeEngine()
        let draft = FakeEngine()
        let provisioner = FakeProvisioner(downloaded: downloaded)
        let idle = FakeIdleTimer()
        let session = IntelligenceSession(polishEngine: polish, draftEngine: draft,
                                          provisioner: provisioner, idle: idle)
        let rec = Recorder()
        session.onStateChanged = { rec.states.append($0) }
        session.onResult = { rec.results.append($0) }
        session.onError = { rec.errors.append($0) }
        return Rig(session: session, polish: polish, draft: draft,
                   provisioner: provisioner, idle: idle, rec: rec)
    }

    @Test func initialStateReflectsDownload() {
        #expect(make(downloaded: true).session.state == .ready)
        #expect(make(downloaded: false).session.state == .needsModel)
    }

    @Test func downloadHappyPathReportsProgressThenReady() async {
        let rig = make(downloaded: false)
        await rig.session.requestDownload()?.value
        #expect(rig.rec.states.contains(.downloading(0.0)))
        #expect(rig.rec.states.contains(.downloading(0.5)))
        #expect(rig.session.state == .ready)
    }

    @Test func downloadFailureStaysNeedsModelWithError() async {
        let rig = make(downloaded: false)
        rig.provisioner.downloadError = TestError()
        await rig.session.requestDownload()?.value
        #expect(rig.session.state == .needsModel)
        #expect(rig.rec.errors == ["Download interrupted — Retry"])
    }

    @Test func downloadOfflineShowsTheOfflineMessage() async {
        let rig = make(downloaded: false)
        rig.provisioner.downloadError = URLError(.notConnectedToInternet)
        await rig.session.requestDownload()?.value
        #expect(rig.session.state == .needsModel)
        #expect(rig.rec.errors == ["You're offline — the one-time model download needs internet."])
    }

    @Test func draftChipRunsOnTheDraftEngineOnly() async {
        let rig = make()
        rig.draft.reply = "```\nHello.\n```"
        await rig.session.run(chip: .draftEmail, tone: .professional, input: " notes ")?.value
        #expect(rig.draft.loads == 1)
        #expect(rig.polish.loads == 0 && rig.polish.generated.isEmpty)
        #expect(rig.draft.generated.count == 1)
        #expect(rig.draft.generated[0].user == "notes") // trimmed by the input check
        #expect(rig.draft.generated[0].temperature == 0.7)
        #expect(rig.draft.generated[0].system ==
                IntelligencePrompt.build(chip: .draftEmail, tone: .professional).system)
        #expect(rig.rec.results == ["Hello."]) // sanitized
        #expect(rig.session.state == .warm)
        #expect(rig.rec.states.contains(.loading) && rig.rec.states.contains(.generating))
    }

    @Test func polishChipRunsOnThePolishEngineOnly() async {
        let rig = make()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        #expect(rig.polish.loads == 1 && rig.polish.generated.count == 1)
        #expect(rig.draft.loads == 0 && rig.draft.generated.isEmpty)
        #expect(rig.polish.generated[0].temperature == 0.2)
    }

    @Test func sameRoleTwiceSkipsReloadAndResetsIdleTimer() async {
        let rig = make()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        await rig.session.run(chip: .polish, tone: .friendly, input: "y")?.value
        #expect(rig.polish.loads == 1)
        #expect(rig.idle.cancels >= 1)      // a new run cancels the pending unload
        #expect(rig.idle.pending != nil)    // …and re-arms it after finishing
    }

    @Test func roleSwitchUnloadsTheWarmModelFirst() async {
        let rig = make()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        await rig.session.run(chip: .draftEmail, tone: .keepTone, input: "y")?.value
        #expect(rig.polish.unloads == 1)    // Gemma left before Qwen arrived
        #expect(rig.draft.loads == 1)
        #expect(rig.session.state == .warm)
    }

    @Test func emptyInputDoesNothingAndTooLongErrorsWithoutEngineCalls() async {
        let rig = make()
        await rig.session.run(chip: .summarize, tone: .keepTone, input: "   ")?.value
        #expect(rig.draft.generated.isEmpty && rig.rec.errors.isEmpty)
        await rig.session.run(chip: .summarize, tone: .keepTone,
                              input: String(repeating: "a", count: 6001))?.value
        #expect(rig.draft.generated.isEmpty)
        #expect(rig.rec.errors == [IntelligencePrompt.tooLongMessage])
        #expect(rig.session.state == .ready)
    }

    @Test func emptySanitizedOutputIsAnHonestError() async {
        let rig = make()
        rig.draft.reply = "  \n "
        await rig.session.run(chip: .draftMessage, tone: .keepTone, input: "x")?.value
        #expect(rig.rec.errors == ["Couldn't draft that — try again."])
        #expect(rig.rec.results.isEmpty)
        #expect(rig.session.state == .warm) // model stays warm; the input is preserved UI-side
    }

    @Test func loadFailureReturnsToReadyWithDamageMessage() async {
        let rig = make()
        rig.polish.loadError = TestError()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        #expect(rig.session.state == .ready)
        #expect(rig.rec.errors == ["Model files look damaged — download again."])
    }

    @Test func generationFailureStaysWarmWithRetryMessage() async {
        let rig = make()
        rig.polish.generateError = TestError()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        #expect(rig.session.state == .warm)
        #expect(rig.rec.errors == ["Couldn't draft that — try again."])
    }

    @Test func idleTimerFireUnloadsBackToReady() async {
        let rig = make()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        rig.idle.fire()
        await rig.session.settle()
        #expect(rig.polish.unloads == 1)
        #expect(rig.session.state == .ready)
    }

    @Test func cancelDuringGenerationReturnsWarmSilently() async {
        let rig = make()
        rig.polish.generateError = CancellationError()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        #expect(rig.session.state == .warm)
        #expect(rig.rec.errors.isEmpty && rig.rec.results.isEmpty)
    }

    @Test func memoryPressureWhenWarmUnloadsImmediately() async {
        let rig = make()
        await rig.session.run(chip: .draftEmail, tone: .keepTone, input: "x")?.value
        rig.session.memoryPressure()
        await rig.session.settle()
        #expect(rig.draft.unloads == 1)
        #expect(rig.session.state == .ready)
    }

    @Test func modelRemovedDropsToNeedsModel() async {
        let rig = make()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        try? rig.provisioner.remove()
        rig.session.modelRemoved()
        await rig.session.settle()
        #expect(rig.polish.unloads == 1)
        #expect(rig.session.state == .needsModel)
    }
}
```

- [ ] **Step 3: Run to verify they fail**

```bash
swift test --filter IntelligenceSessionTests 2>&1 | tail -5
```

Expected: compile failure (`IntelligenceSession` doesn't exist).

- [ ] **Step 4: Implement `mac/Sources/SidekitCore/IntelligenceSession.swift`**

```swift
import Foundation

/// The RAM-guest state machine (spec 2026-06-12 §5): a model loads on demand, stays warm
/// for an idle window, then unloads — never resident. Two role-specific engines (spec §1:
/// Gemma polishes, Qwen drafts) but only ONE is ever warm — switching roles unloads the
/// other first. Pure over the ports; the UI mirrors `state` + the result/error callbacks.
/// @MainActor like the app models it feeds; engine work runs off-main behind the async port.
@MainActor
public final class IntelligenceSession {
    public enum State: Equatable, Sendable {
        case needsModel
        case downloading(Double)
        case ready       // downloaded, no weights in RAM
        case loading
        case warm        // one model's weights in RAM, idle
        case generating
    }

    public private(set) var state: State {
        didSet { if state != oldValue { onStateChanged?(state) } }
    }
    public var onStateChanged: ((State) -> Void)?
    public var onResult: ((String) -> Void)?
    public var onError: ((String) -> Void)?

    private let polishEngine: any TextGenerating
    private let draftEngine: any TextGenerating
    private let provisioner: any ModelProvisioning
    private let idle: any IntelligenceIdleTimer
    private let idleSeconds: Double
    /// Which engine is warm; nil ↔ state ready/needsModel.
    private var warmRole: IntelligenceRole?
    private var generationTask: Task<Void, Never>?
    private var housekeepingTask: Task<Void, Never>?

    public init(polishEngine: any TextGenerating,
                draftEngine: any TextGenerating,
                provisioner: any ModelProvisioning,
                idle: any IntelligenceIdleTimer,
                idleSeconds: Double = 180) {
        self.polishEngine = polishEngine
        self.draftEngine = draftEngine
        self.provisioner = provisioner
        self.idle = idle
        self.idleSeconds = idleSeconds
        self.state = provisioner.isDownloaded ? .ready : .needsModel
    }

    private func engine(for role: IntelligenceRole) -> any TextGenerating {
        role == .polish ? polishEngine : draftEngine
    }

    /// One-time download of BOTH models (spec §6). Returns the task so callers/tests can await it.
    @discardableResult
    public func requestDownload() -> Task<Void, Never>? {
        guard state == .needsModel else { return nil }
        state = .downloading(0.0)
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.provisioner.download { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(fraction)
                    }
                }
                self.state = .ready
            } catch {
                self.state = .needsModel
                // Spec §6 distinguishes plain offline from an interrupted/failed download.
                let offline = (error as? URLError)?.code == .notConnectedToInternet
                self.onError?(offline
                    ? "You're offline — the one-time model download needs internet."
                    : "Download interrupted — Retry")
            }
        }
        generationTask = task
        return task
    }

    /// Run one chip (spec §3/§5): validate → swap/load the chip's model if needed →
    /// generate → sanitize → deliver. Returns the task so callers/tests can await it.
    @discardableResult
    public func run(chip: IntelligenceChip, tone: IntelligenceTone, input: String) -> Task<Void, Never>? {
        guard state == .ready || state == .warm else { return nil }
        let text: String
        switch IntelligencePrompt.check(input) {
        case .empty: return nil
        case .tooLong: onError?(IntelligencePrompt.tooLongMessage); return nil
        case .ok(let trimmed): text = trimmed
        }
        idle.cancel()
        let role = chip.role
        let prompt = IntelligencePrompt.build(chip: chip, tone: tone)
        let task = Task { [weak self] in
            guard let self else { return }
            if let warm = self.warmRole, warm != role {
                // Role switch: the warm model leaves before the other arrives (spec §5).
                self.state = .loading
                self.warmRole = nil
                await self.engine(for: warm).unload()
            }
            if self.warmRole == nil {
                self.state = .loading
                do {
                    try await self.engine(for: role).load()
                    self.warmRole = role
                } catch {
                    self.state = .ready
                    self.onError?("Model files look damaged — download again.")
                    return
                }
            }
            self.state = .generating
            do {
                let raw = try await self.engine(for: role).generate(
                    system: prompt.system, user: text, temperature: prompt.temperature)
                let clean = IntelligencePrompt.sanitize(raw)
                self.state = .warm
                if clean.isEmpty { self.onError?("Couldn't draft that — try again.") }
                else { self.onResult?(clean) }
            } catch is CancellationError {
                // The user (or memory pressure) asked to stop. If pressure already evicted
                // the model, keep the state it set; otherwise stay warm, silently.
                if self.warmRole != nil { self.state = .warm }
            } catch {
                self.state = .warm
                self.onError?("Couldn't draft that — try again.")
            }
            if self.warmRole != nil { self.scheduleIdleUnload() }
        }
        generationTask = task
        return task
    }

    /// Stop the in-flight generation; the warm model stays warm (spec §5).
    public func cancelGeneration() { generationTask?.cancel() }

    /// System memory pressure: the guest leaves immediately (spec §5).
    public func memoryPressure() {
        switch state {
        case .warm:
            unloadNow(to: .ready)
        case .generating:
            generationTask?.cancel()
            onError?("Paused to free memory — try again in a moment.")
            unloadNow(to: .ready)
        default: break
        }
    }

    /// Settings removed the model files (spec §6).
    public func modelRemoved() {
        idle.cancel()
        unloadNow(to: .needsModel)
    }

    /// Await all in-flight internal work — for tests.
    public func settle() async {
        await generationTask?.value
        await housekeepingTask?.value
    }

    private func scheduleIdleUnload() {
        idle.start(after: idleSeconds) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.state == .warm else { return }
                self.unloadNow(to: .ready)
            }
        }
    }

    private func unloadNow(to target: State) {
        let warm = warmRole
        warmRole = nil
        state = target
        housekeepingTask = Task { [polishEngine, draftEngine] in
            switch warm {
            case .polish: await polishEngine.unload()
            case .draft: await draftEngine.unload()
            case nil:    // belt & braces (e.g. modelRemoved while nothing is warm)
                await polishEngine.unload()
                await draftEngine.unload()
            }
        }
    }
}
```

- [ ] **Step 5: Run until green, then the whole suite**

```bash
swift test --filter IntelligenceSessionTests 2>&1 | tail -5   # 16/16 PASS
swift test 2>&1 | tail -3                                      # 181/181
```

(One ordering nuance the tests pin down: `modelRemoved`/`memoryPressure` set the state *before* the async unload completes — `settle()` exists so tests await the unload side-effect.)

- [ ] **Step 6: Commit**

```bash
cd /Users/omkareshwartripathi/SpeakType
git add mac/Sources/SidekitCore/IntelligencePorts.swift mac/Sources/SidekitCore/IntelligenceSession.swift mac/Tests/SidekitCoreTests/IntelligenceSessionTests.swift
git commit -m "feat(mac): IntelligenceSession — RAM-guest state machine over engine/provisioner/idle ports (TDD)"
```

---

## Task 5 — Adapters: `MLXTextEngine`, `ModelDownloader`, timers + selftest rewire

The real implementations, then point `IntelligenceSelftest` at them so the gate exercises shipping code forever after. The engine + downloader live in a **new small library target `SidekitIntelligence`** (the `SidekitNet` precedent: split out exactly so the selftest can verify the shipping adapters headlessly — the `SidekitApp` executable target can't be imported). They are AppKit-free; `Diag`/`AppPaths` stay out of them (a `log` closure and a `root` URL are injected by the app instead).

**Skill:** none (verification-before-completion; third-party drift rule applies to MLX/Hub calls).

**Files:**
- Modify: `mac/Package.swift` (new `SidekitIntelligence` target; retarget `IntelligenceSelftest`)
- Create: `mac/Sources/SidekitIntelligence/MLXTextEngine.swift`
- Create: `mac/Sources/SidekitIntelligence/ModelDownloader.swift`
- Create: `mac/Sources/SidekitApp/Adapters/IntelligenceSystemAdapters.swift`
- Modify: `mac/Sources/IntelligenceSelftest/main.swift` (drive the real adapters + real prompts)

- [ ] **Step 1: `mac/Package.swift` — the `SidekitIntelligence` target**

After the `SidekitNet` target, add:

```swift
        // The on-device LLM engine + model files, split out (like SidekitNet) so
        // IntelligenceSelftest can verify the exact shipping adapters headlessly.
        .target(
            name: "SidekitIntelligence",
            dependencies: [
                "SidekitCore",
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ]
        ),
```

In `SidekitApp`'s dependencies, replace the two MLX product lines (added in Task 2) with `"SidekitIntelligence"` (the products come transitively). Replace the `IntelligenceSelftest` target's dependencies with `["SidekitCore", "SidekitIntelligence"]`.

- [ ] **Step 2: Write `mac/Sources/SidekitIntelligence/MLXTextEngine.swift`**

```swift
import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import SidekitCore

public enum IntelligenceEngineError: Error { case notLoaded }

/// MLXLLM-backed `TextGenerating` (spec §5/§8). An actor: one model in RAM, `load()`
/// idempotent, `unload()` drops the container and clears the MLX cache. Two instances ship
/// (spec §1): Gemma-2 polish — whose chat template has NO system role, so the system prompt
/// is folded into the user turn — and Qwen3.5 draft with thinking disabled at the template
/// level (the lab scored it with think off); `IntelligencePrompt.sanitize` strips any leak.
public actor MLXTextEngine: TextGenerating {
    private let modelDirectory: @Sendable () -> URL
    private let foldsSystemIntoUser: Bool
    private var container: ModelContainer?

    public init(modelDirectory: @escaping @Sendable () -> URL,
                foldsSystemIntoUser: Bool = false) {
        self.modelDirectory = modelDirectory
        self.foldsSystemIntoUser = foldsSystemIntoUser
    }

    public func load() async throws {
        guard container == nil else { return }
        container = try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(directory: modelDirectory()))
    }

    public func unload() async {
        container = nil
        MLX.GPU.clearCache()
    }

    public func generate(system: String, user: String, temperature: Float) async throws -> String {
        guard let container else { throw IntelligenceEngineError.notLoaded }
        let chat: [Chat.Message] = foldsSystemIntoUser
            ? [.user(system + "\n\n" + user)]
            : [.system(system), .user(user)]
        return try await container.perform { context in
            let input = try await context.processor.prepare(
                input: UserInput(chat: chat, additionalContext: ["enable_thinking": false]))
            var text = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(maxTokens: 1024, temperature: temperature),
                context: context)
            for await item in stream {
                try Task.checkCancellation()   // cancelGeneration() lands here mid-stream
                if case .chunk(let chunk) = item { text += chunk }
            }
            return text
        }
    }
}
```

- [ ] **Step 3: Write `mac/Sources/SidekitIntelligence/ModelDownloader.swift`**

```swift
import Foundation
import Hub
import SidekitCore

/// Owns the model files (spec §6): HF hub snapshots of BOTH models into the app's own
/// folder, presence check, and Settings removal. One download action covers both, with
/// combined progress — no second surprise download mid-flow. AppKit-free; the app injects
/// its root (AppPaths) and logger (Diag).
public final class ModelDownloader: ModelProvisioning, @unchecked Sendable {
    public static let polishRepoID = "mlx-community/gemma-2-2b-it-4bit"
    public static let draftRepoID = "mlx-community/Qwen3-1.7B-4bit"
    private static let repoIDs = [polishRepoID, draftRepoID]

    /// `…/Application Support/Sidekit/Intelligence` in the app; the selftest uses the same.
    public let root: URL
    private let log: @Sendable (String) -> Void

    public init(root: URL, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.root = root
        self.log = log
    }

    /// HubApi snapshot layout: `<root>/models/<org>/<name>`.
    public func snapshotDirectory(for repoID: String) -> URL {
        root.appendingPathComponent("models/\(repoID)", isDirectory: true)
    }

    /// Both snapshots complete — each weights' config marks its snapshot; a partial
    /// download lacks it and the load path then reports "damaged" → re-download (spec §6).
    public var isDownloaded: Bool {
        Self.repoIDs.allSatisfy {
            FileManager.default.fileExists(atPath: snapshotDirectory(for: $0)
                .appendingPathComponent("config.json").path)
        }
    }

    /// ONE action downloads both models in sequence; combined progress 0…1 (spec §6).
    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let hub = HubApi(downloadBase: root)
        let count = Double(Self.repoIDs.count)
        for (index, repoID) in Self.repoIDs.enumerated() {
            let base = Double(index) / count
            _ = try await hub.snapshot(
                from: Hub.Repo(id: repoID),
                matching: ["*.safetensors", "*.json", "*.txt", "*.model"]) { p in
                progress(base + p.fractionCompleted / count)
            }
            log("snapshot complete: \(repoID)")
        }
    }

    public func remove() throws {
        try FileManager.default.removeItem(at: root)
        log("models removed")
    }
}
```

- [ ] **Step 4: Write `mac/Sources/SidekitApp/Adapters/IntelligenceSystemAdapters.swift`**

```swift
import Foundation
import SidekitCore

/// Task.sleep-backed one-shot idle timer (spec §5: warm → unload after the idle window).
final class SystemIntelligenceIdleTimer: IntelligenceIdleTimer {
    private var task: Task<Void, Never>?

    func start(after seconds: Double, _ fire: @escaping @Sendable () -> Void) {
        cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            fire()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// System memory pressure → the session's guest-leaves-now rule (spec §5).
@MainActor
final class MemoryPressureSource {
    private let source: DispatchSourceMemoryPressure

    init(onPressure: @escaping @MainActor () -> Void) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical],
                                                         queue: .main)
        source.setEventHandler {
            Diag.log("intelligence: memory pressure")
            MainActor.assumeIsolated { onPressure() }
        }
        source.activate()
    }
}
```

- [ ] **Step 5: Rewire `IntelligenceSelftest` to the real adapters + real prompts**

Replace `mac/Sources/IntelligenceSelftest/main.swift` entirely with:

```swift
import Foundation
import SidekitCore
import SidekitIntelligence

// Brick-0 gate + permanent headless verifier (spec 2026-06-12 §7) — now driving the REAL
// shipping adapters (SidekitIntelligence) + the REAL prompts (IntelligencePrompt), across
// both models with an explicit role swap (the RAM-guest rule, spec §5).

let root = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Sidekit/Intelligence", isDirectory: true)

func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}

let clock = ContinuousClock()
do {
    let downloader = ModelDownloader(root: root, log: { print("  \($0)") })
    if !downloader.isDownloaded {
        print("downloading \(ModelDownloader.polishRepoID) + \(ModelDownloader.draftRepoID)…")
        var lastDecile = -1
        try await downloader.download { fraction in
            let decile = Int(fraction * 10)
            if decile != lastDecile { print("  download \(decile * 10)%"); lastDecile = decile }
        }
    }
    let polishEngine = MLXTextEngine(
        modelDirectory: { downloader.snapshotDirectory(for: ModelDownloader.polishRepoID) },
        foldsSystemIntoUser: true)   // Gemma-2 has no system role (spec §4)
    let draftEngine = MLXTextEngine(
        modelDirectory: { downloader.snapshotDirectory(for: ModelDownloader.draftRepoID) })

    // Polish on Gemma via the real prompt.
    let polish = IntelligencePrompt.build(chip: .polish, tone: .keepTone)
    var loadStart = clock.now
    try await polishEngine.load()
    print("polish/gemma load: \(loadStart.duration(to: clock.now))")
    var genStart = clock.now
    let polished = IntelligencePrompt.sanitize(try await polishEngine.generate(
        system: polish.system,
        user: "um so basically i think we should uh ship it on tuesday actually no wednesday",
        temperature: polish.temperature))
    print("polish/gemma gen (\(genStart.duration(to: clock.now))): \(polished)")
    if polished.isEmpty { fail("polish returned empty") }
    if !polished.localizedCaseInsensitiveContains("wednesday") { fail("polish lost the correction") }
    await polishEngine.unload()   // role swap: the guest leaves before the next arrives

    // Draft on Qwen via the real prompt.
    let draft = IntelligencePrompt.build(chip: .draftEmail, tone: .professional)
    loadStart = clock.now
    try await draftEngine.load()
    print("draft/qwen load: \(loadStart.duration(to: clock.now))")
    genStart = clock.now
    let drafted = IntelligencePrompt.sanitize(try await draftEngine.generate(
        system: draft.system,
        user: "tell priya the invoice for 4500 dollars went out, ask her to cc me going forward",
        temperature: draft.temperature))
    print("draft/qwen gen (\(genStart.duration(to: clock.now))):\n\(drafted)")
    if drafted.isEmpty { fail("draft returned empty") }
    if drafted.contains("<think>") { fail("thinking leaked") }
    if !drafted.contains("4500") { fail("draft dropped the exact amount") }
    await draftEngine.unload()

    print("PASS")
} catch {
    fail("\(error)")
}
```

- [ ] **Step 6: Build, run the selftest, run the suite**

```bash
cd /Users/omkareshwartripathi/SpeakType/mac
swift build && swift run -c release IntelligenceSelftest && swift test 2>&1 | tail -3
```

Expected: selftest PASS on the already-downloaded model (no re-download — same root as Task 2); suite 181/181.

- [ ] **Step 7: Commit**

```bash
cd /Users/omkareshwartripathi/SpeakType
git add mac/Package.swift mac/Sources/SidekitIntelligence/ mac/Sources/SidekitApp/Adapters/IntelligenceSystemAdapters.swift mac/Sources/IntelligenceSelftest/main.swift
git commit -m "feat(mac): SidekitIntelligence adapters (MLX engine, downloader, timers) + selftest drives shipping code"
```

---

## Task 6 — UI: the scratchpad panel

`IntelligencePanel.swift` — model + view + floating window, the FeedbackBox pattern exactly (KeyablePanel, KeyCatcher Esc, focusToken re-focus, glassCard dark). No AppController changes yet (Task 7 wires it); the file must compile standalone.

**Skill:** none (match DS/FeedbackBox house style; verify = build).

**Files:**
- Create: `mac/Sources/SidekitApp/IntelligencePanel.swift`

- [ ] **Step 1: Write the file**

```swift
import AppKit
import SwiftUI
import SidekitCore

/// Observable bridge over `IntelligenceSession` for the scratchpad (spec §3): input draft,
/// result, status line, tone persistence, clipboard prefill, dictation append.
@MainActor
final class IntelligencePanelModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var result: String?
    @Published private(set) var sessionState: IntelligenceSession.State
    @Published private(set) var errorText: String?
    @Published var tone: IntelligenceTone {
        didSet { UserDefaults.standard.set(tone.rawValue, forKey: Self.toneKey) }
    }
    @Published private(set) var focusToken = 0
    @Published private(set) var copied = false

    private static let toneKey = "IntelligenceTone"
    let session: IntelligenceSession
    private let provisioner: any ModelProvisioning

    init(session: IntelligenceSession, provisioner: any ModelProvisioning) {
        self.session = session
        self.provisioner = provisioner
        self.sessionState = session.state
        self.tone = UserDefaults.standard.string(forKey: Self.toneKey)
            .flatMap(IntelligenceTone.init(rawValue:)) ?? .keepTone
        session.onStateChanged = { [weak self] state in self?.sessionState = state }
        session.onResult = { [weak self] text in
            self?.result = text
            self?.errorText = nil
        }
        session.onError = { [weak self] message in
            self?.errorText = message
            Diag.log("intelligence: \(message)")   // spec §9: every failure logged
        }
    }

    var busy: Bool {
        sessionState == .loading || sessionState == .generating
    }

    /// Chips run only from ready/warm (spec §5) — and only with text present (view-side).
    var chipsEnabled: Bool { sessionState == .ready || sessionState == .warm }

    /// The honest status line (spec §3/§5). nil → line hidden.
    var statusText: String? {
        if let errorText { return errorText }
        switch sessionState {
        case .downloading(let p): return "Downloading… \(Int(p * 100))%"
        case .loading: return "Warming up…"
        case .generating: return "Drafting…"
        case .needsModel, .ready, .warm: return nil
        }
    }

    func run(_ chip: IntelligenceChip) {
        errorText = nil
        session.run(chip: chip, tone: tone, input: input)
    }

    func cancel() { session.cancelGeneration() }
    func download() { errorText = nil; session.requestDownload() }

    func copyResult() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    /// Iterate: the result becomes the next input (spec §3 — the editor is never
    /// overwritten BY a generation; only this explicit tap moves text).
    func useAsInput() {
        guard let result else { return }
        input = result
        self.result = nil
    }

    func clear() {
        input = ""
        result = nil
        errorText = nil
    }

    /// Settings → Remove model (spec §6): delete the files, drop the session to needsModel.
    func removeModel() {
        do {
            try provisioner.remove()
            session.modelRemoved()
        } catch {
            errorText = "Couldn't remove the model files."
        }
    }

    /// Append a dictated transcript (NotesStore separator rule — FeedbackModel precedent).
    func appendDictated(_ text: String) {
        if input.isEmpty || input.last!.isWhitespace { input += text }
        else { input += " " + text }
    }

    /// Per open: clear stale toasts/errors, optionally prefill from the clipboard
    /// (Polish entry, spec §2 — whitespace-trim only, over-cap shows the honest message).
    func reopened(prefillFromClipboard: Bool, preselect: IntelligenceChip?) {
        errorText = nil
        copied = false
        if prefillFromClipboard,
           let clip = NSPasteboard.general.string(forType: .string) {
            let trimmed = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                input = trimmed
                result = nil
                if case .tooLong = IntelligencePrompt.check(trimmed) {
                    errorText = IntelligencePrompt.tooLongMessage
                }
            }
        }
        highlightedChip = preselect
        focusToken += 1
    }

    /// The Polish pill entry highlights its chip (spec §2) — visual hint only; the tap runs it.
    @Published var highlightedChip: IntelligenceChip?
}

/// The scratchpad (spec §3): editor → chips → tone → result → status. Esc closes, draft survives.
struct IntelligenceView: View {
    @ObservedObject var model: IntelligencePanelModel
    let onClose: () -> Void
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Scratchpad").font(DS.Typography.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                if !model.input.isEmpty || model.result != nil {
                    Button("Clear") { model.clear() }.buttonStyle(.plain)
                        .font(DS.Typography.caption).foregroundStyle(.tertiary)
                }
            }

            ZStack(alignment: .topLeading) {
                if model.input.isEmpty {
                    Text("Type — or hold Fn and just say it.")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $model.input)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .frame(height: 110)
            }
            .padding(DS.Space.sm)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: DS.Space.sm) {
                ForEach(IntelligenceChip.allCases, id: \.self) { chip in
                    Button(chip.label) { model.run(chip) }
                        .buttonStyle(.bordered)
                        .tint(model.highlightedChip == chip ? DS.Palette.accent : .secondary)
                        .disabled(model.input.isEmpty || !model.chipsEnabled)
                }
            }

            Picker("Tone", selection: $model.tone) {
                ForEach(IntelligenceTone.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            if let result = model.result {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    ScrollView { 
                        Text(result).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                    HStack {
                        Button(model.copied ? "Copied ✓" : "Copy") { model.copyResult() }
                            .buttonStyle(.borderedProminent)
                        Button("Use as input") { model.useAsInput() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(DS.Space.sm)
                .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            }

            statusLine
        }
        .padding(DS.Space.lg)
        .frame(width: 460)
        .glassCard()
        .background(IntelligenceKeyCatcher(onEscape: onClose))
        .onAppear { editorFocused = true }
        .onChange(of: model.focusToken) { editorFocused = true }
        .tint(DS.Palette.accent)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var statusLine: some View {
        if model.sessionState == .needsModel {
            HStack {
                if let error = model.statusText {
                    Text(error).font(DS.Typography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                // Disk size measured by the Task-2 gate run — update if the model changes.
                Button(model.statusText == nil ? "Download models (≈2.7 GB, one time)" : "Retry") {
                    model.download()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let status = model.statusText {
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(status).font(DS.Typography.caption).foregroundStyle(.secondary)
                Spacer()
                if model.sessionState == .generating {
                    Button("Cancel") { model.cancel() }.buttonStyle(.bordered)
                }
            }
        }
    }
}

/// Esc-to-close for the borderless panel (FeedbackBox's KeyCatcher, same shape).
private struct IntelligenceKeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> EscapeView {
        let view = EscapeView()
        view.onEscape = onEscape
        return view
    }
    func updateNSView(_ nsView: EscapeView, context: Context) { nsView.onEscape = onEscape }

    final class EscapeView: NSView {
        var onEscape: (() -> Void)?
        private nonisolated(unsafe) var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53, self?.window?.isKeyWindow == true {
                    self?.onEscape?()
                    return nil
                }
                return event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// The scratchpad's floating window: borderless glass, activating and keyable (the user is
/// deliberately here to type/dictate) — FeedbackBox's species, anchored above the pill.
@MainActor
final class IntelligencePanel {
    let model: IntelligencePanelModel
    private let panel: KeyablePanel

    /// Dictation routes here while the panel is key (RoutingSink chain, spec §3).
    var isKey: Bool { panel.isKeyWindow }

    init(session: IntelligenceSession, provisioner: any ModelProvisioning) {
        model = IntelligencePanelModel(session: session, provisioner: provisioner)
        let canvas = NSRect(x: 0, y: 0, width: 480, height: 420)
        panel = KeyablePanel(contentRect: canvas, styleMask: [.borderless],
                             backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView:
            IntelligenceView(model: model, onClose: { [weak self] in self?.hide() }))
        hosting.frame = canvas
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
    }

    /// Anchor above the pill (bottom-center; the pill canvas is 90 pt tall at minY+24).
    func show(prefillFromClipboard: Bool = false, preselect: IntelligenceChip? = nil) {
        model.reopened(prefillFromClipboard: prefillFromClipboard, preselect: preselect)
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2,
                                         y: area.minY + 24 + 90 + 12))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() { panel.orderOut(nil) }

    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/omkareshwartripathi/SpeakType/mac
swift build
```

Expected: clean build (the panel isn't constructed anywhere yet — that's Task 7). `swift test 2>&1 | tail -3` → still 181/181.

- [ ] **Step 3: Commit**

```bash
cd /Users/omkareshwartripathi/SpeakType
git add mac/Sources/SidekitApp/IntelligencePanel.swift
git commit -m "feat(mac): scratchpad panel — editor, chips, tone, result, honest status (FeedbackBox pattern)"
```

---

## Task 7 — Wiring + pill hover menu + Dictate (manual verify)

Make it real: AppController builds the session/panel, the dictation routing chain gains the scratchpad, and the pill becomes interactive for the first time (hover menu, dot-click opens the window, hands-free Dictate). Includes one spec erratum fix.

**Skill:** none (UI/interaction brick — verify manually on the Mac; superpowers:verification-before-completion).

**Files:**
- Modify: `mac/Sources/SidekitApp/App.swift`
- Modify: `mac/Sources/SidekitApp/PillView.swift`
- Modify: `mac/Sources/SidekitApp/PillPanel.swift`
- Modify: `docs/superpowers/specs/2026-06-12-sidekit-intelligence-v1-design.md` (erratum)

- [ ] **Step 1: Spec erratum** — §2 claims dot-click-opens-window is "existing behavior, kept". The pill is actually fully click-through today (`PillPanel.ignoresMouseEvents = true`; click-to-open was never built). In the spec §2 bullet, replace:

`**Clicking the dot itself** still opens the main window (existing behavior, kept).`

with:

`**Clicking the dot itself** opens the main window (the behavior the UI-redesign spec promised; the pill was click-through until now — this task makes it interactive).`

- [ ] **Step 2: `PillPanel.swift` — accept mouse events**

Replace the `ignoresMouseEvents` line and its comment:

```swift
        // Interactive since Intelligence v1 (spec 2026-06-12 §2): hover expands the menu,
        // the dot click opens the window. Clicks on fully transparent canvas pixels still
        // pass through to whatever is beneath (per-pixel hit testing on non-opaque windows).
        panel.ignoresMouseEvents = false
```

Also update the type comment's "Click-through for now (informational only)…" sentence to: `Interactive: hover expands the Intelligence menu (spec 2026-06-12 §2).`

- [ ] **Step 3: `PillView.swift` — hover menu + clicks**

Add to `PillView` (alongside the existing `@State`s):

```swift
    @State private var hovering = false
```

Replace the `case .idle:` body in `content` with:

```swift
        case .idle:
            ZStack {
                // A near-invisible pad widens the hover/click target beyond the 28×5 dot
                // (spec §2: ≥80×30). Live-tune the opacity upward only if hover fails to
                // register (per-pixel hit testing ignores fully transparent pixels).
                Capsule().fill(.white.opacity(0.02)).frame(width: 120, height: 32)
                if hovering {
                    HStack(spacing: DS.Space.sm) {
                        pillMenuButton("sparkles", "Polish") { controller.pillPolish() }
                        pillMenuButton("square.and.pencil", "Scratchpad") { controller.pillScratchpad() }
                        pillMenuButton("mic.fill", "Dictate") { controller.pillDictate() }
                    }
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                    .glassCard(cornerRadius: DS.Radius.pill)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(width: 28, height: 5)
                        .scaleEffect(breathing ? 1.0 : 0.85)
                        .opacity(breathing ? 0.55 : 0.3)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                            value: breathing)
                        .contentShape(Capsule().scale(2))
                        .onTapGesture { controller.pillOpenWindow() }
                }
            }
            .onHover { hovering = $0 }
            .animation(morph, value: hovering)
```

Add the recording-state stop affordance — on the existing `case .recording:` glass pill, append after `.transition(.scale.combined(with: .opacity))`:

```swift
            .contentShape(Capsule())
            .onTapGesture { controller.pillStopDictate() }   // hands-free only; Fn-held ignores it
```

Add the button helper next to `glassPill`:

```swift
    private func pillMenuButton(_ symbol: String, _ label: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(label).font(DS.Typography.caption)
            }
            .foregroundStyle(DS.Palette.textPrimary)
        }
        .buttonStyle(.plain)
    }
```

And clear `hovering` when a dictation starts — in `handleStateChange`, inside `case .recording:` add `hovering = false`.

- [ ] **Step 4: `App.swift` — build the brain, chain the routing, expose the pill actions**

In `AppController`, add stored properties (near `feedbackBox`):

```swift
    private var intelligencePanel: IntelligencePanel?
    private var memoryPressure: MemoryPressureSource?
    /// True while a pill-button (hands-free) dictation is running — pill click stops it;
    /// Fn-held cycles never set it (spec §2).
    private var handsFreeActive = false
```

And an accessor for Settings (Task 8 uses it):

```swift
    var intelligence: IntelligencePanelModel? { intelligencePanel?.model }
```

In `init()`, right after the `welcomePanel` line, create the Intelligence stack:

```swift
        // Sidekit Intelligence (spec 2026-06-12): two role-specific models, loaded on
        // demand, one warm at a time — the RAM-guest lifecycle lives in the core session.
        let downloader = ModelDownloader(
            root: AppPaths.applicationSupport.appendingPathComponent("Intelligence", isDirectory: true),
            log: { Diag.log("intelligence: \($0)") })
        let intelligenceSession = IntelligenceSession(
            polishEngine: MLXTextEngine(
                modelDirectory: { downloader.snapshotDirectory(for: ModelDownloader.polishRepoID) },
                foldsSystemIntoUser: true),   // Gemma-2 has no system role (spec §4)
            draftEngine: MLXTextEngine(
                modelDirectory: { downloader.snapshotDirectory(for: ModelDownloader.draftRepoID) }),
            provisioner: downloader,
            idle: SystemIntelligenceIdleTimer())
        let intelligencePanel = IntelligencePanel(session: intelligenceSession,
                                                  provisioner: downloader)
```

(Add `import SidekitIntelligence` at the top of App.swift.)

In the `RoutingSink` closure, extend the key-window chain:

```swift
                    if feedbackBox.isKey {
                        feedbackBox.model.appendDictated(text)
                    } else if intelligencePanel.isKey {
                        // Spec §3: the scratchpad outranks the notes while it's key.
                        intelligencePanel.model.appendDictated(text)
                    } else {
```

After `self.feedbackBox = feedbackBox`, add:

```swift
        self.intelligencePanel = intelligencePanel
```

After the `pill = PillPanel(controller: self)` line, add:

```swift
        // The guest leaves the moment the house is full (spec §5).
        memoryPressure = MemoryPressureSource { [weak self] in
            self?.intelligencePanel?.model.session.memoryPressure()
        }
```

In `coordinator.onStateChanged`, add inside the closure (after the existing lines):

```swift
            if newState == .idle { self?.handsFreeActive = false }
```

And add the pill actions (near `showFeedbackBox`):

```swift
    // MARK: Pill menu (spec 2026-06-12 §2)

    func pillPolish() { intelligencePanel?.show(prefillFromClipboard: true, preselect: .polish) }
    func pillScratchpad() { intelligencePanel?.show() }

    /// Hands-free dictation: Fn without the holding. Click the pill to stop.
    func pillDictate() {
        guard state == .idle else { return }
        handsFreeActive = true
        coordinator.pressed()
    }

    /// Stops a hands-free recording only — Fn-held cycles end on Fn release as always.
    func pillStopDictate() {
        guard handsFreeActive else { return }
        handsFreeActive = false
        Task { @MainActor in await coordinator.released() }
    }

    func pillOpenWindow() {
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }
```

- [ ] **Step 5: Build + suite**

```bash
cd /Users/omkareshwartripathi/SpeakType/mac
swift build && swift test 2>&1 | tail -3
```

Expected: clean, 181/181.

- [ ] **Step 6: Manual verification (signed .app — the real surface)**

```bash
cd /Users/omkareshwartripathi/SpeakType/mac && ./Scripts/build-app.sh release && open .build/Sidekit.app
```

Walk, in order (these become TESTING.md §11 in Task 8):
1. Hover the idle dot → three buttons bloom; mouse away → collapses. (If hover never fires, bump the pad opacity 0.02 → 0.05 and rebuild — note the final value.)
2. Click **Scratchpad** → panel opens above the pill, editor focused. Type rough notes → tap **Draft email** → first use offers the download → progress → "Warming up…" → "Drafting…" → an email appears. **Copy** → paste into TextEdit.
3. Copy any sentence to the clipboard → pill → **Polish** → editor pre-filled, Polish chip highlighted → tap it (tone: Keep tone) → faithful cleanup appears. (Coming right after the draft, this is the Qwen→Gemma model swap — expect “Warming up…” again.)
4. Tone **Professional** + **Polish** → re-toned rewrite.
5. With the panel key: hold **Fn**, speak → words land in the editor, not pasted elsewhere.
6. Pill → **Dictate** → pill shows Listening without any key held → click the pill → text routes exactly like an Fn dictation.
7. Esc closes the panel; reopen → draft text still there.
8. Watch Activity Monitor → Sidekit's memory drops ~2 GB within ~3 min of the last generation.
9. Click the idle dot → main window opens.

- [ ] **Step 7: Commit**

```bash
cd /Users/omkareshwartripathi/SpeakType
git add mac/Sources/SidekitApp/App.swift mac/Sources/SidekitApp/PillView.swift mac/Sources/SidekitApp/PillPanel.swift docs/superpowers/specs/2026-06-12-sidekit-intelligence-v1-design.md
git commit -m "feat(mac): pill hover menu (Polish/Scratchpad/Dictate) + Intelligence wiring + hands-free dictation"
```

---

## Task 8 — Settings row + TESTING.md §11 + BRICKS.md

**Skill:** none (docs + one small Settings section; verification-before-completion).

**Files:**
- Modify: `mac/Sources/SidekitApp/SettingsPanel.swift`
- Modify: `mac/Sources/SidekitApp/MainWindow.swift` (pass-through)
- Modify: `mac/Sources/SidekitApp/App.swift` (pass-through)
- Modify: `mac/TESTING.md`
- Modify: `BRICKS.md`

- [ ] **Step 1: Surface model state in Settings (spec §6)**

`SettingsView` gains the intelligence model. Add a property after `identity`:

```swift
    /// The Intelligence panel model — drives the model-state row (spec 2026-06-12 §6).
    /// Optional: nil only in previews/tests that don't build the stack.
    var intelligence: IntelligencePanelModel?
```

Add a new `Section` between `Section("Shelf")` and `Section("Permissions")`:

```swift
                Section("Intelligence") {
                    if let intelligence {
                        IntelligenceSettingsRow(model: intelligence)
                    } else {
                        Text("Unavailable").foregroundStyle(.secondary)
                    }
                }
```

Append at file end:

```swift
/// Model presence + removal (spec §6). State reads from the live session; Remove drops the
/// files and tells the session, so the next chip use re-offers the download.
private struct IntelligenceSettingsRow: View {
    @ObservedObject var model: IntelligencePanelModel

    var body: some View {
        if model.sessionState == .needsModel {
            Text("On-device model: not downloaded — the Scratchpad offers it on first use.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            HStack {
                Text("On-device model: downloaded")
                Spacer()
                Button("Remove model", role: .destructive) { model.removeModel() }
            }
            Text("Frees the disk space; the Scratchpad re-offers the download when needed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

(`removeModel()` already exists on `IntelligencePanelModel` — Task 6 built it.)

Wire the pass-through: in `MainWindow.swift` add `let intelligence: IntelligencePanelModel?` after `let shelf`, and change the sheet line to:

```swift
        .sheet(isPresented: $showSettings) { SettingsView(model: settings, shelf: shelf, identity: identity, intelligence: intelligence) }
```

In `App.swift`'s `Window` scene, add `intelligence: controller.intelligence` to the `MainWindow(...)` call.

- [ ] **Step 2: Build + suite**

```bash
cd /Users/omkareshwartripathi/SpeakType/mac && swift build && swift test 2>&1 | tail -3
```

Expected: clean, 181/181. Quick manual: open Settings → Intelligence shows "downloaded" (the dev machine has it from Task 2) — do NOT click Remove (keep the model for the M11 pass).

- [ ] **Step 3: TESTING.md §11** — append a new section following §10's exact format, items:
  - m11-1 hover expand/collapse; m11-2 scratchpad draft-email end-to-end (download → warm → draft → Copy → paste); m11-3 Polish clipboard pre-fill + faithful clean; m11-4 Polish + Professional re-tone run right after a draft chip (exercises the Gemma↔Qwen model swap — “Warming up…” shows again); m11-5 Fn dictation into the focused scratchpad; m11-6 Dictate button hands-free cycle (click pill stops); m11-7 Esc keeps the draft; m11-8 RAM drops ~2 GB ≤ ~3 min after last generation (Activity Monitor); m11-9 dot click opens main window; m11-10 Settings Remove model → scratchpad re-offers download; m11-11 offline: downloaded model still drafts / undownloaded shows the offline message.
  Mark machine-verifiable ones per the §10 convention; update the intro/§0 test counts (152 → 181) and add sign-off row 11.

- [ ] **Step 4: BRICKS.md** — per CLAUDE.md §2b: add the consolidated Done entry (top of Done (Mac)): what ships, files, `swift test` 181/181 + selftest timings (from Task 2/5 output) + M11 status, review fixes, decisions (RAM-guest, two-model split + Gate A results, hover-pad opacity if tuned), follow-ups (streaming output if budgets feel slow; auto-polish toggle still future; clipboard-capture question still open). Remove the **LLM-POLISH** bullet from "Next iterations" (SKILLS-FOR-SMALL-MODELS stays). Archive the oldest Done entry beyond 3 to `BRICKS-ARCHIVE.md` (prepend verbatim).

- [ ] **Step 5: Commit**

```bash
cd /Users/omkareshwartripathi/SpeakType
git add mac/Sources/SidekitApp/SettingsPanel.swift mac/Sources/SidekitApp/MainWindow.swift mac/Sources/SidekitApp/App.swift mac/TESTING.md BRICKS.md BRICKS-ARCHIVE.md
git commit -m "feat(mac): Settings Intelligence row + TESTING §11 (M11) + BRICKS handoff for Intelligence v1"
```

---

## Execution notes for the controller

- Tasks are strictly ordered: 1 and 2 are gates (each can return BLOCKED with a user decision); 3–4 are pure TDD; 5 depends on 2+3+4; 6 on 3–5; 7 on 6; 8 on 7.
- Task 2 and 5 carry the third-party drift rule; if an implementer reports NEEDS_CONTEXT on MLX API names, point them at the resolved checkout under `mac/.build/checkouts/mlx-swift-examples/Libraries/MLXLMCommon/` — the source is the documentation.
- Tasks 2 and 5 download/run ~2.7 GB of models (two snapshots) — run them one at a time, never in parallel with anything heavy (gentle-thermal applies to the Mac, not just the lab).
- Manual steps in Task 7 step 6 need the human only if the controller cannot drive the UI via the established Accessibility-scripting harness; dictation (m11-5/6) and the visual taste check always need the human.
