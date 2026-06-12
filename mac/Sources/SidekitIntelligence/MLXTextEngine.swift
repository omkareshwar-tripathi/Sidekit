import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import Tokenizers
import SidekitCore

public enum IntelligenceEngineError: Error { case notLoaded }

/// MLXLLM-backed `TextGenerating` (spec §5/§8). An actor: one model in RAM, `load()`
/// idempotent, `unload()` drops the container and clears the MLX cache. Two instances ship
/// (spec §1): Gemma-2 polish — whose chat template has NO system role, so the system prompt
/// is folded into the user turn — and Qwen3-1.7B draft with thinking disabled at the template
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

    /// Loads the model from the local snapshot directory. Idempotent — returns immediately
    /// if already loaded.
    ///
    /// API drift note (mlx-swift-lm 3.31.3): `loadContainer(from:using:)` takes a local
    /// directory URL directly, bypassing any download step. The `#huggingFaceTokenizerLoader()`
    /// macro produces the required `TokenizerLoader`. No `#hubDownloader` needed here since
    /// the model is already on disk (ModelDownloader handles that separately).
    public func load() async throws {
        guard container == nil else { return }
        let tokenizerLoader = #huggingFaceTokenizerLoader()
        container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory(),
            using: tokenizerLoader)
    }

    /// Drops the loaded model from RAM and clears the MLX cache.
    ///
    /// API drift note: `GPU.clearCache()` deprecated; use `Memory.clearCache()`.
    public func unload() async {
        container = nil
        Memory.clearCache()
    }

    /// Runs one generation pass. `system` + `user` are shaped into the chat template;
    /// for Gemma (foldsSystemIntoUser = true) they are concatenated into a single user
    /// turn because Gemma's template has no system role.
    ///
    /// API drift note: `Chat.Message` is non-Sendable (contains image/video arrays).
    /// Values are constructed inside `container.perform { context in }` where Swift 6
    /// does not enforce Sendable transfer. The tuples (role, content) cross the actor
    /// boundary as plain Sendable values.
    public func generate(system: String, user: String, temperature: Float) async throws -> String {
        guard let container else { throw IntelligenceEngineError.notLoaded }

        // Capture Sendable tuple pair; reconstruct Chat.Message inside perform.
        let roleTuples: [(Chat.Message.Role, String)] = foldsSystemIntoUser
            ? [(.user, system + "\n\n" + user)]
            : [(.system, system), (.user, user)]

        return try await container.perform { context in
            let chat = roleTuples.map { Chat.Message(role: $0.0, content: $0.1) }
            let input = try await context.processor.prepare(
                input: UserInput(chat: chat, additionalContext: ["enable_thinking": false]))
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(maxTokens: 1024, temperature: temperature),
                context: context)
            var text = ""
            for await item in stream {
                try Task.checkCancellation()   // cancelGeneration() lands here mid-stream
                if case .chunk(let chunk) = item { text += chunk }
            }
            return text
        }
    }
}
