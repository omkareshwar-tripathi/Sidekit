// @preconcurrency: WhisperKit predates strict concurrency and its types aren't Sendable;
// the actor serializes all access, so calling its async API is safe here.
@preconcurrency import WhisperKit
import Foundation
import SidekitCore

/// On-device transcription via WhisperKit (CoreML / Neural Engine). Loads the model lazily
/// on first use. When `modelFolder` is given (the model bundled into the app), it loads
/// fully offline — no download. An `actor` serializes load + inference; fail-open (empty
/// string → no-speech) so a model/inference error never crashes a dictation, and the error
/// is logged so failures are visible.
actor WhisperKitTranscriber: Transcribing {
    private let modelFolder: String?
    private let modelName: String
    private var pipe: WhisperKit?

    init(modelFolder: URL? = nil, modelName: String = "base.en") {
        self.modelFolder = modelFolder?.path
        self.modelName = modelName
    }

    func transcribe(_ samples: [Float]) async -> String {
        do {
            let whisper = try await ready()
            let results: [TranscriptionResult] = try await whisper.transcribe(audioArray: samples)
            return results.map(\.text).joined(separator: " ")
        } catch {
            FileHandle.standardError.write(Data("SpeakType: transcription failed: \(error)\n".utf8))
            return ""
        }
    }

    private func ready() async throws -> WhisperKit {
        if let pipe { return pipe }
        let config = modelFolder != nil
            ? WhisperKitConfig(modelFolder: modelFolder)   // bundled → offline
            : WhisperKitConfig(model: modelName)            // fallback → download
        let whisper = try await WhisperKit(config)
        pipe = whisper
        return whisper
    }
}
