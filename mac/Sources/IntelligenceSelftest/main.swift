import Foundation
import os
import HuggingFace
import Tokenizers
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace

// Brick-0 gate + permanent headless verifier for the on-device LLMs (spec 2026-06-12 §7).
// Two-model variant (Gate A outcome): Gemma-2-2B polishes (its chat template has NO system
// role — fold the system prompt into the user turn), Qwen3.5-2B drafts (thinking off).
// Downloads on first run into the app's own Intelligence folder, then per model:
// load → canned generation → unload, printing timings. Exits non-zero on any failure.
// Budgets (spec §5): warm-disk load ≤ 5 s; each generation ≤ 8 s.
// Task 5 rewires this to drive the real MLXTextEngine adapter + IntelligencePrompt.
//
// API drift note (mlx-swift-lm 3.31.3):
//   - MLXLLM/MLXLMCommon moved from mlx-swift-examples to mlx-swift-lm (PR #441).
//   - loadContainer now requires explicit Downloader + TokenizerLoader args.
//   - Chat.Message is non-Sendable (contains image/video arrays); pass as [(role, content)]
//     tuples and reconstruct inside perform { context in } to satisfy Swift 6.
//   - GPU.clearCache() / GPU.snapshot() deprecated; Memory.clearCache() / Memory.snapshot().
//   - additionalContext: ["enable_thinking": false] on UserInput is present and functional.
//   - HubClient custom cache: HubClient(cache: HubCache(cacheDirectory: url)).

let polishRepo = "mlx-community/gemma-2-2b-it-4bit"
// mlx-community/Qwen3.5-2B-OptiQ-4bit is a VLM (Qwen3_5ForConditionalGeneration) — multimodal
// architecture causes garbage LLM output. Substituting the registered text-only preset.
let draftRepo  = "mlx-community/Qwen3-1.7B-4bit"
let root = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Sidekit/Intelligence", isDirectory: true)

// Short canned prompts for the gate only — Task 3's IntelligencePrompt replaces these in Task 5.
let polishSystem = """
You clean raw speech-to-text transcripts. Rules:
1. Remove filler words: um, uh, basically, like, so, well.
2. When a speaker self-corrects ("X — no, Y" or "X actually Y"), KEEP the correction (Y) and DROP the false start (X).
3. Fix casing and punctuation.
4. Output only the cleaned transcript, nothing else.
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

// Sendable representation of a text-only chat turn.
typealias Turn = (role: Chat.Message.Role, content: String)

/// Load → generate once → free — the RAM-guest rule holds even in the gate.
///
/// `turns` uses `Chat.Message.Role` (Sendable enum) + String, so the array is Sendable.
/// The full `Chat.Message` values are constructed inside `perform { }` (actor-isolated) where
/// Swift 6 doesn't enforce Sendable transfer.
func runOnce(
    id: String,
    turns: [Turn],
    additionalContext: [String: any Sendable]?,
    temperature: Float,
    label: String
) async throws -> String {
    let downloader = #hubDownloader(HubClient(cache: HubCache(cacheDirectory: root)))
    let tokenizerLoader = #huggingFaceTokenizerLoader()

    // Progress is coarse-grained (10%-steps); locked counter satisfies @Sendable closure.
    let lastPercent = OSAllocatedUnfairLock(initialState: -1)
    let loadStart = clock.now
    let container = try await LLMModelFactory.shared.loadContainer(
        from: downloader,
        using: tokenizerLoader,
        configuration: ModelConfiguration(id: id)
    ) { progress in
        let percent = Int(progress.fractionCompleted * 100)
        let old = lastPercent.withLock { v -> Int in let o = v; v = percent; return o }
        if percent / 10 != old / 10 { print("  \(label) download \(percent)%") }
    }
    print("\(label) load: \(loadStart.duration(to: clock.now))")

    let genStart = clock.now
    // Build Chat.Message values and UserInput inside the actor (perform { context }).
    // Chat.Message is non-Sendable, so it must stay inside the actor context.
    let result: String = try await container.perform { context in
        let chat = turns.map { Chat.Message(role: $0.role, content: $0.content) }
        let input = try await context.processor.prepare(
            input: UserInput(chat: chat, additionalContext: additionalContext))
        let stream = try MLXLMCommon.generate(
            input: input,
            parameters: GenerateParameters(maxTokens: 1024, temperature: temperature),
            context: context)
        var text = ""
        for await item in stream {
            switch item {
            case .chunk(let chunk): text += chunk
            case .info(let info):
                print("\(label) gen (\(genStart.duration(to: clock.now))): \(info.tokensPerSecond) tok/s")
            case .toolCall: break
            }
        }
        return text
    }
    print("\(label) output:\n\(result)\n")
    Memory.clearCache()
    return result
}

do {
    func diskBytes(at url: URL) -> Int {
        var total = 0
        if let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let u as URL in files {
                total += (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            }
        }
        return total
    }

    // Polish on Gemma — NO system role: the system prompt rides the user turn.
    let polished = try await runOnce(
        id: polishRepo,
        turns: [
            (role: .user, content: polishSystem + "\n\n" +
             "um so basically i think we should uh ship it on tuesday actually no wednesday"),
        ],
        additionalContext: nil,
        temperature: 0.2,
        label: "polish/gemma"
    )
    if polished.isEmpty { fail("polish returned empty") }
    if !polished.localizedCaseInsensitiveContains("wednesday") { fail("polish lost the correction") }

    // Draft on Qwen — native system role, thinking off.
    let drafted = try await runOnce(
        id: draftRepo,
        turns: [
            (role: .system, content: draftSystem),
            (role: .user,   content: "tell priya the invoice for 4500 dollars went out, ask her to cc me going forward"),
        ],
        additionalContext: ["enable_thinking": false],
        temperature: 0.7,
        label: "draft/qwen"
    )
    if drafted.isEmpty { fail("draft returned empty") }
    if drafted.contains("<think>") { fail("thinking mode leaked into draft output") }
    if !drafted.contains("4500") { fail("draft dropped the exact amount") }

    let diskGB = Double(diskBytes(at: root)) / 1_073_741_824
    print(String(format: "disk: %.2f GB total", diskGB))
    print("gpu memory: \(Memory.snapshot())")
    print("PASS")
} catch {
    fail("\(error)")
}
