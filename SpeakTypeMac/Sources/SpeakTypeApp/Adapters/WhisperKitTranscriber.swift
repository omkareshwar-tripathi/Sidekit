// @preconcurrency: WhisperKit predates strict concurrency and its types aren't Sendable;
// the actor serializes all access, so calling its async API is safe here.
@preconcurrency import WhisperKit
import SpeakTypeCore

/// On-device transcription via WhisperKit (CoreML / Neural Engine). The model is loaded
/// lazily on first use — WhisperKit downloads it on first run, so launch isn't blocked.
/// An `actor` serializes model load + inference; fail-open (empty string → the coordinator
/// treats it as no-speech) so a model/inference error never crashes a dictation.
actor WhisperKitTranscriber: Transcribing {
    private let model: String
    private var pipe: WhisperKit?

    init(model: String = "base.en") {
        self.model = model
    }

    func transcribe(_ samples: [Float]) async -> String {
        do {
            let whisper = try await ready()
            let results: [TranscriptionResult] = try await whisper.transcribe(audioArray: samples)
            return results.map(\.text).joined(separator: " ")
        } catch {
            return ""
        }
    }

    private func ready() async throws -> WhisperKit {
        if let pipe { return pipe }
        let whisper = try await WhisperKit(WhisperKitConfig(model: model))
        pipe = whisper
        return whisper
    }
}
